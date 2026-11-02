// Private page implementation shared by page.cpp and the tests. Not part of the public entry.
#pragma once
#include <ftxui/screen/screen.hpp>

#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "app.hpp"
#include "ui/page.hpp"

namespace serial {
class SerialPage : public tui::Page {
public:
    SerialPage();
    explicit SerialPage(const std::vector<std::string>& args);
    void attach(tui::Post post) override;
    void set_active(bool active) override;
    void draw(ftxui::Screen& screen, tui::Rect area) override;
    bool handle(const tui::InputEvent& event) override;
    std::optional<tui::TimePoint> next_deadline() const override;
    void tick() override;
    std::optional<std::pair<int, int>> cursor() const override { return cursor_; }

    // Test hooks: the same state machine the Rust tests drive.
    App* app() { return app_.get(); }
    const std::string& error() const { return error_; }
    bool confirm_flash() const { return confirm_flash_; }

private:
    void load();
    void apply_args(App& app);
    void wake();
    bool key(const tui::Key& key);
    void paste(const std::string& text);
    void click(int x, int y);
    void wheel(int delta);
    void move_selection(int delta);
    void edit_setting();
    void lines();
    void draw_error(ftxui::Screen& screen, tui::Rect area);
    void draw_title(ftxui::Screen& screen, tui::Rect area);
    void draw_tabs(ftxui::Screen& screen, tui::Rect area);
    void draw_footer(ftxui::Screen& screen, tui::Rect area);
    void draw_monitor(ftxui::Screen& screen, tui::Rect area);
    void draw_capture(ftxui::Screen& screen, tui::Rect area);
    void draw_record(ftxui::Screen& screen, tui::Rect row, const Record& record);
    void draw_send(ftxui::Screen& screen, tui::Rect area);
    void draw_graph(ftxui::Screen& screen, tui::Rect area);
    void draw_ports(ftxui::Screen& screen, tui::Rect area);
    void draw_settings(ftxui::Screen& screen, tui::Rect area);
    void draw_commands(ftxui::Screen& screen, tui::Rect area);
    void draw_flash(ftxui::Screen& screen, tui::Rect area);
    void draw_input(ftxui::Screen& screen);
    void draw_confirm(ftxui::Screen& screen);
    void draw_help(ftxui::Screen& screen);

    std::vector<std::string> args_;
    std::unique_ptr<App> app_;
    std::string error_;
    bool active_ = true;
    bool confirm_flash_ = false;
    std::optional<std::pair<int, int>> cursor_;
    std::vector<std::pair<tui::Rect, size_t>> tab_hits_;
    std::vector<std::pair<tui::Rect, size_t>> row_hits_;
    size_t port_offset_ = 0;
    size_t favorite_offset_ = 0;
};
// One row of `serial list`, exposed so the column order and format are testable.
std::string format_device_row(const Device& device);
}  // namespace serial
