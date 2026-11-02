// Drawing: pure functions of application state onto a cell buffer.
#include <ftxui/screen/color.hpp>
#include <ftxui/screen/string.hpp>

#include <algorithm>
#include <cstdlib>

#include "app.hpp"
#include "ui/search.hpp"
#include "ui/text.hpp"

using ftxui::Color;
using ftxui::Screen;
namespace bili {
namespace {
constexpr int kWideLayout = 110;
constexpr int kCardLayoutRows = 12;  // Below this a list keeps one line per entry.
void put_highlighted(Screen& screen, int x, int y, const std::string& text, const std::string& query, const Style& style, int limit) {
    std::vector<std::pair<size_t, size_t>> ranges;
    if (!query.empty()) {
        if (const auto hit = match(query, text)) ranges = hit->ranges;
    }
    put_ranges(screen, x, y, text, ranges, style, limit);
}
uint64_t duration_seconds(const std::string& text) {
    uint64_t total = 0;
    uint64_t field = 0;
    for (const char c : text) {
        if (c == ':') {
            total = total * 60 + field;
            field = 0;
        } else if (c >= '0' && c <= '9') {
            field = field * 10 + static_cast<uint64_t>(c - '0');
        } else {
            return 0;
        }
    }
    return total * 60 + field;
}
std::string join_meta(const std::vector<std::string>& parts) {
    std::string out;
    for (const auto& part : parts) {
        if (part.empty()) continue;
        if (!out.empty()) out += " · ";
        out += part;
    }
    return out;
}
int card_height(const Video& item, bool cards) { return cards && item.kind != Kind::Header ? 2 : 1; }
}  // namespace
void App::draw(Screen& screen) {
    width_ = screen.dimx();
    height_ = screen.dimy();
    cursor_.reset();
    cover_rect_.reset();
    list_rows_.clear();
    draw_header(screen);
    int body_y = 1;
    if (tab_ == TabId::Search) {
        draw_search_box(screen);
        body_y = 4;
    }
    if (focus_ == Focus::Filter) {
        const std::string query = list().filter.str();
        const int prompt = put(screen, 1, body_y, "/ ", Style{kBlue});
        put(screen, prompt, body_y, clip(query, width_ - prompt - 1), Style{kBrightFg});
        cursor_ = std::make_pair(std::min(prompt + width_of(list().filter.before_cursor()), width_ - 1), body_y);
        ++body_y;
    }
    const bool playing = player_status_.running && height_ >= 12;
    const int footer = playing ? 2 : 1;
    const Rect body{0, body_y, width_, std::max(height_ - body_y - footer, 0)};
    const bool start_page = tab_ == TabId::Search && list().source.type == Source::Type::None && list().items.empty() && !list().loading;
    if (start_page) {
        list_rect_ = Rect{};
        draw_start(screen, body);
    } else if (width_ >= kWideLayout) {
        const int left = width_ * 6 / 10;
        draw_list(screen, Rect{0, body.y, left, body.height});
        for (int y = body.y; y < body.y + body.height; ++y) put(screen, left, y, "│", Style{kSelection});
        draw_preview(screen, Rect{left + 1, body.y, width_ - left - 1, body.height});
    } else if (focus_ == Focus::Parts) {
        draw_preview(screen, body);
    } else {
        draw_list(screen, body);
    }
    if (!start_page && focus_ == Focus::Input && choices_open_ && !choices_.empty() && !modal_) {
        const int rows = std::min<int>(static_cast<int>(choices_.size()), std::max(body.height - 2, 0));
        const Rect drop{1, body.y - 1, std::min(width_ - 2, 60), rows + 2};
        fill(screen, drop, kSurface);
        box(screen, drop, search_.empty() ? "最近搜索" : "建议", false, kSurface);
        for (int i = 0; i < rows; ++i) {
            const bool selected = choice_ && *choice_ == static_cast<size_t>(i);
            if (selected) fill(screen, Rect{drop.x + 1, drop.y + 1 + i, drop.width - 2, 1}, kSelection);
            put(screen, drop.x + 2, drop.y + 1 + i, clip(choices_[static_cast<size_t>(i)], drop.width - 4), Style{selected ? kBrightFg : kFg, selected ? kSelection : kSurface});
        }
    }
    if (playing) draw_now_playing(screen, height_ - 2);
    draw_footer(screen);
    if (modal_) draw_modal(screen);
}
void App::draw_header(Screen& screen) {
    int x = 1;
    static constexpr std::array<const char*, 3> names{"搜索", "学习", "关注"};
    for (size_t i = 0; i < names.size(); ++i) {
        const bool active = static_cast<size_t>(tab_) == i;
        put(screen, x, 0, std::to_string(i + 1), Style{kMuted});
        put(screen, x + 2, 0, names[i], active ? Style{kBrightFg, {}, true} : Style{kMuted});
        x += 8;
    }
    size_t active_downloads = 0;
    for (const auto& row : downloads_) {
        if (row.state != "已完成" && row.state.rfind("失败", 0) != 0) ++active_downloads;
    }
    int right = width_ - 1;
    std::string account = demo_ ? "离线样例" : api_->logged_in() ? "已登录" : "游客";
    if (right - width_of(account) > x) {
        put_right(screen, right, 0, account, Style{api_->logged_in() ? kGreen : kMuted});
        right -= width_of(account) + 2;
    }
    if (active_downloads > 0) put_right(screen, right, 0, "↓ " + std::to_string(active_downloads), Style{kBlue});
}
void App::draw_search_box(Screen& screen) {
    const bool active = focus_ == Focus::Input;
    const Rect area{1, 1, width_ - 2, 3};
    box(screen, area, "", active);
    const std::string options = std::string(kOrderNames[static_cast<size_t>(order_)]) + " · " + kDurationNames[static_cast<size_t>(duration_)];
    const int option_width = area.width >= width_of(options) + 24 ? width_of(options) + 2 : 0;
    const int text_x = put(screen, area.x + 2, 2, "› ", Style{active ? kBlue : kMuted});
    const int room = std::max(area.x + area.width - 2 - option_width - text_x, 1);
    const std::string text = search_.str();
    if (text.empty()) {
        put(screen, text_x, 2, active ? "搜索视频、UP 主" : "s 搜索", Style{kMuted}, room);
    } else {
        put(screen, text_x, 2, clip(text, room), Style{active ? kBrightFg : kFg});
    }
    if (active) cursor_ = std::make_pair(std::min(text_x + width_of(search_.before_cursor()), text_x + room - 1), 2);
    if (option_width > 0) put_right(screen, area.x + area.width - 2, 2, options, Style{kMuted});
}
void App::draw_start(Screen& screen, Rect area) {
    if (area.height < 1) return;
    const int rows = static_cast<int>(choices_.size());
    const int content = rows > 0 ? rows + 3 : 2;
    const int column = std::clamp(width_ / 2 - 20, 1, std::max(width_ - 20, 1));
    int y = area.y + std::max((area.height - content) / 3, 0);
    const int room = width_ - column - 1;
    if (y < area.y + area.height) put(screen, column, y++, "想学点什么？", Style{kBrightFg}, room);
    if (y < area.y + area.height) put(screen, column, y++, "输入关键词后按 Enter", Style{kMuted}, room);
    if (rows == 0) return;
    ++y;
    if (y < area.y + area.height) put(screen, column, y++, search_.empty() ? "最近搜索" : "建议", Style{kMuted}, room);
    for (int i = 0; i < rows && y < area.y + area.height; ++i, ++y) {
        const bool selected = choice_ && *choice_ == static_cast<size_t>(i);
        if (selected) put(screen, column - 2, y, "▌", Style{kBlue});
        put(screen, column, y, clip(choices_[static_cast<size_t>(i)], room), Style{selected ? kBrightFg : kFg});
    }
}
void App::draw_now_playing(Screen& screen, int y) {
    fill(screen, Rect{0, y, width_, 1}, kSurface);
    const PlayerStatus& status = player_status_;
    int right = width_ - 1;
    if (status.queued > 0) {
        const std::string queued = "队列 " + std::to_string(status.queued);
        put_right(screen, right, y, queued, Style{kMuted, kSurface});
        right -= width_of(queued) + 2;
    }
    if (status.duration > 0) {
        const std::string time = seconds_text(status.position) + "/" + seconds_text(status.duration);
        put_right(screen, right, y, time, Style{kFg, kSurface});
        right -= width_of(time) + 1;
    }
    const int bar = status.duration > 0 && width_ >= 70 ? std::min(width_ / 6, 24) : 0;
    if (bar > 0) {
        right -= bar;
        put_bar(screen, right, y, bar, static_cast<double>(status.position) / static_cast<double>(status.duration), kGreen, kSurface);
        right -= 1;
    }
    const int x = put(screen, 1, y, "▶ ", Style{kGreen, kSurface});
    put(screen, x, y, clip(status.title, right - x - 1), Style{kBrightFg, kSurface});
}
void App::draw_footer(Screen& screen) {
    if (height_ < 1) return;
    std::vector<Hint> hints;
    if (modal_) {
        if (modal_->kind == Modal::Kind::Menu) hints = {{"↑↓", "选择"}, {"Enter", "确认"}, {"Esc", "取消"}};
        else hints = {{"Esc", "关闭"}};
    } else if (focus_ == Focus::Input) {
        hints = {{"Enter", "搜索"}, {"↑↓", "历史"}, {"Tab", "建议"}, {"Esc", "回到列表"}};
    } else if (focus_ == Focus::Filter) {
        hints = {{"↑↓", "选择"}, {"Enter", "保留"}, {"Esc", "恢复"}};
    } else if (focus_ == Focus::Parts) {
        hints = {{"Enter", "播放这一集"}, {"↑↓", "选择"}, {"←", "返回"}};
    } else {
        hints = {{"Enter", "播放"}, {"→", "分集"}, {"a", "排队"}, {"w", "稍后"}, {"u", "UP"}, {"/", "过滤"}, {"o", "排序"}, {"t", "时长"}, {"Space", "更多"}, {"?", "帮助"}, {"q", "退出"}};
    }
    const int y = height_ - 1;
    int room = width_ - 2;
    if (!notice_.empty()) {
        const std::string text = clip(notice_, std::min(width_ - 2, std::max(width_ * 2 / 5, 24)));
        put_right(screen, width_ - 1, y, text, Style{notice_error_ ? kRed : kBlue});
        room -= width_of(text) + 2;
    }
    put_hints(screen, 1, y, room, hints);
}
void App::draw_list(Screen& screen, Rect area) {
    list_rect_ = area;
    if (area.width < 8 || area.height < 2) return;
    ListState& state = list();
    const int label_room = area.width - 4;
    int label_x = put(screen, 2, area.y, clip(state.heading, label_room), Style{kMuted});
    if (!state.visible.empty()) label_x = put(screen, label_x + 1, area.y, std::to_string(state.visible.size()), Style{kBorder});
    if (!state.filter.empty()) label_x = put(screen, label_x + 1, area.y, "/" + clip(state.filter.str(), 16), Style{kYellow});
    if (state.loading) put(screen, label_x + 1, area.y, "加载中…", Style{kBlue});
    const Rect inner{area.x, area.y + 1, area.width - 1, area.height - 1};
    if (state.visible.empty()) {
        std::string message;
        if (state.loading) message = "正在请求 B 站…";
        else if (!state.error.empty()) message = state.error + "  R 重试";
        else if (!state.filter.empty()) message = "没有匹配 · Esc 清除过滤";
        else message = "没有内容 · R 刷新";
        int row = inner.y + 1;
        for (const auto& line : wrap(message, inner.width - 4, 4)) {
            put(screen, inner.x + 2, row++, line, Style{state.error.empty() ? kMuted : kRed});
        }
        return;
    }
    const bool cards = inner.height >= kCardLayoutRows;
    if (state.selected < state.offset) state.offset = state.selected;
    const auto heights = [&](size_t from, size_t to) {
        int total = 0;
        for (size_t i = from; i <= to; ++i) total += card_height(state.items[state.visible[i]], cards);
        return total;
    };
    while (state.offset < state.selected && heights(state.offset, state.selected) > inner.height) ++state.offset;
    // Fill the view when scrolled back from a shrunken list.
    while (state.offset > 0 && heights(state.offset - 1, state.visible.size() - 1) <= inner.height) --state.offset;
    const std::string query = state.filter.str();
    int y = inner.y;
    for (size_t index = state.offset; index < state.visible.size(); ++index) {
        const Video& item = state.items[state.visible[index]];
        const int height = card_height(item, cards);
        if (y + height > inner.y + inner.height) break;
        list_rows_.emplace_back(y, index);
        if (item.kind == Kind::Header) {
            put(screen, inner.x + 2, y, clip(item.title, inner.width - 4), Style{kMuted, {}, false, true});
            ++y;
            continue;
        }
        const bool selected = index == state.selected;
        const std::optional<uint32_t> bg = selected ? std::optional<uint32_t>(kSelection) : std::nullopt;
        if (selected) {
            fill(screen, Rect{inner.x, y, inner.width, height}, kSelection);
            for (int row = 0; row < height; ++row) put(screen, inner.x, y + row, "▌", Style{kBlue, bg});
        }
        std::string badge;
        if (item.kind == Kind::User) badge = "UP";
        if (item.kind == Kind::Video && item.count > 1) badge = std::to_string(item.count) + "P";
        const int right = inner.x + inner.width - 1;
        int cursor = inner.x + 2;
        if (!badge.empty()) cursor = put(screen, cursor, y, badge, Style{kBlue, bg}) + 1;
        std::string duration = item.kind == Kind::Folder ? std::to_string(item.count) + " 项" : item.kind == Kind::Video ? item.duration : "";
        const uint64_t total = item.kind == Kind::Video ? duration_seconds(item.duration) : 0;
        const bool finished = item.kind == Kind::Video && item.progress < 0;
        const bool partial = item.progress > 0 && total > 0;
        const Style title{selected ? kBrightFg : kFg, bg};
        if (!cards) {
            const int width = width_of(duration);
            put_right(screen, right, y, duration, Style{kMuted, bg});
            const int up_room = inner.width >= 70 && item.kind != Kind::Folder ? 16 : 0;
            if (up_room > 0) put(screen, right - width - 1 - up_room, y, clip(item.up, up_room - 1), Style{kMuted, bg});
            put_highlighted(screen, cursor, y, item.title, query, title, right - width - 1 - up_room - cursor - 1);
            ++y;
            continue;
        }
        put_highlighted(screen, cursor, y, item.title, query, title, right - cursor);
        // The second line: who, how popular, when, how long, then progress on the right.
        int progress_x = right;
        if (finished) {
            put_right(screen, right, y + 1, "已看完", Style{kGreen, bg});
            progress_x -= width_of("已看完") + 2;
        } else if (partial && inner.width >= 48) {
            const double fraction = std::min(static_cast<double>(item.progress) / static_cast<double>(total), 1.0);
            const std::string percent = std::to_string(static_cast<int>(fraction * 100)) + "%";
            put_right(screen, right, y + 1, percent, Style{kGreen, bg});
            progress_x -= width_of(percent) + 11;
            put_bar(screen, progress_x + 1, y + 1, 9, fraction, kGreen, bg);
            --progress_x;
        }
        std::vector<std::string> meta;
        if (item.kind == Kind::Video) meta = {duration, item.views > 0 ? count(item.views) : "", item.pubdate != 0 ? date_text(item.pubdate) : ""};
        if (item.kind == Kind::Folder) meta = {duration};
        const int meta_x = inner.x + 2;
        int x = meta_x;
        if (item.kind != Kind::Folder && !item.up.empty()) {
            const std::string up = clip(item.up, std::min(18, progress_x - meta_x));
            put_highlighted(screen, x, y + 1, up, query, Style{kMuted, bg}, progress_x - x);
            x += width_of(up);
        }
        const std::string rest = join_meta(meta);
        if (!rest.empty() && x + 3 < progress_x) {
            x = x > meta_x ? put(screen, x, y + 1, " · ", Style{kMuted, bg}) : x;
            put(screen, x, y + 1, clip(rest, progress_x - x), Style{kMuted, bg});
        }
        y += 2;
    }
    put_scroll(screen, area.x + area.width - 1, inner.y, inner.height, state.selected, state.visible.size());
}
void App::draw_preview(Screen& screen, Rect area) {
    preview_rect_ = area;
    if (area.width < 12 || area.height < 3) return;
    const Rect inner{area.x + 2, area.y, area.width - 4, area.height};
    const Video* selected = selected_video();
    if (!selected) {
        put(screen, inner.x, inner.y + 1, "选中一个视频查看详情", Style{kMuted});
        return;
    }
    const Details* details = selected_details();
    const Video& video = details ? details->video : *selected;
    int y = inner.y;
    if (focus_ == Focus::Parts) {
        put(screen, inner.x, y++, clip(video.title, inner.width), Style{kBrightFg});
    } else {
        y += 1;
        if (selected->kind == Kind::Video && inner.height >= 16) {
            // Terminal cells are about twice as tall as wide; covers are 16:9.
            const int rows = std::clamp(inner.width * 9 / 32, 4, std::max(inner.height / 2, 4));
            const Rect cover{inner.x, y, std::min(rows * 32 / 9, inner.width), rows};
            fill(screen, cover, kSurface);
            put(screen, cover.x + cover.width / 2 - 1, cover.y + rows / 2, "▶", Style{kBorder, kSurface});
            if (cover_ && cover_->first == selected->cover) cover_rect_ = cover;
            y += rows + 1;
        }
    }
    const int bottom = inner.y + inner.height;
    if (focus_ != Focus::Parts) {
        for (const auto& line : wrap(video.title, inner.width, 2)) {
            if (y < bottom) put(screen, inner.x, y++, line, Style{kBrightFg, {}, false, true});
        }
        if (selected->kind != Kind::Video) {
            if (y < bottom) put(screen, inner.x, y++, "Enter 打开", Style{kMuted});
            return;
        }
        if (y < bottom) put(screen, inner.x, y++, clip(video.up, inner.width), Style{kBlue});
        std::string meta = join_meta({count(video.views) + " 播放", video.pubdate != 0 ? date_text(video.pubdate) : "", video.duration});
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
        if (y < bottom) put(screen, inner.x, y++, std::string(has_parts ? "分 P " : "合集 ") + std::to_string(total) + (focus_ == Focus::Parts ? "" : "  → 进入"), Style{kMuted});
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
                const std::string label = has_parts ? std::to_string(video.parts[i].page) + "  " + video.parts[i].title : video.collection[i].title;
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
            for (const auto& line : wrap(video.description, inner.width, static_cast<size_t>(rows))) put(screen, inner.x, y++, line, Style{kMuted});
        }
    }
}
void App::draw_modal(Screen& screen) {
    const Modal& modal = *modal_;
    const auto centered = [&](int width, int height) { return tui::centered(width_, height_, width, height); };
    if (modal.kind == Modal::Kind::Menu) {
        int longest = width_of(modal.title) + 6;
        for (const auto& item : modal.items) longest = std::max(longest, width_of(item.label) + 6);
        const Rect area = centered(std::max(longest, 36), static_cast<int>(modal.items.size()) + 2);
        fill(screen, area, kSurface);
        box(screen, area, modal.title, false, kSurface);
        for (size_t i = 0; i < modal.items.size() && static_cast<int>(i) < area.height - 2; ++i) {
            const int y = area.y + 1 + static_cast<int>(i);
            const bool selected = i == modal.selected;
            const uint32_t bg = selected ? kSelection : kSurface;
            fill(screen, Rect{area.x + 1, y, area.width - 2, 1}, bg);
            if (selected) put(screen, area.x + 1, y, "▌", Style{kBlue, bg});
            put(screen, area.x + 3, y, clip(modal.items[i].label, area.width - 5), Style{selected ? kBrightFg : kFg, bg});
        }
    } else if (modal.kind == Modal::Kind::Downloads) {
        const int rows = std::max<int>(static_cast<int>(downloads_.size()), 1);
        const Rect area = centered(std::min(width_ - 4, 90), std::min(rows + 2, height_ - 2));
        fill(screen, area, kSurface);
        box(screen, area, modal.title, false, kSurface);
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
        box(screen, area, modal.title, false, kSurface);
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
        if (modal.kind == Modal::Kind::Help) {
            const int rows = static_cast<int>(lines.size());
            const Rect help = centered(std::min(width_ - 2, 78), rows + 4);
            fill(screen, help, kSurface);
            box(screen, help, modal.title, false, kSurface);
            int row = help.y + 2;
            for (const auto& line : lines) {
                if (row >= help.y + help.height - 1) break;
                // The key column is whatever precedes the double space.
                const auto gap = line.find("  ");
                if (gap == std::string::npos) {
                    put(screen, help.x + 3, row, clip(line, help.width - 6), Style{kMuted, kSurface});
                } else {
                    const int after = put(screen, help.x + 3, row, line.substr(0, gap), Style{kBlue, kSurface});
                    put(screen, std::max(after + 2, help.x + 16), row, clip(trim(line.substr(gap)), help.width - 19), Style{kFg, kSurface});
                }
                ++row;
            }
            return;
        }
        const Rect area = centered(std::min(width_ - 2, 78), static_cast<int>(lines.size()) + 2);
        fill(screen, area, kSurface);
        box(screen, area, modal.title, false, kSurface);
        int y = area.y + 1;
        for (const auto& line : lines) {
            if (y < area.y + area.height - 1) put(screen, area.x + 2, y++, line, Style{kFg, kSurface});
        }
    }
}
}  // namespace bili
