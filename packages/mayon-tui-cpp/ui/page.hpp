// What every tool implements. A Page owns its state; only run_page's thread touches it.
#pragma once
#include <chrono>
#include <ftxui/screen/screen.hpp>
#include <functional>
#include <optional>
#include <utility>

#include "ui/draw.hpp"
#include "ui/keys.hpp"

namespace tui {
using TimePoint = std::chrono::steady_clock::time_point;
// Thread safe: runs the job on the UI thread and triggers a redraw.
using Post = std::function<void(std::function<void()>)>;
class Page {
public:
    virtual ~Page() = default;
    // Called once before the first draw, and may start background work.
    virtual void attach(Post post) { post_ = std::move(post); }
    // Hidden pages and unfocused terminals stop refreshing and streaming.
    virtual void set_active(bool) {}
    virtual void draw(ftxui::Screen& screen, Rect area) = 0;
    // True asks the program to quit.
    virtual bool handle(const InputEvent& event) = 0;
    // When tick must next run; nothing means sleep until an event, so idle costs no CPU.
    virtual std::optional<TimePoint> next_deadline() const { return std::nullopt; }
    virtual void tick() {}
    // Where the real cursor goes after draw, for text inputs.
    virtual std::optional<std::pair<int, int>> cursor() const { return std::nullopt; }

protected:
    Post post_;
};
// Owns the terminal until the page quits or a fatal signal arrives; returns the exit code.
int run_page(Page& page);
}  // namespace tui
