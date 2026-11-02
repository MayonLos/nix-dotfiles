// Cell drawing shared by every tool: pure functions onto an FTXUI screen buffer.
#pragma once
#include <cstdint>
#include <ftxui/screen/screen.hpp>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace tui {
#include "ui/palette.inc"
struct Rect {
    int x = 0, y = 0, width = 0, height = 0;
    bool contains(int px, int py) const { return px >= x && py >= y && px < x + width && py < y + height; }
};
struct Style {
    uint32_t fg = kFg;
    std::optional<uint32_t> bg;
    bool underline = false;
    bool bold = false;
};
// Returns the column after the text. Wide characters never split at the limit.
int put(ftxui::Screen& screen, int x, int y, const std::string& text, const Style& style, int limit = 100000);
int width_of(const std::string& text);
std::string clip(const std::string& text, int width);
std::vector<std::string> wrap(const std::string& text, int width, size_t max_lines);
void fill(ftxui::Screen& screen, const Rect& area, uint32_t bg);
void box(ftxui::Screen& screen, const Rect& area, const std::string& title, bool focused, std::optional<uint32_t> bg = {});
void put_right(ftxui::Screen& screen, int right, int y, const std::string& text, const Style& style);
// Draws text, colouring the code point ranges a search matched.
void put_ranges(ftxui::Screen& screen, int x, int y, const std::string& text, const std::vector<std::pair<size_t, size_t>>& ranges, const Style& style, int limit);
// Thin progress bar, `fraction` in 0..1.
void put_bar(ftxui::Screen& screen, int x, int y, int width, double fraction, uint32_t on, std::optional<uint32_t> bg = {});
// One scrollbar thumb cell in the column; nothing when everything fits.
void put_scroll(ftxui::Screen& screen, int x, int y, int height, size_t position, size_t total, std::optional<uint32_t> bg = {});

struct Hint {
    std::string key;
    std::string action;
};
// Keeps leading hints that fit; anything dropped is replaced by "? 更多".
std::vector<Hint> fit_hints(const std::vector<Hint>& hints, int width);
void put_hints(ftxui::Screen& screen, int x, int y, int width, const std::vector<Hint>& hints);
Rect centered(int outer_width, int outer_height, int width, int height);
}  // namespace tui
