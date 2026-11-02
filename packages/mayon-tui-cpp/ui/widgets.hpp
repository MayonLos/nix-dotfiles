// Dialogs and tables with the shared look. Pages hold the state; these only draw.
#pragma once
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "ui/draw.hpp"
#include "ui/input.hpp"

namespace tui {
// Numbered page labels on one row, current page underlined. Returns the column after them.
int draw_tabs(ftxui::Screen& screen, int x, int y, const std::vector<std::string>& names, size_t current);
// Which label a click on the tab row hit, if any.
std::optional<size_t> tab_at(int x, int origin, const std::vector<std::string>& names);
struct Column {
    std::string title;
    int width = 0;  // 0 shares what is left.
    bool right = false;
};
// Resolves shared widths for the given total.
std::vector<int> column_widths(const std::vector<Column>& columns, int total);
void draw_table_header(ftxui::Screen& screen, Rect row, const std::vector<Column>& columns);
// One row: selection uses the selection background and a blue left bar, like every list.
void draw_table_row(ftxui::Screen& screen, Rect row, const std::vector<Column>& columns, const std::vector<std::string>& cells, bool selected, uint32_t fg = kFg);
// Keeps `selected` visible in `rows` rows; returns the new first row.
size_t scroll_to(size_t selected, size_t offset, size_t rows, size_t total);
// Destructive actions must show this and wait for an explicit key.
void draw_confirm(ftxui::Screen& screen, const std::string& title, const std::string& message, const std::string& yes_key = "y");
// Single-line input dialog; returns the cursor position for Page::cursor().
std::pair<int, int> draw_input(ftxui::Screen& screen, const std::string& title, const TextInput& input, bool masked = false);
// Lines of "key  description"; other lines appear muted.
void draw_help(ftxui::Screen& screen, const std::string& title, const std::vector<std::string>& lines);
// A menu using the list selection style.
void draw_menu(ftxui::Screen& screen, const std::string& title, const std::vector<std::string>& items, size_t selected);
}  // namespace tui
