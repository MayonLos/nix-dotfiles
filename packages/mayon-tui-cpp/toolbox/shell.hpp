// The toolbox shell: one top bar with five tabs over the embedded tool pages.
// main.cpp supplies the page factories; tests drive the shell with fakes.
#pragma once
#include <array>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "ui/page.hpp"

namespace toolbox {
struct Tool {
    const char* name;
    const char* label;
};
inline constexpr std::array<Tool, 5> kTools{{{"docker", "Docker"}, {"ports", "Ports"}, {"serial", "Serial"}, {"keys", "Keys"}, {"voice", "Voice"}}};
using Factory = std::function<std::unique_ptr<tui::Page>(const std::vector<std::string>& args)>;

// Hit test on the tab row. Rust main.rs starts the labels after " 工具箱  " (9 cells)
// and gives each label its width plus one padding cell on both sides.
std::optional<size_t> tab_at(int x);
// `[` / `]` while no page has a text cursor, or a left click on the tab row.
std::optional<size_t> top_switch(const tui::InputEvent& event, size_t current, bool editing);

class Shell : public tui::Page {
public:
    // `args` is the argument vector of the initially selected page; every other page
    // starts with an empty one, like Rust's page_args.
    Shell(std::array<Factory, 5> factories, size_t initial, std::vector<std::vector<std::string>> args);
    ~Shell() override;

    void attach(tui::Post post) override;
    void set_active(bool active) override;
    void draw(ftxui::Screen& screen, tui::Rect area) override;
    bool handle(const tui::InputEvent& event) override;
    std::optional<tui::TimePoint> next_deadline() const override;
    void tick() override;
    std::optional<std::pair<int, int>> cursor() const override;

    size_t page() const { return page_; }
    // True once the page was built; a failed build is an error slot until retried.
    bool opened(size_t page) const { return slots_[page].page != nullptr || !slots_[page].error.empty(); }
    bool failed(size_t page) const { return !slots_[page].error.empty(); }
    const std::string& error(size_t page) const { return slots_[page].error; }

private:
    struct Slot {
        std::unique_ptr<tui::Page> page;
        std::string error;
    };

    void open(size_t page, bool retry);
    void switch_to(size_t page);
    tui::Page* current() const { return slots_[page_].page.get(); }

    std::array<Factory, 5> factories_;
    std::array<Slot, 5> slots_;
    std::array<std::vector<std::string>, 5> args_;
    size_t page_ = 1;
    bool active_ = true;
    tui::TimePoint drawn_at_ = std::chrono::steady_clock::now();
};
}  // namespace toolbox
