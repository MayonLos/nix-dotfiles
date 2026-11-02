// Private: the page itself, in a header so the tests can drive it through events.
#pragma once
#include <iosfwd>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "fuzzy.hpp"
#include "model.hpp"
#include "ui/input.hpp"
#include "ui/page.hpp"

namespace keys {
struct Position {
    size_t column = 0;
    size_t y = 0;
    size_t group = 0;
    std::optional<size_t> selection;  // Index into the visible list; nothing for a group label.
};
struct Layout {
    std::vector<Position> positions;
    size_t total = 0;
};
// Groups occupy columns; a single filtered group flows across all of them.
Layout layout_rows(const std::vector<Entry>& items, const std::vector<size_t>& visible, size_t columns);
size_t columns_for(int width, size_t group_count);

class KeysPage : public tui::Page {
public:
    explicit KeysPage(std::optional<std::string> data_path = std::nullopt);
    explicit KeysPage(std::vector<Entry> items, std::string path = "fixture");
    void draw(ftxui::Screen& screen, tui::Rect area) override;
    bool handle(const tui::InputEvent& event) override;
    std::optional<std::pair<int, int>> cursor() const override { return cursor_; }

    std::vector<size_t> visible() const;
    bool editing() const { return editing_; }
    bool help() const { return help_; }
    bool details() const { return details_; }
    size_t selected() const { return selected_; }
    size_t scroll() const { return scroll_; }
    int detail_scroll() const { return detail_scroll_; }
    std::optional<size_t> group() const { return group_; }
    std::string query() const { return query_.str(); }
    size_t columns() const { return columns_; }
    const std::optional<std::string>& error() const { return error_; }

private:
    void load();
    void index_rows();
    void keep_selected(std::optional<size_t> id);
    std::optional<size_t> selected_id() const;
    void move_selection(int delta, size_t count);
    void reset();
    void pick_group(std::optional<size_t> group);
    bool handle_key(const tui::Key& key);
    void handle_mouse(const tui::InputEvent& event);
    void draw_tabs(ftxui::Screen& screen, tui::Rect row);
    void draw_query(ftxui::Screen& screen, tui::Rect row);
    void draw_list(ftxui::Screen& screen, tui::Rect list, const std::vector<size_t>& visible);
    void draw_details(ftxui::Screen& screen, const Entry& entry) const;
    void draw_help_dialog(ftxui::Screen& screen) const;

    std::optional<std::string> requested_path_;
    std::string path_;
    std::optional<std::string> error_;
    std::vector<Entry> items_;
    std::vector<SearchText> search_;
    std::optional<size_t> group_;
    tui::TextInput query_;
    tui::TextInput previous_query_;
    bool editing_ = false;
    size_t selected_ = 0;
    size_t scroll_ = 0;
    bool help_ = false;
    bool details_ = false;
    int detail_scroll_ = 0;
    bool follow_ = true;
    std::vector<std::pair<tui::Rect, size_t>> hits_;
    std::vector<std::pair<tui::Rect, std::optional<size_t>>> tabs_;
    size_t viewport_ = 0;
    size_t total_rows_ = 0;
    size_t columns_ = 1;
    tui::Rect last_area_;
    std::optional<std::pair<int, int>> cursor_;
};
// The command line with its streams injected. Without `list` it takes over the terminal.
int run_cli(const std::vector<std::string>& args, std::ostream& out, std::ostream& err);
}  // namespace keys
