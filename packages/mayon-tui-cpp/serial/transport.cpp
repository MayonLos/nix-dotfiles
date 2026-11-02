#include "transport.hpp"

#include <fcntl.h>
#include <poll.h>
#include <sys/ioctl.h>
#include <termios.h>

#include <algorithm>
#include <cerrno>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <iterator>

#include "store.hpp"

namespace serial {
bool set_baud(int fd, uint32_t baud);  // baud.cpp
namespace fs = std::filesystem;
using Clock = std::chrono::steady_clock;
using std::chrono::milliseconds;
namespace {
constexpr milliseconds kRetry{400};
constexpr milliseconds kBacklogPoll{10};
constexpr milliseconds kFrame{70};
constexpr size_t kMaxTxBytes = 1024 * 1024;
constexpr size_t kTxChunkBytes = 4096;
constexpr size_t kPendingLimit = 512;
constexpr const char* kRtsWarning = "RTS/CTS 硬件流控可能由驱动接管 RTS 电平";

std::optional<std::string> read_trimmed(const fs::path& path) {
    std::ifstream file(path);
    if (!file) return std::nullopt;
    const std::string text = trim_text(std::string((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>()));
    if (text.empty()) return std::nullopt;
    return text;
}
std::optional<uint16_t> parse_hex_file(const fs::path& path) {
    const auto text = read_trimmed(path);
    if (!text || text->size() > 4) return std::nullopt;
    unsigned value = 0;
    for (const char c : *text) {
        const int digit = c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;
        if (digit < 0) return std::nullopt;
        value = value * 16 + static_cast<unsigned>(digit);
    }
    return static_cast<uint16_t>(value);
}
std::string adapter_name(uint16_t vid, uint16_t pid) {
    if (vid == 0x0483 && ((pid >= 0x3748 && pid <= 0x374f) || pid == 0x3752 || pid == 0x3753)) return "ST-Link VCP";
    if (vid == 0x0483 && pid == 0x5740) return "STM32 VCP";
    if (vid == 0x1a86 && (pid == 0x7523 || pid == 0x5523 || pid == 0x55d4)) return "CH340/CH341";
    if (vid == 0x10c4) return "Silicon Labs CP210x";
    if (vid == 0x0403) return "FTDI USB Serial";
    if (vid == 0x0483) return "ST USB Serial";
    return "USB Serial Adapter";
}
std::optional<Device> sysfs_device(const std::string& tty) {
    std::error_code error;
    const fs::path canonical = fs::canonical(fs::path("/sys/class/tty") / tty / "device", error);
    if (error) return std::nullopt;
    std::optional<fs::path> usb;
    for (fs::path path = canonical;; path = path.parent_path()) {
        if (parse_hex_file(path / "idVendor") && parse_hex_file(path / "idProduct")) {
            usb = path;
            break;
        }
        if (path == path.parent_path()) break;
    }
    if (!usb) return std::nullopt;
    Device device;
    device.path = "/dev/" + tty;
    device.vid = *parse_hex_file(*usb / "idVendor");
    device.pid = *parse_hex_file(*usb / "idProduct");
    device.serial = read_trimmed(*usb / "serial");
    const std::string identified = adapter_name(device.vid, device.pid);
    const auto product = read_trimmed(*usb / "product");
    device.product = !product ? identified : identified != "USB Serial Adapter" ? *product + " · " + identified : *product;
    // The tty usually resolves to the USB interface node. The topology names the physical
    // device, so it stays stable when ttyACM/ttyUSB numbering moves.
    for (fs::path path = canonical;; path = path.parent_path()) {
        if (const auto number = read_trimmed(path / "bInterfaceNumber")) {
            device.interface = *number;
            break;
        }
        if (path == *usb || path == path.parent_path()) break;
    }
    std::string driver;
    for (fs::path path = canonical;; path = path.parent_path()) {
        const fs::path target = fs::read_symlink(path / "driver", error);
        if (!error) {
            driver = target.filename().string();
            break;
        }
        if (path == path.parent_path()) break;
    }
    device.topology = usb->filename().string() + "|" + driver;
    return device;
}
std::string lower(std::string text) {
    std::ranges::transform(text, text.begin(), [](unsigned char c) { return static_cast<char>(c >= 'A' && c <= 'Z' ? c + 32 : c); });
    return text;
}
bool hardware_rts_flow(const Settings& settings) {
    const std::string flow = lower(settings.flow);
    return flow == "hardware" || flow == "rts/cts" || flow == "rtscts";
}
// Nonblocking throughout, so a stalled CTS or a full tty cannot trap Release or Shutdown.
std::expected<int, std::string> configure(const Device& device, const Settings& settings) {
    const auto fail = [&](int fd, std::string message) -> std::expected<int, std::string> {
        if (fd >= 0) ::close(fd);
        return std::unexpected(std::move(message));
    };
    tcflag_t size = CS8;
    if (settings.bits == 5) size = CS5;
    else if (settings.bits == 6) size = CS6;
    else if (settings.bits == 7) size = CS7;
    else if (settings.bits != 8) return fail(-1, "unsupported data bits: " + std::to_string(settings.bits));
    const std::string parity = lower(settings.parity);
    if (parity != "none" && parity != "n" && parity != "even" && parity != "e" && parity != "odd" && parity != "o") return fail(-1, "unsupported parity: " + settings.parity);
    if (settings.stop != 1 && settings.stop != 2) return fail(-1, "unsupported stop bits: " + std::to_string(settings.stop));
    const std::string flow = lower(settings.flow);
    const bool software = flow == "software" || flow == "xon/xoff" || flow == "xonxoff";
    const bool hardware = hardware_rts_flow(settings);
    if (flow != "none" && !software && !hardware) return fail(-1, "unsupported flow control: " + settings.flow);
    // O_NOCTTY: a serial port must never become this program's controlling terminal.
    const int fd = ::open(device.path.c_str(), O_RDWR | O_NOCTTY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) return fail(-1, device.path + ": " + os_error(errno));
    if (::ioctl(fd, TIOCEXCL) != 0) return fail(fd, device.path + ": " + os_error(errno));
    termios options{};
    if (::tcgetattr(fd, &options) != 0) return fail(fd, device.path + ": " + os_error(errno));
    ::cfmakeraw(&options);
    options.c_cflag |= CREAD | CLOCAL;
    options.c_cflag &= ~static_cast<tcflag_t>(CSIZE | PARENB | PARODD | CSTOPB | CRTSCTS);
    options.c_cflag |= size;
    options.c_iflag &= ~static_cast<tcflag_t>(INPCK | IGNPAR | IXON | IXOFF | IXANY);
    if (parity == "none" || parity == "n") {
        options.c_iflag |= IGNPAR;
    } else {
        options.c_cflag |= PARENB;
        if (parity == "odd" || parity == "o") options.c_cflag |= PARODD;
        options.c_iflag |= INPCK;
    }
    if (settings.stop == 2) options.c_cflag |= CSTOPB;
    if (hardware) options.c_cflag |= CRTSCTS;
    if (software) options.c_iflag |= IXON | IXOFF;
    options.c_cc[VMIN] = 0;
    options.c_cc[VTIME] = 0;
    if (::tcsetattr(fd, TCSANOW, &options) != 0) return fail(fd, device.path + ": " + os_error(errno));
    if (!set_baud(fd, settings.baud)) return fail(fd, device.path + ": " + os_error(errno));
    return fd;
}
void close_port(int fd) {
    ::ioctl(fd, TIOCNXCL);
    ::close(fd);
}
bool is_stream(const Event& event) { return event.kind == Event::Kind::Rx || event.kind == Event::Kind::Tx; }
// Delivers events without ever blocking the port loop: overflow waits here, and reads pause meanwhile.
class EventSink {
public:
    EventSink(std::shared_ptr<EventChannel> tx, std::function<void()> notify) : tx_(std::move(tx)), notify_(std::move(notify)) {}
    bool has_pending() const { return !pending_.empty(); }
    void send(Event event) {
        if (!pending_.empty()) {
            queue_pending(std::move(event));
            return;
        }
        const bool stream = is_stream(event);
        const auto result = tx_->try_send(std::move(event));
        if (result == EventChannel::Result::Ok) wake(stream);
        else if (result == EventChannel::Result::Full) pending_.push_back(std::move(event));
    }
    void flush() {
        while (!pending_.empty()) {
            const bool stream = is_stream(pending_.front());
            const auto result = tx_->try_send(std::move(pending_.front()));
            if (result == EventChannel::Result::Full) break;
            if (result == EventChannel::Result::Closed) {
                pending_.clear();
                break;
            }
            pending_.pop_front();
            wake(stream);
        }
    }
    // Delivers a throttled wake once its 70 ms have passed; otherwise returns how long is left.
    std::optional<milliseconds> flush_wake() {
        if (!deferred_) return std::nullopt;
        const auto left = last_wake_ + kFrame - Clock::now();
        if (left <= Clock::duration::zero()) {
            wake(false);
            return std::nullopt;
        }
        return std::chrono::duration_cast<milliseconds>(left) + milliseconds(1);
    }

private:
    void wake(bool throttled) {
        if (!notify_) return;
        const auto now = Clock::now();
        if (throttled && now - last_wake_ < kFrame) {
            deferred_ = true;
            return;
        }
        deferred_ = false;
        last_wake_ = now;
        notify_();
    }
    void queue_pending(Event event) {
        if (pending_.size() < kPendingLimit) {
            pending_.push_back(std::move(event));
            return;
        }
        const auto kind = event.kind;
        if (kind == Event::Kind::Tx) {
            for (auto it = pending_.rbegin(); it != pending_.rend(); ++it) {
                if (it->kind == Event::Kind::Tx) {
                    it->count += event.count;
                    break;
                }
            }
        } else if (kind == Event::Kind::Error) {
            const auto same = std::ranges::find_if(pending_, [&](const Event& item) { return item.kind == Event::Kind::Error && item.text == event.text; });
            if (same == pending_.end()) {
                const auto first = std::ranges::find_if(pending_, [](const Event& item) { return item.kind == Event::Kind::Error; });
                if (first != pending_.end()) pending_.erase(first);
                pending_.push_back(std::move(event));
            }
        } else if (kind == Event::Kind::Connected || kind == Event::Kind::Disconnected) {
            std::erase_if(pending_, [](const Event& item) { return item.kind == Event::Kind::Connected || item.kind == Event::Kind::Disconnected; });
            make_room();
            pending_.push_back(std::move(event));
        } else if (kind == Event::Kind::Released) {
            std::erase_if(pending_, [](const Event& item) { return item.kind == Event::Kind::Released; });
            make_room();
            pending_.push_back(std::move(event));
        } else if (pending_.back().kind == Event::Kind::Rx) {
            // Reads pause while anything is pending, so this only guards a future caller.
            pending_.back().bytes.insert(pending_.back().bytes.end(), event.bytes.begin(), event.bytes.end());
        }
    }
    void make_room() {
        if (pending_.size() < kPendingLimit) return;
        const auto index = std::ranges::find_if(pending_, [](const Event& item) { return item.kind == Event::Kind::Tx || item.kind == Event::Kind::Error; });
        if (index != pending_.end()) pending_.erase(index);
    }
    std::shared_ptr<EventChannel> tx_;
    std::function<void()> notify_;
    std::deque<Event> pending_;
    Clock::time_point last_wake_{};
    bool deferred_ = false;
};
struct Pulse {
    Clock::time_point deadline;
    bool dtr;
    bool rts;
};
struct PendingTx {
    Bytes bytes;
    size_t offset = 0;
};
struct Active {
    int fd = -1;
    Device device;
    Settings settings;
    std::optional<PendingTx> pending_tx;
    std::optional<Pulse> pulse;
    Clock::time_point tx_retry{};
};
struct Reconnect {
    Device device;
    Settings settings;
    Clock::time_point retry_at;
};
void set_line(int fd, int line, bool on, const char* name, std::vector<std::string>& errors) {
    if (::ioctl(fd, on ? TIOCMBIS : TIOCMBIC, &line) != 0) errors.push_back(std::string(name) + ": " + os_error(errno));
}
void modem_lines(int fd, bool dtr, bool rts, EventSink& events) {
    std::vector<std::string> errors;
    set_line(fd, TIOCM_DTR, dtr, "DTR", errors);
    set_line(fd, TIOCM_RTS, rts, "RTS", errors);
    if (errors.empty()) return;
    std::string joined;
    for (const std::string& error : errors) joined += (joined.empty() ? "" : "；") + error;
    events.send(Event::error("控制线不可用（连接仍保持）：" + joined));
}
std::optional<Active> open_and_emit(Device device, const Settings& settings, EventSink& events, bool report_error) {
    const auto fd = configure(device, settings);
    if (!fd) {
        if (report_error) events.send(Event::error(fd.error()));
        return std::nullopt;
    }
    if (hardware_rts_flow(settings)) events.send(Event::error(kRtsWarning));
    modem_lines(*fd, settings.dtr, settings.rts, events);
    events.send(Event::connected(device.path));
    Active active;
    active.fd = *fd;
    active.device = std::move(device);
    active.settings = settings;
    return active;
}
std::optional<std::string> disconnect(std::optional<Active>& active, EventSink& events) {
    if (!active) return std::nullopt;
    std::string path = active->device.path;
    if (active->pending_tx) {
        const size_t remaining = active->pending_tx->bytes.size() - active->pending_tx->offset;
        if (remaining > 0) events.send(Event::error("关闭串口时丢弃了 " + std::to_string(remaining) + " 字节待发送数据"));
    }
    close_port(active->fd);  // Close before acknowledging a flash hand-off.
    active.reset();
    events.send(Event::disconnected(path));
    return path;
}
std::optional<Device> locate(const Device& target) {
    // Manually supplied paths may be any symlink; USB devices must match their identity.
    if (target.vid == 0 && target.pid == 0) {
        std::error_code error;
        if (fs::exists(target.path, error)) return target;
        return std::nullopt;
    }
    return resolve_device(target, discover());
}
void port_loop(CommandChannel& commands, EventSink& events, int wake_fd, const std::atomic<bool>& stopped) {
    std::optional<Active> active;
    std::optional<Reconnect> reconnect;
    const auto current_path = [&]() -> std::string { return active ? active->device.path : reconnect ? reconnect->device.path : std::string(); };
    const auto handle = [&](Command command) -> bool {
        switch (command.kind) {
            case Command::Kind::Connect: {
                disconnect(active, events);
                reconnect = Reconnect{command.device, command.settings, Clock::now()};
                std::optional<Device> current;
                if (command.device.vid == 0 && command.device.pid == 0) current = command.device;
                else current = resolve_device(command.device, discover());
                if (current) {
                    active = open_and_emit(*current, command.settings, events, true);
                    if (active) reconnect.reset();
                } else {
                    events.send(Event::error("设备 " + command.device.path + " 已断开或身份不唯一，等待按设备身份重连"));
                }
                break;
            }
            case Command::Kind::Disconnect:
            case Command::Kind::Release: {
                const std::string path = current_path();
                reconnect.reset();  // No reopening behind a flash or an explicit disconnect.
                if (!disconnect(active, events)) events.send(Event::disconnected(path));
                if (command.kind == Command::Kind::Release) events.send(Event::released(command.id));
                break;
            }
            case Command::Kind::Write:
                if (command.bytes.size() > kMaxTxBytes) events.send(Event::error("发送内容超过 " + std::to_string(kMaxTxBytes) + " 字节上限"));
                else if (!active) events.send(Event::error("串口尚未连接"));
                else if (active->pending_tx) events.send(Event::error("上一条发送仍在排队"));
                else active->pending_tx = PendingTx{std::move(command.bytes)};
                break;
            case Command::Kind::Lines:
                if (active) {
                    if (command.rts != active->settings.rts && hardware_rts_flow(active->settings)) events.send(Event::error(kRtsWarning));
                    modem_lines(active->fd, command.dtr, command.rts, events);
                    active->settings.dtr = command.dtr;
                    active->settings.rts = command.rts;
                }
                break;
            case Command::Kind::Pulse:
                if (active) {
                    const bool old_dtr = active->settings.dtr;
                    const bool old_rts = active->settings.rts;
                    if (!command.dtr && hardware_rts_flow(active->settings)) events.send(Event::error(kRtsWarning));
                    modem_lines(active->fd, command.dtr ? !old_dtr : old_dtr, command.dtr ? old_rts : !old_rts, events);
                    active->pulse = Pulse{Clock::now() + milliseconds(std::max<uint64_t>(command.millis, 1)), old_dtr, old_rts};
                }
                break;
            case Command::Kind::Shutdown:
                return false;
        }
        return true;
    };
    const auto lost = [&](const std::string& message) {
        const Device device = active->device;
        const Settings settings = active->settings;
        events.send(Event::error(message));
        disconnect(active, events);
        reconnect = Reconnect{device, settings, Clock::now() + kRetry};
    };
    while (!stopped.load(std::memory_order_acquire)) {
        // Sleep until a command, port activity or a real deadline: an idle port costs nothing.
        const auto now = Clock::now();
        std::optional<milliseconds> wait = events.flush_wake();
        const auto limit = [&](milliseconds value) { wait = wait ? std::min(*wait, value) : value; };
        const auto until = [&](Clock::time_point when) { limit(std::max(std::chrono::duration_cast<milliseconds>(when - now) + milliseconds(1), milliseconds(0))); };
        if (events.has_pending()) limit(kBacklogPoll);
        short port_events = 0;
        if (active) {
            if (!events.has_pending()) port_events |= POLLIN;
            if (active->pending_tx) {
                if (now >= active->tx_retry) port_events |= POLLOUT;
                else until(active->tx_retry);
            }
            if (active->pulse) until(active->pulse->deadline);
        } else if (reconnect) {
            until(reconnect->retry_at);
        }
        pollfd fds[2]{{wake_fd, POLLIN, 0}, {active && port_events != 0 ? active->fd : -1, port_events, 0}};
        const int ready = ::poll(fds, 2, wait ? static_cast<int>(wait->count()) : -1);
        if (ready < 0 && errno != EINTR) break;
        const short revents = ready > 0 ? fds[1].revents : short{0};
        if (ready > 0 && (fds[0].revents & POLLIN)) {
            uint64_t value = 0;
            [[maybe_unused]] const auto ignored = ::read(wake_fd, &value, sizeof value);
        }
        // A command may close or reopen the port, which makes the poll result stale.
        const int polled_fd = fds[1].fd;
        bool running = true;
        while (running) {
            auto command = commands.try_recv();
            if (!command) break;
            running = handle(std::move(*command));
        }
        if (!running) break;
        const bool same_port = active && active->fd == polled_fd;
        if (same_port && active->pending_tx && (revents & (POLLOUT | POLLERR | POLLHUP))) {
            PendingTx& pending = *active->pending_tx;
            const size_t count = std::min(kTxChunkBytes, pending.bytes.size() - pending.offset);
            const ssize_t wrote = ::write(active->fd, pending.bytes.data() + pending.offset, count);
            if (wrote > 0) {
                events.send(Event::tx(static_cast<size_t>(wrote)));
                pending.offset += static_cast<size_t>(wrote);
                if (pending.offset >= pending.bytes.size()) active->pending_tx.reset();
            } else if (wrote < 0 && errno != EAGAIN && errno != EINTR) {
                lost("写入失败：" + os_error(errno));
            } else {
                active->tx_retry = Clock::now() + kBacklogPoll;  // Never spin on a tty that claims room.
            }
        }
        if (active && active->fd == polled_fd && !events.has_pending() && (revents & (POLLIN | POLLHUP | POLLERR | POLLNVAL))) {
            uint8_t buffer[4096];
            const ssize_t count = ::read(active->fd, buffer, sizeof buffer);
            if (count > 0) {
                events.send(Event::rx(Bytes(buffer, buffer + count)));
            } else if (count == 0) {
                // Poll said input or hangup under VMIN=0, so an empty read means the line is gone.
                lost("串口断开：连接已挂断");
            } else if (errno != EAGAIN && errno != EINTR) {
                lost("串口断开：" + os_error(errno));
            }
        }
        if (active && active->pulse && Clock::now() >= active->pulse->deadline) {
            modem_lines(active->fd, active->pulse->dtr, active->pulse->rts, events);
            active->pulse.reset();
        }
        if (!active && reconnect && Clock::now() >= reconnect->retry_at) {
            reconnect->retry_at = Clock::now() + kRetry;
            if (const auto device = locate(reconnect->device)) {
                active = open_and_emit(*device, reconnect->settings, events, false);
                if (active) reconnect.reset();
            }
        }
        // A UI that fell behind leaves data in this bounded queue, and reads stop until it catches up.
        events.flush();
    }
    disconnect(active, events);
    events.flush();
}
Command with_kind(Command::Kind kind) {
    Command out;
    out.kind = kind;
    return out;
}
}  // namespace
std::string Device::key() const {
    const std::string identity = serial && !serial->empty() ? *serial : !topology.empty() ? topology : path;
    char prefix[16];
    std::snprintf(prefix, sizeof prefix, "%04x:%04x:", vid, pid);
    return prefix + identity + ":" + interface;
}
std::vector<Device> discover() {
    std::vector<Device> devices;
    std::error_code error;
    for (const auto& entry : fs::directory_iterator("/sys/class/tty", error)) {
        const std::string name = entry.path().filename().string();
        if (!name.starts_with("ttyACM") && !name.starts_with("ttyUSB")) continue;
        if (auto device = sysfs_device(name)) devices.push_back(std::move(*device));
    }
    std::ranges::sort(devices, {}, &Device::path);
    return devices;
}
std::optional<Device> resolve_device(const Device& target, const std::vector<Device>& candidates) {
    std::optional<Device> found;
    const std::string key = target.key();
    for (const Device& candidate : candidates) {
        if (candidate.key() != key) continue;
        if (found) return std::nullopt;
        found = candidate;
    }
    return found;
}
Command Command::connect(Device device, Settings settings) {
    Command out = with_kind(Kind::Connect);
    out.device = std::move(device);
    out.settings = std::move(settings);
    return out;
}
Command Command::disconnect() { return with_kind(Kind::Disconnect); }
Command Command::release(uint64_t id) {
    Command out = with_kind(Kind::Release);
    out.id = id;
    return out;
}
Command Command::write(Bytes bytes) {
    Command out = with_kind(Kind::Write);
    out.bytes = std::move(bytes);
    return out;
}
Command Command::lines(bool dtr, bool rts) {
    Command out = with_kind(Kind::Lines);
    out.dtr = dtr;
    out.rts = rts;
    return out;
}
Command Command::pulse(bool dtr, uint64_t millis) {
    Command out = with_kind(Kind::Pulse);
    out.dtr = dtr;
    out.millis = millis;
    return out;
}
Worker::Control::~Control() {
    if (wake_fd >= 0) ::close(wake_fd);
}
Worker Worker::start(std::function<void()> notify) {
    Worker worker;
    worker.tx = std::make_shared<CommandChannel>(64);
    worker.rx = std::make_shared<EventChannel>(512);
    worker.control_ = std::make_shared<Control>();
    worker.control_->wake_fd = ::eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
    worker.tx->set_wake_fd(worker.control_->wake_fd);
    worker.thread_ = std::thread([commands = worker.tx, out = worker.rx, control = worker.control_, notify = std::move(notify)] {
        EventSink events(out, notify);
        port_loop(*commands, events, control->wake_fd, control->stopped);
        commands->close();
    });
    return worker;
}
Worker Worker::from_channels(std::shared_ptr<CommandChannel> tx, std::shared_ptr<EventChannel> rx) {
    Worker worker;
    worker.tx = std::move(tx);
    worker.rx = std::move(rx);
    return worker;
}
Worker Worker::parked() {
    Worker worker;
    worker.tx = std::make_shared<CommandChannel>(1);
    worker.rx = std::make_shared<EventChannel>(1);
    worker.tx->close();
    return worker;
}
Worker& Worker::operator=(Worker&& other) noexcept {
    if (this != &other) {
        stop();
        tx = std::move(other.tx);
        rx = std::move(other.rx);
        control_ = std::move(other.control_);
        thread_ = std::move(other.thread_);
    }
    return *this;
}
Worker::~Worker() { stop(); }
void Worker::stop() {
    if (control_) {
        control_->stopped.store(true, std::memory_order_release);
        const uint64_t one = 1;
        [[maybe_unused]] const auto ignored = ::write(control_->wake_fd, &one, sizeof one);
    }
    if (thread_.joinable()) thread_.join();
}
}  // namespace serial
