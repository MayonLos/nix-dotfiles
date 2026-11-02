#include "ui/page.hpp"

#include <poll.h>
#include <signal.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <fcntl.h>
#include <stdexcept>
#include <string_view>

#include "ui/mailbox.hpp"
#include "ui/terminal.hpp"

namespace tui {
namespace {
int wake_pipe[2] = {-1, -1};
void on_signal(int number) {
    const unsigned char byte = number == SIGWINCH ? 'w' : 'q';
    [[maybe_unused]] const auto ignored = ::write(wake_pipe[1], &byte, 1);
}
struct Ui {};
}  // namespace
int run_page(Page& page) {
    if (::pipe2(wake_pipe, O_CLOEXEC | O_NONBLOCK) != 0) throw std::runtime_error("cannot start the event loop");
    struct sigaction action {};
    action.sa_handler = on_signal;
    sigemptyset(&action.sa_mask);
    action.sa_flags = SA_RESTART;
    for (const int number : {SIGWINCH, SIGINT, SIGTERM, SIGHUP}) sigaction(number, &action, nullptr);
    Mailbox<Ui> mailbox;
    Ui ui;
    Terminal terminal;
    InputParser parser;
    page.attach([&mailbox](std::function<void()> job) { mailbox.post([job = std::move(job)](Ui&) { job(); }); });
    page.set_active(true);
    bool active = true;
    bool dirty = true;
    bool quit = false;
    while (!quit) {
        page.tick();
        if (dirty && active) {
            const auto [width, height] = terminal.size();
            ftxui::Screen screen(width, height);
            page.draw(screen, Rect{0, 0, width, height});
            terminal.present(screen, page.cursor());
            dirty = false;
        }
        int timeout = -1;
        if (parser.pending()) {
            timeout = 30;
        } else if (const auto deadline = page.next_deadline()) {
            const auto wait = std::chrono::duration_cast<std::chrono::milliseconds>(*deadline - std::chrono::steady_clock::now()).count();
            timeout = static_cast<int>(std::clamp<int64_t>(wait + 1, 0, 60000));
        }
        pollfd fds[3]{{STDIN_FILENO, POLLIN, 0}, {mailbox.fd(), POLLIN, 0}, {wake_pipe[0], POLLIN, 0}};
        const int ready = ::poll(fds, 3, timeout);
        if (ready < 0 && errno != EINTR) break;
        if (ready < 0) continue;
        if (ready == 0) {
            if (parser.pending()) {
                for (const auto& event : parser.flush()) quit = page.handle(event) || quit;
            }
            dirty = true;
            continue;
        }
        if (fds[2].revents & POLLIN) {
            unsigned char bytes[16];
            const ssize_t got = ::read(wake_pipe[0], bytes, sizeof bytes);
            for (ssize_t i = 0; i < got; ++i) {
                if (bytes[i] == 'q') quit = true;
                if (bytes[i] == 'w') terminal.invalidate();
            }
            dirty = true;
        }
        if (fds[1].revents & POLLIN) {
            for (auto& job : mailbox.take()) job(ui);
            dirty = true;
        }
        if (fds[0].revents & (POLLIN | POLLHUP)) {
            char buffer[4096];
            const ssize_t got = ::read(STDIN_FILENO, buffer, sizeof buffer);
            if (got == 0 && (fds[0].revents & POLLHUP)) break;
            for (const auto& event : parser.feed(std::string_view(buffer, static_cast<size_t>(std::max<ssize_t>(got, 0))))) {
                if (event.type == InputEvent::Type::FocusIn || event.type == InputEvent::Type::FocusOut) {
                    active = event.type == InputEvent::Type::FocusIn;
                    page.set_active(active);
                    if (active) terminal.invalidate();
                }
                quit = page.handle(event) || quit;
            }
            dirty = true;
        }
    }
    page.set_active(false);
    return 0;
}
}  // namespace tui
