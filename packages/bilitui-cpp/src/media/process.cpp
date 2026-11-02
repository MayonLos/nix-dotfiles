#include "media/process.hpp"

#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

#include <chrono>
#include <stdexcept>
#include <thread>

extern char** environ;
namespace bili {
pid_t spawn_process(const std::vector<std::string>& argv) {
    std::vector<char*> raw;
    for (const auto& item : argv) raw.push_back(const_cast<char*>(item.c_str()));
    raw.push_back(nullptr);
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0);
    posix_spawnattr_t attributes;
    posix_spawnattr_init(&attributes);
    sigset_t none, all;
    sigemptyset(&none);
    sigfillset(&all);
    posix_spawnattr_setsigmask(&attributes, &none);
    posix_spawnattr_setsigdefault(&attributes, &all);
    // A separate process group keeps terminal Ctrl-C and foreground reads away from the child.
    posix_spawnattr_setpgroup(&attributes, 0);
    posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETPGROUP);
    pid_t pid = -1;
    const int code = posix_spawnp(&pid, raw[0], &actions, &attributes, raw.data(), environ);
    posix_spawn_file_actions_destroy(&actions);
    posix_spawnattr_destroy(&attributes);
    if (code != 0) throw std::runtime_error("无法启动 " + argv[0]);
    return pid;
}
bool try_reap(pid_t pid, bool* success) {
    int status = 0;
    const pid_t done = ::waitpid(pid, &status, WNOHANG);
    if (done == 0) return false;
    if (success) *success = done == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0;
    return true;
}
void stop_process(pid_t pid) {
    ::kill(pid, SIGTERM);
    for (int i = 0; i < 20; ++i) {
        if (try_reap(pid, nullptr)) return;
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
    ::kill(pid, SIGKILL);
    ::waitpid(pid, nullptr, 0);
}
}  // namespace bili
