#include "flash.hpp"

#include <fcntl.h>
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>

#include <cerrno>
#include <cstdlib>

#include "store.hpp"

namespace serial {
namespace {
constexpr size_t kEventCapacity = 256;
// A negative pid targets the private group created by setsid.
void terminate_group(pid_t pid, int signal_number) {
    if (pid > 1) ::kill(-pid, signal_number);
}
void read_lines(int fd, Channel<FlashEvent>& tx, std::atomic<size_t>& dropped) {
    char chunk[4096];
    Bytes line;
    line.reserve(kFlashMaxLine);
    bool truncated = false;
    while (true) {
        const ssize_t count = ::read(fd, chunk, sizeof chunk);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) break;
        for (ssize_t i = 0; i < count; ++i) {
            const auto byte = static_cast<uint8_t>(chunk[i]);
            if (byte == '\n') {
                emit_flash_line(tx, dropped, line, truncated);
                line.clear();
                truncated = false;
            } else if (line.size() < kFlashMaxLine) {
                line.push_back(byte);
            } else {
                truncated = true;
            }
        }
    }
    if (!line.empty() || truncated) emit_flash_line(tx, dropped, line, truncated);
    ::close(fd);
}
}  // namespace
void emit_flash_line(Channel<FlashEvent>& tx, std::atomic<size_t>& dropped, const Bytes& bytes, bool truncated) {
    std::string line = decode_bytes(Encoding::Utf8, bytes);
    if (line.ends_with('\r')) line.pop_back();
    if (truncated) line += kFlashTruncation;
    if (tx.try_send(FlashEvent{FlashEvent::Kind::Line, std::move(line)}) == Channel<FlashEvent>::Result::Full) dropped.fetch_add(1, std::memory_order_relaxed);
}
std::expected<std::unique_ptr<Flash>, std::string> Flash::start(const std::string& command, const std::string& directory) {
    if (trim_text(command).empty()) return std::unexpected("烧录命令不能为空");
    const char* configured = std::getenv("SERIAL_MAYON_SHELL");
    const std::string shell = configured != nullptr && !trim_text(configured).empty() ? configured : "sh";
    const std::string cwd = trim_text(directory).empty() ? "." : directory;
    int out[2], err[2], report[2];
    if (::pipe2(out, O_CLOEXEC) != 0) return std::unexpected(os_error(errno));
    if (::pipe2(err, O_CLOEXEC) != 0) {
        const int error = errno;
        ::close(out[0]);
        ::close(out[1]);
        return std::unexpected(os_error(error));
    }
    if (::pipe2(report, O_CLOEXEC) != 0) {
        const int error = errno;
        for (const int fd : {out[0], out[1], err[0], err[1]}) ::close(fd);
        return std::unexpected(os_error(error));
    }
    const char* const argv[] = {shell.c_str(), "-c", command.c_str(), nullptr};
    const pid_t pid = ::fork();
    if (pid < 0) {
        const int error = errno;
        for (const int fd : {out[0], out[1], err[0], err[1], report[0], report[1]}) ::close(fd);
        return std::unexpected(os_error(error));
    }
    if (pid == 0) {
        // Only async-signal-safe calls: other threads existed when this process forked.
        // The private session lets cancel end the shell and its children without touching the TUI.
        const auto die = [&] {
            const int error = errno;
            [[maybe_unused]] const auto ignored = ::write(report[1], &error, sizeof error);
            ::_exit(127);
        };
        if (::setsid() == -1 || ::chdir(cwd.c_str()) != 0) die();
        const int null = ::open("/dev/null", O_RDONLY);
        if (null < 0 || ::dup2(null, STDIN_FILENO) < 0 || ::dup2(out[1], STDOUT_FILENO) < 0 || ::dup2(err[1], STDERR_FILENO) < 0) die();
        for (const int number : {SIGPIPE, SIGINT, SIGTERM, SIGHUP, SIGWINCH}) ::signal(number, SIG_DFL);
        sigset_t none;
        ::sigemptyset(&none);
        ::sigprocmask(SIG_SETMASK, &none, nullptr);
        ::execvp(argv[0], const_cast<char* const*>(argv));
        die();
    }
    ::close(out[1]);
    ::close(err[1]);
    ::close(report[1]);
    int child_error = 0;
    ssize_t got = 0;
    do {
        got = ::read(report[0], &child_error, sizeof child_error);
    } while (got < 0 && errno == EINTR);
    ::close(report[0]);
    if (got > 0) {
        ::close(out[0]);
        ::close(err[0]);
        int status = 0;
        ::waitpid(pid, &status, 0);
        return std::unexpected(os_error(child_error));
    }
    std::unique_ptr<Flash> flash(new Flash());
    flash->rx = std::make_shared<Channel<FlashEvent>>(kEventCapacity);
    flash->pid_ = pid;
    flash->finished_ = std::make_shared<std::atomic<bool>>(false);
    auto dropped = std::make_shared<std::atomic<size_t>>(0);
    std::thread out_reader([fd = out[0], tx = flash->rx, dropped] { read_lines(fd, *tx, *dropped); });
    std::thread err_reader([fd = err[0], tx = flash->rx, dropped] { read_lines(fd, *tx, *dropped); });
    flash->worker_ = std::thread([pid, tx = flash->rx, dropped, finished = flash->finished_, out_reader = std::move(out_reader), err_reader = std::move(err_reader)]() mutable {
        int status = 0;
        pid_t waited = 0;
        do {
            waited = ::waitpid(pid, &status, 0);
        } while (waited < 0 && errno == EINTR);
        const int wait_error = errno;
        // A command may leave background descendants holding the pipes: end the group before joining.
        terminate_group(pid, SIGTERM);
        ::usleep(30000);
        terminate_group(pid, SIGKILL);
        out_reader.join();
        err_reader.join();
        std::string message;
        if (waited < 0) message = "等待烧录命令失败：" + os_error(wait_error);
        else if (WIFEXITED(status)) message = "烧录命令退出，状态码 " + std::to_string(WEXITSTATUS(status));
        else message = "烧录命令被信号终止";
        const size_t lost = dropped->load(std::memory_order_relaxed);
        if (lost > 0) message += "（输出队列已丢弃 " + std::to_string(lost) + " 行）";
        // The child is already reaped, so this cannot stall it; cancel drains while joining.
        tx->send(FlashEvent{FlashEvent::Kind::Done, std::move(message)});
        finished->store(true, std::memory_order_release);
    });
    return flash;
}
void Flash::cancel() {
    if (!running()) return;
    using std::chrono::milliseconds;
    terminate_group(pid_, SIGTERM);
    const auto grace = std::chrono::steady_clock::now() + milliseconds(500);
    const auto done = [&] { return finished_->load(std::memory_order_acquire); };
    while (!done() && std::chrono::steady_clock::now() < grace) rx->recv_timeout(milliseconds(10));
    if (!done()) terminate_group(pid_, SIGKILL);
    while (!done()) rx->recv_timeout(milliseconds(10));
    while (rx->try_recv()) {
    }
    worker_.join();
    pid_ = 0;
}
Flash::~Flash() { cancel(); }
}  // namespace serial
