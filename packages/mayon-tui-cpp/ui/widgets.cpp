#include "ui/widgets.hpp"

#include <algorithm>

#include "ui/text.hpp"

using ftxui::Screen;
namespace tui {
int draw_tabs(Screen& screen, int x, int y, const std::vector<std::string>& names, size_t current) {
    for (size_t i = 0; i < names.size(); ++i) {
        const bool active = i == current;
        put(screen, x, y, std::to_string(i + 1), Style{kMuted});
        const int end = put(screen, x + 2, y, names[i], active ? Style{kBrightFg, {}, true} : Style{kMuted});
        x = end + 2;
    }
    return x;
}
std::optional<size_t> tab_at(int x, int origin, const std::vector<std::string>& names) {
    for (size_t i = 0; i < names.size(); ++i) {
        const int end = origin + 2 + width_of(names[i]);
        if (x >= origin && x < end) return i;
        origin = end + 2;
    }
    return std::nullopt;
}
std::vector<int> column_widths(const std::vector<Column>& columns, int total) {
    int fixed = 0;
    int shared = 0;
    for (const Column& column : columns) {
        fixed += column.width + 1;
        if (column.width == 0) ++shared;
    }
    const int rest = std::max(total - fixed, 0);
    std::vector<int> out;
    int left = rest;
    for (const Column& column : columns) {
        if (column.width > 0) {
            out.push_back(column.width);
        } else {
            const int width = shared > 1 ? rest / std::max(shared, 1) : left;
            out.push_back(width);
            left -= width;
            --shared;
        }
    }
    return out;
}
static void draw_cells(Screen& screen, Rect row, const std::vector<Column>& columns, const std::vector<std::string>& cells, const Style& style) {
    const auto widths = column_widths(columns, row.width - 2);
    int x = row.x + 2;
    for (size_t i = 0; i < columns.size() && i < cells.size(); ++i) {
        const std::string text = clip(cells[i], widths[i]);
        if (columns[i].right) put_right(screen, x + widths[i], row.y, text, style);
        else put(screen, x, row.y, text, style);
        x += widths[i] + 1;
    }
}
void draw_table_header(Screen& screen, Rect row, const std::vector<Column>& columns) {
    std::vector<std::string> titles;
    for (const Column& column : columns) titles.push_back(column.title);
    draw_cells(screen, row, columns, titles, Style{kMuted});
}
void draw_table_row(Screen& screen, Rect row, const std::vector<Column>& columns, const std::vector<std::string>& cells, bool selected, uint32_t fg) {
    Style style{fg};
    if (selected) {
        fill(screen, row, kSelection);
        put(screen, row.x, row.y, "▌", Style{kBlue, kSelection});
        style = Style{kBrightFg, kSelection};
    }
    draw_cells(screen, row, columns, cells, style);
}
size_t scroll_to(size_t selected, size_t offset, size_t rows, size_t total) {
    if (rows == 0) return 0;
    if (selected < offset) offset = selected;
    if (selected >= offset + rows) offset = selected - rows + 1;
    if (offset + rows > total) offset = total > rows ? total - rows : 0;
    return offset;
}
void draw_confirm(Screen& screen, const std::string& title, const std::string& message, const std::string& yes_key) {
    const int width = std::min(screen.dimx() - 2, 64);
    const auto lines = wrap(message, width - 6, 8);
    const Rect area = centered(screen.dimx(), screen.dimy(), width, static_cast<int>(lines.size()) + 4);
    fill(screen, area, kSurface);
    box(screen, area, title, false, kSurface);
    int y = area.y + 1;
    for (const auto& line : lines) put(screen, area.x + 3, y++, line, Style{kFg, kSurface});
    int x = put(screen, area.x + 3, y + 1, yes_key, Style{kRed, kSurface});
    x = put(screen, x + 1, y + 1, "确认", Style{kMuted, kSurface});
    x = put(screen, x + 2, y + 1, "Esc", Style{kFg, kSurface});
    put(screen, x + 1, y + 1, "取消", Style{kMuted, kSurface});
}
std::pair<int, int> draw_input(Screen& screen, const std::string& title, const TextInput& input, bool masked) {
    const Rect area = centered(screen.dimx(), screen.dimy(), std::min(screen.dimx() - 2, 64), 3);
    fill(screen, area, kSurface);
    box(screen, area, title, true, kSurface);
    const auto hide = [&](std::string text) {
        if (!masked) return text;
        return std::string(decode(text).size(), '*');
    };
    const int room = area.width - 6;
    put(screen, area.x + 3, area.y + 1, clip(hide(input.str()), room), Style{kBrightFg, kSurface});
    return {std::min(area.x + 3 + width_of(hide(input.before_cursor())), area.x + 3 + room), area.y + 1};
}
void draw_help(Screen& screen, const std::string& title, const std::vector<std::string>& lines) {
    const Rect area = centered(screen.dimx(), screen.dimy(), std::min(screen.dimx() - 2, 78), static_cast<int>(lines.size()) + 4);
    fill(screen, area, kSurface);
    box(screen, area, title, false, kSurface);
    int y = area.y + 2;
    for (const auto& line : lines) {
        if (y >= area.y + area.height - 1) break;
        const auto gap = line.find("  ");
        if (gap == std::string::npos) {
            put(screen, area.x + 3, y, clip(line, area.width - 6), Style{kMuted, kSurface});
        } else {
            const int after = put(screen, area.x + 3, y, line.substr(0, gap), Style{kBlue, kSurface});
            put(screen, std::max(after + 2, area.x + 16), y, clip(trim(line.substr(gap)), area.width - 19), Style{kFg, kSurface});
        }
        ++y;
    }
}
void draw_menu(Screen& screen, const std::string& title, const std::vector<std::string>& items, size_t selected) {
    int longest = width_of(title) + 6;
    for (const auto& item : items) longest = std::max(longest, width_of(item) + 6);
    const Rect area = centered(screen.dimx(), screen.dimy(), std::max(longest, 36), static_cast<int>(items.size()) + 2);
    fill(screen, area, kSurface);
    box(screen, area, title, false, kSurface);
    for (size_t i = 0; i < items.size() && static_cast<int>(i) < area.height - 2; ++i) {
        const int y = area.y + 1 + static_cast<int>(i);
        const bool active = i == selected;
        const uint32_t bg = active ? kSelection : kSurface;
        fill(screen, Rect{area.x + 1, y, area.width - 2, 1}, bg);
        if (active) put(screen, area.x + 1, y, "▌", Style{kBlue, bg});
        put(screen, area.x + 3, y, clip(items[i], area.width - 5), Style{active ? kBrightFg : kFg, bg});
    }
}
}  // namespace tui
