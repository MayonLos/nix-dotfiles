#include "page.hpp"

#include <algorithm>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <iostream>
#include <set>

#include "app.hpp"
#include "ui/text.hpp"
#include "ui/widgets.hpp"

using ftxui::Screen;
using tui::InputEvent;
using tui::Key;
using tui::KeyCode;
using tui::Rect;
using tui::Style;

namespace keys {
namespace {
// Rows above the list, then the detail panel and the footer below it.
constexpr int kHeader = 3;
constexpr int kDetail = 3;
constexpr int kFooter = 2;

std::string read_file(const std::string& path, const std::string& hint) {
    const auto fail = [&] {
        const int code = errno;
        return Error("无法读取 " + path + "；" + hint, std::string(std::strerror(code)) + " (os error " + std::to_string(code) + ")");
    };
    const std::unique_ptr<std::FILE, int (*)(std::FILE*)> file(std::fopen(path.c_str(), "rb"), std::fclose);
    if (!file) throw fail();
    std::string out;
    char buffer[65536];
    // Opening a directory succeeds; only the read fails.
    while (const size_t got = std::fread(buffer, 1, sizeof buffer, file.get())) out.append(buffer, got);
    if (std::ferror(file.get())) throw fail();
    return out;
}
void print_error(std::ostream& err, const Error& error) {
    err << "Error: " << error.what() << "\n";
    if (!error.cause.empty()) err << "\nCaused by:\n    " << error.cause << "\n";
}
}  // namespace

Layout layout_rows(const std::vector<Entry>& items, const std::vector<size_t>& visible, size_t columns) {
    Layout out;
    if (visible.empty()) return out;
    const size_t first_group = items[visible.front()].group;
    if (std::all_of(visible.begin(), visible.end(), [&](size_t i) { return items[i].group == first_group; })) {
        const size_t per_column = (visible.size() + columns - 1) / columns;
        for (size_t start = 0, column = 0; start < visible.size(); start += per_column, ++column) {
            out.positions.push_back(Position{column, 0, first_group, std::nullopt});
            for (size_t row = 0; row < per_column && start + row < visible.size(); ++row) out.positions.push_back(Position{column, 1 + row, first_group, start + row});
        }
        out.total = 1 + per_column;
        return out;
    }
    std::vector<size_t> heights(columns, 0);
    for (size_t group = 0; group < kGroups.size(); ++group) {
        std::vector<size_t> rows;
        for (size_t i = 0; i < visible.size(); ++i) {
            if (items[visible[i]].group == group) rows.push_back(i);
        }
        if (rows.empty()) continue;
        const auto shortest = static_cast<size_t>(std::min_element(heights.begin(), heights.end()) - heights.begin());
        out.positions.push_back(Position{shortest, heights[shortest]++, group, std::nullopt});
        for (const size_t selection : rows) out.positions.push_back(Position{shortest, heights[shortest]++, group, selection});
        ++heights[shortest];
    }
    out.total = *std::max_element(heights.begin(), heights.end());
    return out;
}
size_t columns_for(int width, size_t group_count) {
    const size_t most = width >= 138 ? 3 : width >= 88 ? 2 : 1;
    return std::min(most, std::max<size_t>(group_count, 1));
}

KeysPage::KeysPage(std::optional<std::string> data_path) : requested_path_(std::move(data_path)) { load(); }
KeysPage::KeysPage(std::vector<Entry> items, std::string path) : path_(std::move(path)), items_(std::move(items)) { index_rows(); }
void KeysPage::load() {
    try {
        path_ = requested_path_ ? *requested_path_ : default_data_path();
        items_ = entries(parse_export(read_file(path_, "请先安装 Mango 快捷键数据")));
        index_rows();
        error_.reset();
    } catch (const Error& error) {
        items_.clear();
        search_.clear();
        error_ = error.what();
    }
}
void KeysPage::index_rows() {
    search_.clear();
    search_.reserve(items_.size());
    for (const Entry& e : items_) search_.emplace_back(e.chord + " " + e.description + " " + e.binding.mode + " " + e.binding.kind + " " + e.binding.raw);
}
std::vector<size_t> KeysPage::visible() const {
    const Matcher matcher(query_.str());
    std::vector<std::pair<size_t, uint32_t>> scored;
    for (size_t i = 0; i < items_.size(); ++i) {
        if (group_ && items_[i].group != *group_) continue;
        if (const auto found = matcher.find_in(search_[i])) scored.emplace_back(i, found->score);
    }
    // Raw Mango actions are long; fall back to subsequences only without a real hit.
    const bool strong = std::any_of(scored.begin(), scored.end(), [&](const auto& row) { return row.second >= matcher.strong_score(); });
    std::vector<size_t> out;
    for (const auto& [index, score] : scored) {
        if (!strong || score >= matcher.strong_score()) out.push_back(index);
    }
    std::stable_sort(out.begin(), out.end(), [&](size_t a, size_t b) { return items_[a].group < items_[b].group; });
    return out;
}
std::optional<size_t> KeysPage::selected_id() const {
    const auto rows = visible();
    if (selected_ < rows.size()) return rows[selected_];
    return std::nullopt;
}
void KeysPage::keep_selected(std::optional<size_t> id) {
    selected_ = 0;
    if (!id) return;
    const auto rows = visible();
    const auto found = std::find(rows.begin(), rows.end(), *id);
    if (found != rows.end()) selected_ = static_cast<size_t>(found - rows.begin());
}
void KeysPage::move_selection(int delta, size_t count) {
    const size_t last = count > 0 ? count - 1 : 0;
    if (delta < 0) selected_ = selected_ > 0 ? selected_ - 1 : 0;
    else selected_ = std::min(selected_ + 1, last);
    selected_ = std::min(selected_, last);
}
void KeysPage::reset() {
    selected_ = 0;
    scroll_ = 0;
}
void KeysPage::pick_group(std::optional<size_t> group) {
    group_ = group;
    reset();
    follow_ = true;
}
bool KeysPage::handle(const InputEvent& event) {
    if (error_) {
        if (event.type != InputEvent::Type::Key) return false;
        if (event.key.ctrl && event.key.ch == U'c') return true;
        if (event.key.is(U'R')) load();
        return event.key.is(U'q') || event.key.code == KeyCode::Escape;
    }
    switch (event.type) {
        case InputEvent::Type::Key:
            return handle_key(event.key);
        case InputEvent::Type::Paste:
            if (editing_ && !help_ && !details_) {
                const auto id = selected_id();
                const std::string before = query_.str();
                query_.paste(event.paste);
                if (query_.str() != before) keep_selected(id);
                follow_ = true;
            }
            return false;
        case InputEvent::Type::MouseClick:
        case InputEvent::Type::WheelUp:
        case InputEvent::Type::WheelDown:
            if (!help_) handle_mouse(event);
            return false;
        case InputEvent::Type::FocusIn:
        case InputEvent::Type::FocusOut:
            return false;
    }
    return false;
}
bool KeysPage::handle_key(const Key& key) {
    if (key.ctrl && key.ch == U'c') return true;
    if (help_) {
        if (key.code == KeyCode::Escape || key.is(U'?')) help_ = false;
        return key.is(U'q');
    }
    if (details_) {
        if (key.code == KeyCode::Escape || key.code == KeyCode::Enter) details_ = false;
        if (key.code == KeyCode::Up) detail_scroll_ = std::max(detail_scroll_ - 1, 0);
        if (key.code == KeyCode::Down) ++detail_scroll_;
        return key.is(U'q');
    }
    const size_t count = visible().size();
    if (editing_) {
        const auto id = selected_id();
        if (key.code == KeyCode::Escape) {
            query_ = previous_query_;
            editing_ = false;
            keep_selected(id);
        } else if (key.code == KeyCode::Enter) {
            editing_ = false;
        } else if (key.code == KeyCode::Down) {
            move_selection(1, count);
        } else if (key.code == KeyCode::Up) {
            move_selection(-1, count);
        } else if (query_.handle(key)) {
            keep_selected(id);
        }
        follow_ = true;
        return false;
    }
    if (key.code == KeyCode::Escape) {
        if (query_.empty()) return true;
        const auto id = selected_id();
        query_.clear();
        keep_selected(id);
        follow_ = true;
        return false;
    }
    if (key.ctrl || key.alt) return false;
    if (key.is(U'q')) return true;
    if (key.is(U'/')) {
        previous_query_ = query_;
        editing_ = true;
    } else if (key.is(U'?')) {
        help_ = true;
    } else if (key.code == KeyCode::Enter) {
        details_ = true;
        detail_scroll_ = 0;
    } else if (key.code == KeyCode::Char && key.ch >= U'0' && key.ch <= U'7') {
        pick_group(key.ch == U'0' ? std::nullopt : std::optional<size_t>(key.ch - U'1'));
    } else if (key.is(U'j') || key.code == KeyCode::Down) {
        move_selection(1, count);
        follow_ = true;
    } else if (key.is(U'k') || key.code == KeyCode::Up) {
        move_selection(-1, count);
        follow_ = true;
    } else if (key.code == KeyCode::PageDown) {
        scroll_ += viewport_ > 2 ? viewport_ - 2 : 0;
    } else if (key.code == KeyCode::PageUp) {
        const size_t step = viewport_ > 2 ? viewport_ - 2 : 0;
        scroll_ = scroll_ > step ? scroll_ - step : 0;
    } else if (key.code == KeyCode::Home || key.is(U'g')) {
        selected_ = 0;
        follow_ = true;
    } else if (key.code == KeyCode::End || key.is(U'G')) {
        selected_ = count > 0 ? count - 1 : 0;
        follow_ = true;
    }
    return false;
}
void KeysPage::handle_mouse(const InputEvent& event) {
    if (details_) {
        if (event.type == InputEvent::Type::WheelDown) detail_scroll_ += 2;
        if (event.type == InputEvent::Type::WheelUp) detail_scroll_ = std::max(detail_scroll_ - 2, 0);
        return;
    }
    if (event.type == InputEvent::Type::WheelDown) {
        scroll_ += 3;
    } else if (event.type == InputEvent::Type::WheelUp) {
        scroll_ = scroll_ > 3 ? scroll_ - 3 : 0;
    } else {
        for (const auto& [rect, group] : tabs_) {
            if (rect.contains(event.x, event.y)) {
                pick_group(group);
                return;
            }
        }
        for (const auto& [rect, selection] : hits_) {
            if (rect.contains(event.x, event.y)) {
                selected_ = selection;
                return;
            }
        }
    }
}
void KeysPage::draw_tabs(Screen& screen, Rect row) {
    tabs_.clear();
    int x = row.x + 1;
    const int right = row.x + row.width;
    for (size_t number = 0; number <= kGroups.size() && x < right; ++number) {
        const std::optional<size_t> group = number == 0 ? std::nullopt : std::optional<size_t>(number - 1);
        const std::string name = number == 0 ? "全部" : std::string(kGroups[number - 1]);
        const bool active = group == group_;
        const int start = x;
        x = tui::put(screen, x, row.y, std::to_string(number), Style{tui::kMuted}, right - x);
        x = tui::put(screen, x + 1, row.y, name, active ? Style{tui::kBrightFg, {}, true} : Style{tui::kMuted}, std::max(right - x - 1, 0));
        tabs_.emplace_back(Rect{start, row.y, x - start + 1, 1}, group);
        x += 2;
    }
}
void KeysPage::draw_query(Screen& screen, Rect row) {
    cursor_.reset();
    if (!editing_) {
        tui::put(screen, row.x + 1, row.y, tui::clip("/ 过滤 " + query_.str(), row.width - 2), Style{tui::kMuted});
        return;
    }
    const int start = tui::put(screen, row.x + 1, row.y, "/ ", Style{tui::kBlue}, std::max(row.width - 1, 0));
    const int room = row.x + row.width - start - 1;
    if (room <= 0 || row.y >= screen.dimy()) return;
    // Scrolls horizontally so the cursor always stays on screen.
    std::u32string before = tui::decode(query_.before_cursor());
    const std::u32string all = tui::decode(query_.str());
    size_t skip = 0;
    int used = tui::width_of(tui::encode(before));
    while (used >= room && skip < before.size()) used -= tui::width_of(tui::encode(std::u32string_view(before).substr(skip++, 1)));
    tui::put(screen, start, row.y, tui::encode(std::u32string_view(all).substr(skip)), Style{tui::kBlue}, room);
    cursor_ = std::make_pair(start + used, row.y);
}
void KeysPage::draw_list(Screen& screen, Rect list, const std::vector<size_t>& visible) {
    std::set<size_t> groups;
    for (const size_t i : visible) groups.insert(items_[i].group);
    columns_ = columns_for(list.width, groups.size());
    const Layout rows = layout_rows(items_, visible, columns_);
    total_rows_ = rows.total;
    viewport_ = static_cast<size_t>(std::max(list.height, 0));
    if (follow_) {
        for (const Position& position : rows.positions) {
            if (position.selection != selected_) continue;
            if (position.y < scroll_) scroll_ = position.y;
            if (position.y + 1 > scroll_ + viewport_) scroll_ = position.y + 1 > viewport_ ? position.y + 1 - viewport_ : 0;
            break;
        }
    }
    scroll_ = std::min(scroll_, total_rows_ > viewport_ ? total_rows_ - viewport_ : 0);
    hits_.clear();
    if (visible.empty()) {
        const auto lines = tui::wrap("没有匹配。Esc 清除过滤；/ 修改搜索；0 查看全部分组。", list.width - 2, static_cast<size_t>(std::max(list.height, 0)));
        for (size_t i = 0; i < lines.size(); ++i) tui::put(screen, list.x + 1, list.y + static_cast<int>(i), lines[i], Style{tui::kMuted});
        return;
    }
    const int columns = static_cast<int>(columns_);
    const int width = (list.width - (columns - 1)) / columns;
    const Matcher matcher(query_.str());
    // Longer chords push the description column out, up to half the row.
    int longest = 0;
    for (const size_t i : visible) longest = std::max(longest, tui::width_of((items_[i].conflict ? "! " : "") + items_[i].chord));
    const int chord_room = std::max(20, std::min(longest + 2, width / 2));
    for (const Position& position : rows.positions) {
        if (position.y < scroll_ || position.y >= scroll_ + viewport_) continue;
        const Rect row{list.x + static_cast<int>(position.column) * (width + 1), list.y + static_cast<int>(position.y - scroll_), width, 1};
        if (!position.selection) {
            tui::put(screen, row.x + 2, row.y, std::string(kGroups[position.group]), Style{tui::kMuted, {}, false, true}, std::max(width - 2, 0));
            continue;
        }
        const Entry& e = items_[visible[*position.selection]];
        const bool selected = *position.selection == selected_;
        std::optional<uint32_t> bg;
        if (selected) {
            tui::fill(screen, row, tui::kSelection);
            bg = tui::kSelection;
            tui::put(screen, row.x, row.y, "▌", Style{tui::kBlue, bg}, std::max(width, 0));
        }
        const std::string chord = (e.conflict ? "! " : "") + e.chord;
        const int pad = std::max(chord_room - tui::width_of(chord), 1);
        const std::string mode = e.binding.mode == "default" ? "" : " · " + e.binding.mode;
        const std::string text = tui::clip(chord + std::string(static_cast<size_t>(pad), ' ') + e.description + mode, width - 2);
        const uint32_t color = e.conflict ? tui::kRed : selected ? tui::kBrightFg : tui::kFg;
        tui::put_ranges(screen, row.x + 2, row.y, text, matcher.highlight(text), Style{color, bg}, width - 2);
        hits_.emplace_back(row, *position.selection);
    }
}
void KeysPage::draw_details(Screen& screen, const Entry& e) const {
    const Rect area = tui::centered(screen.dimx(), screen.dimy(), std::min(screen.dimx() - 2, 100), std::min(screen.dimy() - 2, 20));
    tui::fill(screen, area, tui::kSurface);
    tui::box(screen, area, "原始动作 · ↑/↓ 滚动 · Enter/Esc 返回", false, tui::kSurface);
    const int room = area.width - 6;
    constexpr size_t kAll = 100000;
    std::vector<std::pair<std::string, uint32_t>> lines;
    const auto add = [&](const std::string& text, uint32_t color) {
        if (text.empty()) lines.emplace_back("", color);
        for (const std::string& line : tui::wrap(text, room, kAll)) lines.emplace_back(line, color);
    };
    add(e.chord, tui::kBrightFg);
    add(std::string(kGroups[e.group]) + " · " + e.binding.mode + " · " + e.binding.kind, tui::kMuted);
    add("", tui::kFg);
    add(e.description, tui::kFg);
    add("", tui::kFg);
    add("原始 Mango 动作", tui::kMuted);
    add(e.binding.raw, tui::kFg);
    int y = area.y + 1;
    for (size_t i = static_cast<size_t>(detail_scroll_); i < lines.size() && y < area.y + area.height - 1; ++i, ++y) {
        tui::put(screen, area.x + 3, y, lines[i].first, Style{lines[i].second, tui::kSurface}, std::max(room, 0));
    }
}
void KeysPage::draw_help_dialog(Screen& screen) const {
    std::vector<std::string> lines{
        "0 1 2 3  全部 · 窗口 · 工作区 · 应用",
        "4 5 6 7  TUI 工具 · 截图 · 媒体 · 系统",
        "/  按键名或中文说明模糊搜索（跨分组保留过滤）",
        "搜索中  Enter 结束 · Esc 恢复编辑前过滤 · ↑/↓ 选择",
        "Ctrl+U  清到行首；Backspace 删除",
        "j/k ↑/↓  选择",
        "PgUp/PgDn  翻页",
        "Home/End  首尾（g/G 同）",
        "鼠标  滚轮滚动 · 点击条目选择 · 点击顶部分组切页",
        "Enter  查看完整原始动作（↑/↓、滚轮可滚动）",
        "红色 !  同设备、重叠模式的相同组合",
        "Esc  列表先清过滤再退出",
        "common 在所有模式生效；resize 需先按 SUPER+R",
        "",
    };
    const int room = std::min(screen.dimx() - 2, 78) - 6;
    for (const std::string& line : tui::wrap("数据文件：" + path_, room, 4)) lines.push_back(line);
    tui::draw_help(screen, "帮助 · ? / Esc 关闭", lines);
}
void KeysPage::draw(Screen& screen, Rect area) {
    if (area.width != last_area_.width || area.height != last_area_.height) follow_ = true;
    last_area_ = area;
    cursor_.reset();
    if (error_) {
        tui::put(screen, area.x + 1, area.y, "快捷键速查", Style{tui::kBrightFg}, std::max(area.width - 2, 0));
        const auto lines = tui::wrap(*error_, area.width - 2, 6);
        int y = area.y + 2;
        for (const std::string& line : lines) tui::put(screen, area.x + 1, y++, line, Style{tui::kRed});
        tui::put_hints(screen, area.x + 1, area.y + area.height - 1, area.width - 2, {{"R", "重试"}, {"q/Esc", "关闭"}});
        return;
    }
    const auto rows = visible();
    selected_ = std::min(selected_, rows.empty() ? size_t{0} : rows.size() - 1);
    const size_t conflicts = static_cast<size_t>(std::count_if(items_.begin(), items_.end(), [](const Entry& e) { return e.conflict; }));
    const std::string title = "快捷键速查  Mango · " + std::to_string(rows.size()) + " / " + std::to_string(items_.size()) + " 条 · " + std::to_string(conflicts) + " 条冲突";
    tui::put(screen, area.x + 1, area.y, tui::clip(title, area.width - 2), Style{tui::kBrightFg});
    draw_tabs(screen, Rect{area.x, area.y + 1, area.width, 1});
    draw_query(screen, Rect{area.x, area.y + 2, area.width, 1});
    const int list_height = std::max(area.height - kHeader - kDetail - kFooter, 0);
    draw_list(screen, Rect{area.x, area.y + kHeader, area.width, list_height}, rows);
    follow_ = false;
    int y = area.y + kHeader + list_height;
    if (selected_ < rows.size()) {
        const Entry& e = items_[rows[selected_]];
        const auto lines = tui::wrap(e.chord + "  [" + e.binding.mode + " · " + e.binding.kind + "] " + e.description + "\n" + e.binding.raw, area.width - 2, kDetail);
        for (size_t i = 0; i < lines.size(); ++i) tui::put(screen, area.x + 1, y + static_cast<int>(i), lines[i], Style{i == 0 ? tui::kFg : tui::kMuted});
    }
    y += kDetail;
    tui::put_hints(screen, area.x + 1, y, area.width - 2, {{"/", "搜索"}, {"0–7", "分组"}, {"j/k", "移动"}, {"Enter", "原文"}, {"q/Esc", "关闭"}, {"?", "帮助"}});
    const std::string where = "行 " + std::to_string(scroll_ + (total_rows_ > 0 ? 1 : 0)) + "–" + std::to_string(std::min(scroll_ + viewport_, total_rows_)) + " / " + std::to_string(total_rows_) + " · 数据：生成的 Mango 配置";
    tui::put(screen, area.x + 1, y + 1, tui::clip(where, area.width - 2), Style{tui::kMuted});
    if (help_) {
        draw_help_dialog(screen);
    } else if (details_ && selected_ < rows.size()) {
        draw_details(screen, items_[rows[selected_]]);
    }
    // The dialog hides the input, so the cursor does not stay on top of it.
    if (help_ || details_) cursor_.reset();
}

int run_cli(const std::vector<std::string>& args, std::ostream& out, std::ostream& err) {
    try {
        std::optional<std::string> path;
        std::optional<std::string> page_path;
        bool list = false;
        bool json = false;
        for (size_t i = 0; i < args.size(); ++i) {
            const std::string& arg = args[i];
            if (arg == "--data") {
                if (i + 1 >= args.size()) throw Error("--data 需要路径");
                path = args[++i];
                // The Rust page takes the first --data and the listing the last.
                if (!page_path) page_path = path;
            } else if (arg == "list" && !list) {
                list = true;
            } else if (arg == "--json") {
                json = true;
            } else if (arg == "--help" || arg == "-h") {
                out << "mayon-tools keys [--data PATH] [list [--json]]\n\nMango 快捷键速查（生成数据，只读）\n默认读取 $XDG_CONFIG_HOME/keys-mayon/bindings.json\n可用 KEYS_MAYON_DATA 或 --data 覆盖。\n\n/ 模糊搜索 · 0 全部 / 1–7 分组 · j/k 移动 · 鼠标滚动\nEnter 原始动作 · ? 帮助 · q / Esc 关闭\n";
                return 0;
            } else if (arg == "--version" || arg == "-V") {
                out << "keys-mayon 0.1.0\n";
                return 0;
            } else {
                throw Error("未知参数 " + arg + "，请运行 mayon-tools keys --help");
            }
        }
        if (json && !list) throw Error("--json 需要 list 子命令");
        if (!list) {
            KeysPage page(page_path);
            return tui::run_page(page);
        }
        const std::string file = path ? *path : default_data_path();
        const auto items = entries(parse_export(read_file(file, "请先构建并安装 Mango 导出的 JSON，或指定 --data")));
        out << (json ? to_json(items) : to_text(items));
        return 0;
    } catch (const Error& error) {
        print_error(err, error);
        return 1;
    }
}
}  // namespace keys

std::unique_ptr<tui::Page> make_keys_page() { return std::make_unique<keys::KeysPage>(); }
std::unique_ptr<tui::Page> make_keys_page(const std::string& data_path) { return std::make_unique<keys::KeysPage>(std::optional<std::string>(data_path)); }
int keys_cli(int argc, char** argv) {
    std::vector<std::string> args;
    for (int i = 1; i < argc; ++i) args.emplace_back(argv[i]);
    return keys::run_cli(args, std::cout, std::cerr);
}
