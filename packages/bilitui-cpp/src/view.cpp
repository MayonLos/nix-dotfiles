// Drawing: pure functions of application state onto a cell buffer.
#include <ftxui/screen/color.hpp>
#include <ftxui/screen/string.hpp>

#include <algorithm>

#include "app.hpp"
#include "core/search.hpp"
#include "core/text.hpp"

using ftxui::Color;
using ftxui::Screen;
namespace bili {
#include "ui/palette.inc"
namespace {
Color rgb(uint32_t value) { return Color::RGB((value >> 16) & 255, (value >> 8) & 255, value & 255); }
struct Style {
    uint32_t fg = kFg;
    std::optional<uint32_t> bg;
    bool underline = false;
    bool bold = false;
};
int put(Screen& screen, int x, int y, const std::string& text, const Style& style, int limit = 100000) {
    if (y < 0 || y >= screen.dimy() || x >= screen.dimx()) return x;
    const auto glyphs = ftxui::Utf8ToGlyphs(text);
    int used = 0;
    for (const auto& glyph : glyphs) {
        if (used >= limit || x + used >= screen.dimx()) break;
        if (x + used >= 0) {
            ftxui::Pixel& pixel = screen.PixelAt(x + used, y);
            pixel.character = glyph == "\n" || glyph == "\t" ? " " : glyph;
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
    for (int y = area.y; y < area.y + area.height && y < screen.dimy(); ++y) {
        for (int x = area.x; x < area.x + area.width && x < screen.dimx(); ++x) {
            ftxui::Pixel& pixel = screen.PixelAt(x, y);
            pixel.character = " ";
            pixel.background_color = rgb(bg);
        }
    }
}
void box(Screen& screen, const Rect& area, const std::string& title, bool focused, std::optional<uint32_t> bg = {}) {
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
    if (!title.empty()) {
        put(screen, area.x + 2, area.y, " " + clip(title, area.width - 6) + " ", Style{focused ? kBrightFg : kFg, bg});
    }
}
void put_highlighted(Screen& screen, int x, int y, const std::string& text, const std::string& query, const Style& style, int limit) {
    const std::string clipped = clip(text, limit);
    std::vector<std::pair<size_t, size_t>> ranges;
    if (!query.empty()) {
        if (const auto hit = match(query, text)) ranges = hit->ranges;
    }
    size_t index = 0;
    for (const char32_t ch : decode(clipped)) {
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
}  // namespace
void App::draw(Screen& screen) {
    width_ = screen.dimx();
    height_ = screen.dimy();
    cursor_.reset();
    cover_rect_.reset();
    int x = 1;
    static constexpr std::array<const char*, 3> names{"搜索", "学习", "关注"};
    for (size_t i = 0; i < names.size(); ++i) {
        const bool active = static_cast<size_t>(tab_) == i;
        put(screen, x, 0, std::to_string(i + 1) + " " + names[i], Style{active ? kBlue : kMuted, {}, active});
        x += 8;
    }
    std::string status;
    if (player_status_.running) status += "▶ " + clip(player_status_.title, std::max(width_ / 3, 10));
    if (player_status_.queued > 0) status += " · 队列 " + std::to_string(player_status_.queued);
    size_t active_downloads = 0;
    for (const auto& row : downloads_) {
        if (row.state != "已完成" && row.state.rfind("失败", 0) != 0) ++active_downloads;
    }
    if (active_downloads > 0) status += " · 下载 " + std::to_string(active_downloads);
    if (status.empty()) status = demo_ ? "离线样例" : api_->logged_in() ? "✓ 已登录" : "游客";
    status = clip(status, std::max(width_ - x - 2, 0));
    put(screen, width_ - width_of(status) - 1, 0, status, Style{player_status_.running ? kGreen : api_->logged_in() ? kGreen : kMuted});
    int body_y = 1;
    if (tab_ == TabId::Search) {
        const std::string right = std::string(kOrderNames[static_cast<size_t>(order_)]) + " · " + kDurationNames[static_cast<size_t>(duration_)];
        const int right_width = width_of(right);
        const bool active = focus_ == Focus::Input;
        const int prompt = put(screen, 1, 1, "› ", Style{active ? kBlue : kMuted});
        const std::string text = search_.str();
        const int room = std::max(width_ - right_width - 5, 1);
        if (text.empty() && !active) {
            put(screen, prompt, 1, "s 搜索", Style{kMuted});
        } else {
            put(screen, prompt, 1, clip(text, room), Style{active ? kBrightFg : kFg});
        }
        if (active) cursor_ = std::make_pair(std::min(prompt + width_of(search_.before_cursor()), width_ - 1), 1);
        if (width_ > right_width + 8) put(screen, width_ - right_width - 1, 1, right, Style{kMuted});
        body_y = 2;
    }
    if (focus_ == Focus::Filter) {
        const int row = body_y;
        const std::string query = list().filter.str();
        const int prompt = put(screen, 1, row, "/ ", Style{kBlue});
        put(screen, prompt, row, clip(query, width_ - prompt - 1), Style{kBrightFg});
        cursor_ = std::make_pair(std::min(prompt + width_of(list().filter.before_cursor()), width_ - 1), row);
        ++body_y;
    }
    const int footer = 2;
    const Rect body{0, body_y, width_, std::max(height_ - body_y - footer, 0)};
    const bool wide = width_ >= 110;
    if (wide) {
        const int left = width_ * 6 / 10;
        draw_list(screen, Rect{0, body.y, left, body.height});
        draw_preview(screen, Rect{left, body.y, width_ - left, body.height});
    } else if (focus_ == Focus::Parts) {
        draw_preview(screen, body);
    } else {
        draw_list(screen, body);
    }
    if (focus_ == Focus::Input && choices_open_ && !choices_.empty() && !modal_) {
        const int rows = std::min<int>(static_cast<int>(choices_.size()), std::max(body.height - 2, 0));
        const Rect drop{1, body.y, std::min(width_ - 2, 60), rows + 2};
        fill(screen, drop, kSurface);
        box(screen, drop, search_.empty() ? "最近搜索" : "建议", true, kSurface);
        for (int i = 0; i < rows; ++i) {
            const bool selected = choice_ && *choice_ == static_cast<size_t>(i);
            put(screen, drop.x + 2, drop.y + 1 + i, clip(choices_[static_cast<size_t>(i)], drop.width - 4), Style{selected ? kBlue : kFg, kSurface});
        }
    }
    std::string hint;
    if (modal_) {
        hint = modal_->kind == Modal::Kind::Menu ? "↑↓ 选择  Enter 确认  Esc 取消" : "Esc 关闭";
    } else if (focus_ == Focus::Input) {
        hint = "Enter 搜索  ↑↓ 历史  Tab 建议  Esc 回到列表";
    } else if (focus_ == Focus::Filter) {
        hint = "↑↓ 选择  Enter 保留  Esc 恢复";
    } else if (focus_ == Focus::Parts) {
        hint = "Enter 播放这一集  ↑↓ 选择  ← 返回";
    } else {
        hint = "Enter 播放  → 分集  a 排队  w 稍后  o 排序  t 时长  / 过滤  Space 更多  ? 帮助  q 退出";
    }
    if (height_ >= 1) put(screen, 1, height_ - 1, clip(hint, width_ - 2), Style{kMuted});
    if (!notice_.empty() && height_ >= 2) put(screen, 1, height_ - 2, clip(notice_, width_ - 2), Style{notice_error_ ? kRed : kBlue});
    if (modal_) draw_modal(screen);
}
void App::draw_list(Screen& screen, Rect area) {
    list_rect_ = area;
    if (area.width < 8 || area.height < 3) return;
    ListState& state = list();
    std::string title = state.heading;
    if (!state.visible.empty()) title += " · " + std::to_string(state.visible.size());
    if (!state.filter.empty()) title += " · /" + state.filter.str();
    if (state.loading) title += " · 加载中…";
    box(screen, area, title, focus_ == Focus::List || focus_ == Focus::Filter);
    const Rect inner{area.x + 1, area.y + 1, area.width - 2, area.height - 2};
    if (state.visible.empty()) {
        std::string message;
        if (state.loading) message = "正在请求 B 站…";
        else if (!state.error.empty()) message = state.error + "  R 重试";
        else if (!state.filter.empty()) message = "没有匹配 · Esc 清除过滤";
        else if (tab_ == TabId::Search && state.source.type == Source::Type::None) message = "输入关键词，Enter 搜索";
        else message = "没有内容 · R 刷新";
        int row = inner.y + 1;
        for (const auto& line : wrap(message, inner.width - 4, 4)) {
            put(screen, inner.x + 2, row++, line, Style{state.error.empty() ? kMuted : kRed});
        }
        return;
    }
    const auto rows = static_cast<size_t>(std::max(inner.height, 1));
    if (state.selected < state.offset) state.offset = state.selected;
    if (state.selected >= state.offset + rows) state.offset = state.selected - rows + 1;
    if (state.offset + rows > state.visible.size()) state.offset = state.visible.size() > rows ? state.visible.size() - rows : 0;
    const std::string query = state.filter.str();
    const int duration_width = 9;
    const int views_width = inner.width >= 70 ? 8 : 0;
    const int up_width = inner.width >= 56 ? (inner.width >= 80 ? 18 : 12) : 0;
    for (size_t i = 0; i < rows && state.offset + i < state.visible.size(); ++i) {
        const size_t visible_index = state.offset + i;
        const Video& item = state.items[state.visible[visible_index]];
        const int y = inner.y + static_cast<int>(i);
        if (item.kind == Kind::Header) {
            put(screen, inner.x + 1, y, clip(item.title, inner.width - 2), Style{kMuted, {}, false, true});
            continue;
        }
        const bool selected = visible_index == state.selected;
        const std::optional<uint32_t> bg = selected ? std::optional<uint32_t>(kSelection) : std::nullopt;
        if (selected) fill(screen, Rect{inner.x, y, inner.width, 1}, kSelection);
        put(screen, inner.x, y, selected ? "▏" : " ", Style{kBlue, bg});
        std::string badge;
        if (item.kind == Kind::User) badge = "UP ";
        if (item.kind == Kind::Folder) badge = "夹 ";
        if (item.kind == Kind::Video && item.count > 1) badge = std::to_string(item.count) + "P ";
        int cursor = inner.x + 1;
        if (!badge.empty()) cursor = put(screen, cursor, y, badge, Style{kBlue, bg});
        const int title_width = inner.x + inner.width - cursor - up_width - views_width - duration_width - 1;
        put_highlighted(screen, cursor, y, item.title, query, Style{selected ? kBrightFg : kFg, bg}, title_width);
        int column = inner.x + inner.width - duration_width;
        std::string duration = item.kind == Kind::Folder ? std::to_string(item.count) + " 项" : item.kind == Kind::Video ? item.duration : "";
        if (item.kind == Kind::Video && item.progress > 0) duration = seconds_text(static_cast<uint64_t>(item.progress)) + "/" + duration;
        put(screen, column + std::max(duration_width - width_of(clip(duration, duration_width)) - 1, 0), y, clip(duration, duration_width - 1), Style{kMuted, bg});
        column -= views_width;
        if (views_width > 0 && item.kind == Kind::Video) {
            const std::string views = count(item.views);
            put(screen, column + std::max(views_width - width_of(views) - 1, 0), y, views, Style{kMuted, bg});
        }
        column -= up_width;
        if (up_width > 0 && item.kind != Kind::Folder) put_highlighted(screen, column, y, item.up, query, Style{kMuted, bg}, up_width - 1);
    }
}
void App::draw_preview(Screen& screen, Rect area) {
    preview_rect_ = area;
    if (area.width < 12 || area.height < 3) return;
    box(screen, area, focus_ == Focus::Parts ? "分集" : "预览", focus_ == Focus::Parts);
    const Rect inner{area.x + 2, area.y + 1, area.width - 4, area.height - 2};
    const Video* selected = selected_video();
    if (!selected) {
        put(screen, inner.x, inner.y, "选中一个视频查看详情", Style{kMuted});
        return;
    }
    const Details* details = selected_details();
    const Video& video = details ? details->video : *selected;
    int y = inner.y;
    if (selected->kind == Kind::Video && focus_ != Focus::Parts && cover_ && cover_->first == selected->cover) {
        // Terminal cells are about twice as tall as wide; covers are 16:9.
        const int rows = std::clamp(inner.width * 9 / 32, 4, std::max(inner.height / 3, 4));
        cover_rect_ = Rect{inner.x, y, rows * 32 / 9, rows};
        y += rows + 1;
    }
    const int bottom = inner.y + inner.height;
    if (focus_ != Focus::Parts) {
        for (const auto& line : wrap(video.title, inner.width, 2)) {
            if (y < bottom) put(screen, inner.x, y++, line, Style{kBrightFg});
        }
        if (selected->kind != Kind::Video) {
            if (y < bottom) put(screen, inner.x, y++, "Enter 打开", Style{kMuted});
            return;
        }
        if (y < bottom) put(screen, inner.x, y++, clip(video.up, inner.width), Style{kBlue});
        std::string meta = count(video.views) + " 播放";
        if (video.pubdate != 0) meta += " · " + date_text(video.pubdate);
        if (y < bottom) put(screen, inner.x, y++, clip(meta, inner.width), Style{kMuted});
    }
    if (!details) {
        if (y < bottom) put(screen, inner.x, y, "加载详情中…", Style{kMuted});
        return;
    }
    const auto [resume, start] = resume_point(*details);
    if (details->info.last_seconds > 0 && y < bottom) {
        std::string text = "已看到";
        if (video.parts.size() > 1) text += " P" + std::to_string(resume + 1);
        text += " · " + seconds_text(start);
        put(screen, inner.x, y++, clip(text, inner.width), Style{kGreen});
    }
    const bool has_parts = video.parts.size() > 1;
    const size_t total = has_parts ? video.parts.size() : video.collection.size();
    if (total > 0) {
        ++y;
        if (y < bottom) put(screen, inner.x, y++, std::string(has_parts ? "分 P · " : "合集 · ") + std::to_string(total) + " · → 进入", Style{kMuted});
        const int rows = bottom - y;
        if (rows > 0) {
            const size_t focus_index = focus_ == Focus::Parts ? series_selected_ : (has_parts ? resume : 0);
            auto window = static_cast<size_t>(rows);
            if (focus_index < series_offset_) series_offset_ = focus_index;
            if (focus_index >= series_offset_ + window) series_offset_ = focus_index - window + 1;
            if (series_offset_ >= total) series_offset_ = 0;
            for (size_t i = series_offset_; i < total && i < series_offset_ + window; ++i) {
                const bool highlight = i == focus_index && focus_ == Focus::Parts;
                const bool current = has_parts ? (details->info.last_seconds > 0 && i == resume) : video.collection[i].bvid == video.bvid;
                const std::string label = has_parts ? std::to_string(video.parts[i].page) + " " + video.parts[i].title : video.collection[i].title;
                const std::optional<uint32_t> bg = highlight ? std::optional<uint32_t>(kSelection) : std::nullopt;
                if (highlight) fill(screen, Rect{inner.x, y, inner.width, 1}, kSelection);
                put(screen, inner.x, y, current ? "▶ " : "  ", Style{kGreen, bg});
                put(screen, inner.x + 2, y, clip(label, inner.width - 2), Style{highlight ? kBrightFg : current ? kBrightFg : kFg, bg});
                ++y;
            }
        }
        return;
    }
    if (!video.description.empty()) {
        ++y;
        const int rows = bottom - y;
        if (rows > 0) {
            for (const auto& line : wrap(video.description, inner.width, static_cast<size_t>(rows))) put(screen, inner.x, y++, line, Style{kFg});
        }
    }
}
void App::draw_modal(Screen& screen) {
    const Modal& modal = *modal_;
    const auto centered = [&](int width, int height) {
        const int w = std::min(width, width_);
        const int h = std::min(height, height_);
        return Rect{(width_ - w) / 2, (height_ - h) / 2, w, h};
    };
    if (modal.kind == Modal::Kind::Menu) {
        int longest = width_of(modal.title) + 6;
        for (const auto& item : modal.items) longest = std::max(longest, width_of(item.label) + 6);
        const Rect area = centered(std::max(longest, 36), static_cast<int>(modal.items.size()) + 2);
        fill(screen, area, kSurface);
        box(screen, area, modal.title, true, kSurface);
        for (size_t i = 0; i < modal.items.size() && static_cast<int>(i) < area.height - 2; ++i) {
            const int y = area.y + 1 + static_cast<int>(i);
            const bool selected = i == modal.selected;
            put(screen, area.x + 2, y, std::string(selected ? "▏" : " ") + clip(modal.items[i].label, area.width - 5), Style{selected ? kBlue : kFg, kSurface});
        }
    } else if (modal.kind == Modal::Kind::Downloads) {
        const int rows = std::max<int>(static_cast<int>(downloads_.size()), 1);
        const Rect area = centered(std::min(width_ - 4, 90), std::min(rows + 2, height_ - 2));
        fill(screen, area, kSurface);
        box(screen, area, modal.title, true, kSurface);
        if (downloads_.empty()) put(screen, area.x + 2, area.y + 1, "还没有下载任务", Style{kMuted, kSurface});
        const int visible = area.height - 2;
        const int first = std::max(static_cast<int>(downloads_.size()) - visible, 0);
        for (int i = 0; i < visible && first + i < static_cast<int>(downloads_.size()); ++i) {
            const DownloadRow& row = downloads_[static_cast<size_t>(first + i)];
            std::string state = row.state;
            if (row.bytes > 0) state += " " + std::to_string(row.bytes / 1048576) + " MiB";
            const int state_width = std::min(width_of(state), area.width / 2);
            put(screen, area.x + 2, area.y + 1 + i, clip(row.title, area.width - state_width - 6), Style{kFg, kSurface});
            const uint32_t tone = row.state == "已完成" ? kGreen : row.state.rfind("失败", 0) == 0 ? kRed : kBlue;
            put(screen, area.x + area.width - state_width - 2, area.y + 1 + i, clip(state, state_width), Style{tone, kSurface});
        }
    } else if (modal.kind == Modal::Kind::Qr) {
        std::vector<std::string> art;
        size_t at = 0;
        while (at < modal.qr_art.size()) {
            const auto end = modal.qr_art.find('\n', at);
            art.push_back(modal.qr_art.substr(at, end - at));
            at = end == std::string::npos ? modal.qr_art.size() : end + 1;
        }
        const int art_width = art.empty() ? 0 : width_of(art.front());
        const Rect area = centered(std::max(art_width + 4, 44), static_cast<int>(art.size()) + 5);
        fill(screen, area, kSurface);
        box(screen, area, modal.title, true, kSurface);
        if (static_cast<int>(art.size()) + 4 > area.height || art_width + 4 > area.width) {
            put(screen, area.x + 2, area.y + 1, "请放大终端以完整显示二维码", Style{kYellow, kSurface});
        } else {
            int y = area.y + 1;
            for (const auto& line : art) {
                const auto glyphs = ftxui::Utf8ToGlyphs(line);
                int x = area.x + (area.width - art_width) / 2;
                for (const auto& glyph : glyphs) {
                    ftxui::Pixel& pixel = screen.PixelAt(x++, y);
                    pixel.character = glyph;
                    pixel.foreground_color = Color::White;
                    pixel.background_color = Color::Black;
                }
                ++y;
            }
            put(screen, area.x + 2, y, clip(modal.text, area.width - 4), Style{kBlue, kSurface});
        }
        if (art.empty()) put(screen, area.x + 2, area.y + 1, clip(modal.text, area.width - 4), Style{kBlue, kSurface});
    } else {
        const auto lines = wrap(modal.text, std::min(width_ - 8, 72), 40);
        const Rect area = centered(std::min(width_ - 2, 78), static_cast<int>(lines.size()) + 2);
        fill(screen, area, kSurface);
        box(screen, area, modal.title, true, kSurface);
        int y = area.y + 1;
        for (const auto& line : lines) {
            if (y < area.y + area.height - 1) put(screen, area.x + 2, y++, line, Style{kFg, kSurface});
        }
    }
}
}  // namespace bili
