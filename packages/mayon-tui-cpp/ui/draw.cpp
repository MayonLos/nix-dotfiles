#include "ui/draw.hpp"

#include <algorithm>
#include <cmath>
#include <ftxui/screen/color.hpp>
#include <ftxui/screen/string.hpp>

#include "ui/text.hpp"

using ftxui::Screen;
namespace tui {
namespace {
ftxui::Color rgb(uint32_t value) { return ftxui::Color::RGB((value >> 16) & 255, (value >> 8) & 255, value & 255); }
}  // namespace
int put(Screen& screen, int x, int y, const std::string& text, const Style& style, int limit) {
    if (y < 0 || y >= screen.dimy() || x >= screen.dimx()) return x;
    const auto glyphs = ftxui::Utf8ToGlyphs(text);
    int used = 0;
    for (size_t i = 0; i < glyphs.size(); ++i) {
        // A wide character is a glyph followed by one empty continuation cell.
        const bool wide = i + 1 < glyphs.size() && glyphs[i + 1].empty();
        if (used + (wide ? 2 : 1) > limit || x + used + (wide ? 1 : 0) >= screen.dimx()) break;
        if (x + used >= 0) {
            ftxui::Pixel& pixel = screen.PixelAt(x + used, y);
            pixel.character = glyphs[i] == "\n" || glyphs[i] == "\t" ? " " : glyphs[i];
            pixel.foreground_color = rgb(style.fg);
            if (style.bg) pixel.background_color = rgb(*style.bg);
            pixel.underlined = style.underline;
            pixel.bold = style.bold;
        }
        ++used;
    }
    return x + used;
}
int width_of(const std::string& text) { return ftxui::string_width(text); }
std::string clip(const std::string& text, int width) {
    if (width <= 0) return {};
    if (width_of(text) <= width) return text;
    std::string out;
    int used = 0;
    for (const char32_t ch : decode(text)) {
        std::string one;
        append(one, ch);
        const int cells = width_of(one);
        if (used + cells > width - 1) break;
        out += one;
        used += cells;
    }
    return out + "…";
}
std::vector<std::string> wrap(const std::string& text, int width, size_t max_lines) {
    std::vector<std::string> lines;
    if (width <= 0) return lines;
    std::string line;
    int used = 0;
    for (const char32_t ch : decode(text)) {
        if (lines.size() >= max_lines) return lines;
        if (ch == U'\n') {
            lines.push_back(std::exchange(line, {}));
            used = 0;
            continue;
        }
        std::string one;
        append(one, ch);
        const int cells = width_of(one);
        if (used + cells > width) {
            lines.push_back(std::exchange(line, {}));
            used = 0;
        }
        line += one;
        used += cells;
    }
    if (!line.empty() && lines.size() < max_lines) lines.push_back(line);
    return lines;
}
void fill(Screen& screen, const Rect& area, uint32_t bg) {
    const int left = std::max(area.x, 0);
    const int right = std::min(area.x + area.width, screen.dimx());
    for (int y = std::max(area.y, 0); y < area.y + area.height && y < screen.dimy(); ++y) {
        // A wide character occupies two cells with an empty continuation cell. Overwriting
        // either half alone would leave the other half visible outside the filled area.
        if (left > 0 && left < screen.dimx() && screen.PixelAt(left, y).character.empty()) {
            screen.PixelAt(left - 1, y).character = " ";
        }
        if (right > 0 && right < screen.dimx() && screen.PixelAt(right, y).character.empty()) {
            screen.PixelAt(right, y).character = " ";
        }
        for (int x = left; x < right; ++x) {
            ftxui::Pixel& pixel = screen.PixelAt(x, y);
            pixel.character = " ";
            pixel.background_color = rgb(bg);
        }
    }
}
void box(Screen& screen, const Rect& area, const std::string& title, bool focused, std::optional<uint32_t> bg) {
    if (area.width < 4 || area.height < 2) return;
    const Style line{focused ? kBlue : kBorder, bg};
    const int right = area.x + area.width - 1;
    const int bottom = area.y + area.height - 1;
    for (int x = area.x + 1; x < right; ++x) {
        put(screen, x, area.y, "─", line);
        put(screen, x, bottom, "─", line);
    }
    for (int y = area.y + 1; y < bottom; ++y) {
        put(screen, area.x, y, "│", line);
        put(screen, right, y, "│", line);
    }
    put(screen, area.x, area.y, "╭", line);
    put(screen, right, area.y, "╮", line);
    put(screen, area.x, bottom, "╰", line);
    put(screen, right, bottom, "╯", line);
    if (!title.empty()) put(screen, area.x + 2, area.y, " " + clip(title, area.width - 6) + " ", Style{focused ? kBrightFg : kFg, bg});
}
void put_right(Screen& screen, int right, int y, const std::string& text, const Style& style) {
    put(screen, right - width_of(text), y, text, style);
}
void put_ranges(Screen& screen, int x, int y, const std::string& text, const std::vector<std::pair<size_t, size_t>>& ranges, const Style& style, int limit) {
    size_t index = 0;
    for (const char32_t ch : decode(clip(text, limit))) {
        std::string one;
        append(one, ch);
        Style cell = style;
        for (const auto& [from, to] : ranges) {
            if (index >= from && index < to) cell.fg = kYellow;
        }
        x = put(screen, x, y, one, cell);
        ++index;
    }
}
void put_bar(Screen& screen, int x, int y, int width, double fraction, uint32_t on, std::optional<uint32_t> bg) {
    const int filled = static_cast<int>(std::lround(std::clamp(fraction, 0.0, 1.0) * width));
    for (int i = 0; i < width; ++i) put(screen, x + i, y, i < filled ? "━" : "─", Style{i < filled ? on : kBorder, bg});
}
void put_scroll(Screen& screen, int x, int y, int height, size_t position, size_t total, std::optional<uint32_t> bg) {
    if (height < 2 || total <= 1) return;
    const auto span = static_cast<size_t>(height - 1);
    put(screen, x, y + static_cast<int>(position * span / (total - 1)), "▐", Style{kBorder, bg});
}
std::vector<Hint> fit_hints(const std::vector<Hint>& hints, int width) {
    const auto cost = [](const Hint& hint) { return width_of(hint.key) + 1 + width_of(hint.action) + 2; };
    int total = 0;
    for (const Hint& hint : hints) total += cost(hint);
    if (total - 2 <= width) return hints;
    const Hint more{"?", "更多"};
    std::vector<Hint> out;
    int used = cost(more) - 2;
    for (const Hint& hint : hints) {
        if (hint.key == more.key || used + cost(hint) > width) continue;
        used += cost(hint);
        out.push_back(hint);
    }
    if (used <= width) out.push_back(more);
    return out;
}
void put_hints(Screen& screen, int x, int y, int width, const std::vector<Hint>& hints) {
    for (const Hint& hint : fit_hints(hints, width)) {
        x = put(screen, x, y, hint.key, Style{kFg});
        x = put(screen, x + 1, y, hint.action, Style{kMuted}) + 2;
    }
}
Rect centered(int outer_width, int outer_height, int width, int height) {
    const int w = std::min(width, outer_width);
    const int h = std::min(height, outer_height);
    return Rect{(outer_width - w) / 2, (outer_height - h) / 2, w, h};
}
}  // namespace tui
