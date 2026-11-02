#include "shell.hpp"

#include <algorithm>
#include <chrono>
#include <utility>

#include "ui/text.hpp"

using ftxui::Screen;
using tui::InputEvent;
using tui::Rect;
using tui::Style;

namespace toolbox {
namespace {
constexpr int kTitleWidth = 9;  // " 工具箱  " in cells.
constexpr std::chrono::milliseconds kFrame{70};
void top_bar(Screen& screen, int x, int y, int width, size_t page) {
    int right = x + width;
    x = tui::put(screen, x, y, " 工具箱  ", Style{tui::kMuted}, std::max(right - x, 0));
    for (size_t i = 0; i < kTools.size(); ++i) {
        const int room = std::max(right - x, 0);
        const Style style = i == page ? Style{tui::kBlue, {}, true} : Style{tui::kMuted};
        x = tui::put(screen, x, y, std::string(" ") + kTools[i].label + " ", style, room);
        x = tui::put(screen, x, y, " ", Style{tui::kMuted}, std::max(right - x, 0));
    }
    tui::put(screen, x, y, " [ / ] 切换", Style{tui::kMuted}, std::max(right - x, 0));
}
}  // namespace

std::optional<size_t> tab_at(int x) {
    int left = kTitleWidth;
    for (size_t i = 0; i < kTools.size(); ++i) {
        const int width = tui::width_of(kTools[i].label) + 3;
        if (x >= left && x < left + width) return i;
        left += width;
    }
    return std::nullopt;
}

std::optional<size_t> top_switch(const InputEvent& event, size_t current, bool editing) {
    if (event.type == InputEvent::Type::MouseClick) {
        if (event.y == 0) return tab_at(event.x);
        return std::nullopt;
    }
    if (event.type != InputEvent::Type::Key || editing) return std::nullopt;
    const tui::Key& key = event.key;
    if (key.ctrl || key.alt) return std::nullopt;
    if (key.is(U'[')) return (current + 4) % kTools.size();
    if (key.is(U']')) return (current + 1) % kTools.size();
    return std::nullopt;
}

Shell::Shell(std::array<Factory, 5> factories, size_t initial, std::vector<std::vector<std::string>> args)
    : factories_(std::move(factories)), page_(std::min(initial, kTools.size() - 1)) {
    for (size_t i = 0; i < args_.size() && i < args.size(); ++i) args_[i] = std::move(args[i]);
    open(page_, false);
}
Shell::~Shell() = default;

void Shell::attach(tui::Post post) {
    post_ = std::move(post);
    for (Slot& slot : slots_) {
        if (slot.page) slot.page->attach(post_);
    }
}

void Shell::open(size_t index, bool retry) {
    Slot& slot = slots_[index];
    if (!retry) {
        if (slot.page) {
            slot.page->set_active(active_);
            return;
        }
        if (!slot.error.empty()) return;
    } else {
        slot.page.reset();
        slot.error.clear();
    }
    try {
        std::unique_ptr<tui::Page> page = factories_[index](args_[index]);
        if (!page) {
            slot.error = std::string(kTools[index].name) + " 页面不可用";
            return;
        }
        if (post_) page->attach(post_);
        page->set_active(active_);
        slot.page = std::move(page);
    } catch (const std::exception& error) {
        slot.error = error.what();
    } catch (...) {
        slot.error = std::string(kTools[index].name) + " 页面初始化失败";
    }
}

void Shell::switch_to(size_t index) {
    if (index == page_) return;
    if (tui::Page* page = current()) page->set_active(false);
    page_ = index;
    open(page_, false);
}

void Shell::set_active(bool active) {
    active_ = active;
    if (tui::Page* page = current()) page->set_active(active);
}

void Shell::tick() {
    if (!active_) return;
    if (tui::Page* page = current()) page->tick();
}

std::optional<tui::TimePoint> Shell::next_deadline() const {
    if (!active_) return std::nullopt;
    const tui::Page* page = current();
    if (page == nullptr) return std::nullopt;
    const auto deadline = page->next_deadline();
    if (!deadline) return std::nullopt;
    // Coalesce redraws to at most one frame per 70 ms, like Rust's FRAME_TIME.
    const auto floor = drawn_at_ + kFrame;
    if (*deadline < floor) return floor;
    return deadline;
}

std::optional<std::pair<int, int>> Shell::cursor() const {
    if (const tui::Page* page = current(); page != nullptr) return page->cursor();
    return std::nullopt;
}

void Shell::draw(Screen& screen, Rect area) {
    if (area.width <= 0 || area.height <= 0) return;
    drawn_at_ = std::chrono::steady_clock::now();
    top_bar(screen, area.x, area.y, area.width, page_);
    const Rect body{area.x, area.y + 1, area.width, std::max(area.height - 1, 0)};
    if (body.height <= 0) return;
    if (Slot& slot = slots_[page_]; slot.page) {
        slot.page->draw(screen, body);
    } else {
        const std::string title = std::string(kTools[page_].label) + " · 启动失败";
        tui::put(screen, body.x + 1, body.y, tui::clip(title, std::max(body.width - 2, 0)), Style{tui::kBrightFg}, std::max(body.width - 2, 0));
        int y = body.y + 2;
        const auto lines = tui::wrap(slot.error.empty() ? "未知错误" : slot.error, std::max(body.width - 4, 1), 8);
        for (const std::string& line : lines) {
            if (y >= body.y + body.height) break;
            tui::put(screen, body.x + 1, y++, tui::clip(line, std::max(body.width - 2, 0)), Style{tui::kRed}, std::max(body.width - 2, 0));
        }
        if (body.height >= 2) {
            std::vector<tui::Hint> hints;
            hints.push_back({"R", "重试"});
            hints.push_back({"[ / ]", "切换工具"});
            hints.push_back({"q/Esc", "退出"});
            tui::put_hints(screen, body.x + 1, body.y + body.height - 1, std::max(body.width - 2, 0), hints);
        }
    }
}

bool Shell::handle(const InputEvent& event) {
    if (event.type == InputEvent::Type::FocusIn || event.type == InputEvent::Type::FocusOut) return false;
    if (event.type == InputEvent::Type::Key && event.key.ctrl && event.key.ch == U'c') return true;
    const tui::Page* page = current();
    const bool editing = page != nullptr && page->editing();
    if (const auto next = top_switch(event, page_, editing)) {
        switch_to(*next);
        return false;
    }
    if (!slots_[page_].error.empty()) {
        if (event.type != InputEvent::Type::Key) return false;
        if (event.key.is(U'R')) open(page_, true);
        else if (event.key.is(U'q') || event.key.code == tui::KeyCode::Escape) return true;
        return false;
    }
    if (page == nullptr) return false;
    InputEvent local = event;
    if (local.type == InputEvent::Type::MouseClick || local.type == InputEvent::Type::WheelUp || local.type == InputEvent::Type::WheelDown) {
        local.y -= 1;
        if (local.type == InputEvent::Type::MouseClick && local.y < 0) return false;
    }
    return slots_[page_].page->handle(local);
}

}  // namespace toolbox
