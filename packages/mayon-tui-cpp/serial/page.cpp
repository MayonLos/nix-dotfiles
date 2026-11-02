#include "page.hpp"

#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <cstdarg>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <iterator>
#include <limits>
#include <string_view>
#include <tuple>
#include <vector>

#include "screen.hpp"
#include "ui/search.hpp"
#include "ui/text.hpp"
#include "ui/widgets.hpp"

using ftxui::Screen;
using tui::Column;
using tui::Hint;
using tui::InputEvent;
using tui::Key;
using tui::KeyCode;
using tui::Rect;
using tui::Style;

namespace serial {
namespace {
constexpr std::array<const char*, 3> kModeNames{"TEXT", "HEX", "MIX"};
constexpr std::array<const char*, 5> kPageNames{"监视", "端口", "参数", "命令", "烧录"};
constexpr std::array<uint32_t, 5> kSeriesColors{tui::kBlue, tui::kGreen, tui::kYellow, tui::kBlue, tui::kRed};
constexpr const char* kHelp =
    "1 监视 · 2 端口 · 3 参数 · 4 命令 · 5 烧录 · q 退出\n\n"
    "Enter / i 发送输入 · ↑↓ 输入历史 · Esc 取消输入\n"
    "x 发送 TEXT/HEX · e 行尾 · F 发送文件（原字节 ≤1MiB）\n"
    "t 定时重复上次发送（毫秒；0 停止）\n"
    "/ / f 过滤 · Ctrl+f 搜索 · n / N 下 / 上一条 · 空内容清除\n"
    "p / Space 暂停跟随 · PgUp/PgDn / 滚轮 回滚 · End 跟随\n"
    "v 接收 TEXT/HEX/MIX · T 时间戳 · g UTF-8/GBK\n"
    "w 波形开关 · l 日志开关 · c CSV（下次开始日志生效）\n"
    "b 常用波特率 · B 自定义 · s 全部参数 · h 高亮词\n"
    "d DTR · r RTS · D / R 脉冲100ms（恢复原电平）\n"
    "4 命令页：a 收藏 · ↑↓ 选择 · Enter 载入（不立即发送）\n"
    "5 烧录页：o 命令 · O 工作目录 · F5 执行（X 需再确认） · Esc 取消\n"
    "2 端口页：↑↓/鼠标选择 · Enter 连接 · u 主动断开\n\n"
    "暂停仍接收/记日志。回滚默认10万行，上限32MiB；满后淘汰最旧行。\n"
    "原始 .bin 保留日志开启后的全部接收字节；.log 带时间戳。";
constexpr const char* kUsage = "用法：mayon-tools serial [<端口> [-b 波特率]] 或 mayon-tools serial list";

std::string format(const char* pattern, ...) __attribute__((format(printf, 1, 2)));
std::string format(const char* pattern, ...) {
    va_list args;
    va_start(args, pattern);
    std::array<char, 512> buffer;
    const int size = std::vsnprintf(buffer.data(), buffer.size(), pattern, args);
    va_end(args);
    if (size < 0) return {};
    if (static_cast<size_t>(size) < buffer.size()) return std::string(buffer.data(), static_cast<size_t>(size));
    std::string out(static_cast<size_t>(size), '\0');
    va_start(args, pattern);
    std::vsnprintf(out.data(), out.size() + 1, pattern, args);
    va_end(args);
    return out;
}
std::string hex_text(const Bytes& bytes, size_t limit) {
    static constexpr char kDigits[] = "0123456789ABCDEF";
    std::string out;
    for (size_t i = 0; i < limit && i < bytes.size(); ++i) {
        if (i != 0) out += ' ';
        out += kDigits[bytes[i] >> 4];
        out += kDigits[bytes[i] & 15];
    }
    if (bytes.size() > limit) out += " …";
    return out;
}
std::string ascii_text(const Bytes& bytes) {
    std::string out;
    for (const uint8_t byte : bytes) out += byte >= 32 && byte < 127 ? static_cast<char>(byte) : '.';
    return out;
}
std::string mix_text(const Bytes& bytes) {
    std::string hex = hex_text(bytes, 16);
    if (hex.size() < 47) hex += std::string(47 - hex.size(), ' ');
    return hex + " │ " + ascii_text(bytes);
}
std::vector<std::string> split_lines(const std::string& text) {
    std::vector<std::string> lines;
    size_t at = 0;
    while (at <= text.size()) {
        const size_t next = text.find('\n', at);
        lines.emplace_back(text.substr(at, next == std::string::npos ? std::string::npos : next - at));
        if (next == std::string::npos) break;
        at = next + 1;
    }
    return lines;
}
std::string padded_kind(const std::string& kind) {
    const int width = tui::width_of(kind);
    return width >= 2 ? kind : std::string(static_cast<size_t>(2 - width), ' ') + kind;
}
std::string input_label(const App& app) {
    const Input& input = *app.input;
    switch (input.kind) {
        case InputKind::Send:
            return app.tx_hex ? "发送 HEX · 原字节，无附加行尾" : "发送文本 · ↑↓ 历史";
        case InputKind::Search:
            return "搜索 · 空内容清除 · n / N 下 / 上一条";
        case InputKind::Filter:
            return "过滤 · 空内容显示全部";
        case InputKind::Baud:
            return "自定义波特率";
        case InputKind::Settings:
            return "串口参数 · baud / bits / parity / stop / flow";
        case InputKind::Favorite:
            return "收藏 · 名称=命令";
        case InputKind::File:
            return "发送文件 · 原字节，无行尾 · 路径";
        case InputKind::Timer:
            return "重复发送 · 毫秒 · 0 停止";
        case InputKind::FlashCommand:
            return "烧录命令 · 由 shell 执行 · 不猜型号";
        case InputKind::FlashDir:
            return "烧录工作目录 · 空值为启动目录";
        case InputKind::Highlights:
            return "高亮词 · 逗号分隔";
    }
    return {};
}
std::vector<Hint> page_hints(size_t page) {
    switch (page) {
        case 0:
            return {{"i", "发送"}, {"/", "过滤"}, {"Ctrl+f", "搜索"}, {"p", "暂停"}, {"l", "日志"}, {"w", "波形"}, {"F5", "烧录"}, {"?", "帮助"}, {"q", "退出"}};
        case 1:
            return {{"↑↓", "选择"}, {"Enter", "连接"}, {"u", "断开"}, {"g/G", "首尾"}, {"?", "帮助"}, {"q", "退出"}};
        case 2:
            return {{"Enter", "修改"}, {"b/B", "波特率"}, {"g", "编码"}, {"d/r", "DTR/RTS"}, {"?", "帮助"}, {"q", "退出"}};
        case 3:
            return {{"a", "收藏"}, {"Enter", "载入"}, {"i", "输入"}, {"F", "文件"}, {"?", "帮助"}, {"q", "退出"}};
        default:
            return {{"o", "命令"}, {"O", "目录"}, {"X", "执行"}, {"Esc", "取消"}, {"?", "帮助"}, {"q", "退出"}};
    }
}
// Port table columns keep the serial number readable and never starve the product field.
std::vector<Column> port_columns(int width) {
    const int inner = std::max(width - 2, 10);
    const int port = std::min(17, inner / 3);
    const int vid = 9;
    int rest = std::max(inner - port - vid - 2, 6);
    int product = rest * 62 / 100;
    if (product < 6) product = 6;
    int serial = rest - product;
    if (serial < 4) serial = 4;
    return {Column{"端口", port}, Column{"VID:PID", vid}, Column{"产品 / 适配器", product}, Column{"序列号", serial}};
}
std::vector<Column> favorite_columns(int width) {
    const int inner = std::max(width - 2, 10);
    const int name = std::min(18, std::max(inner / 4, 8));
    const int mode = 6;
    return {Column{"名称", name}, Column{"模式", mode}, Column{"命令", std::max(inner - name - mode - 2, 8)}};
}
std::vector<Column> setting_columns(int width) {
    const int inner = std::max(width - 2, 10);
    const int name = 12;
    const int value = 16;
    return {Column{"参数", name}, Column{"值", value}, Column{"快捷键", std::max(inner - name - value - 2, 10)}};
}
void draw_empty(Screen& screen, Rect area, const std::vector<std::string>& lines, int limit) {
    int y = area.y;
    for (const std::string& line : lines) {
        if (y >= area.y + area.height) break;
        tui::put(screen, area.x + 1, y++, tui::clip(line, area.width - 2), Style{tui::kMuted}, limit);
    }
}
}  // namespace

SerialPage::SerialPage() : SerialPage(std::vector<std::string>{}) {}
SerialPage::SerialPage(const std::vector<std::string>& args) : args_(args) { load(); }
void SerialPage::attach(tui::Post post) { post_ = std::move(post); }
void SerialPage::wake() {
    if (post_) post_([] {});
}
void SerialPage::load() {
    error_.clear();
    app_.reset();
    try {
        Store store = Store::load();
        app_ = std::make_unique<App>(std::move(store), [this] { wake(); });
        apply_args(*app_);
    } catch (const std::exception& error) {
        app_.reset();
        error_ = error.what();
    }
}
void SerialPage::apply_args(App& app) {
    std::optional<std::string> port;
    std::optional<uint32_t> baud;
    for (size_t i = 0; i < args_.size(); ++i) {
        const std::string& arg = args_[i];
        if (arg == "-b" || arg == "--baud") {
            if (++i >= args_.size()) throw std::runtime_error("-b 缺少波特率");
            const auto parsed = parse_unsigned(args_[i], 0xFFFF'FFFFu);
            if (!parsed) throw std::runtime_error("invalid digit found in string");
            if (*parsed == 0 || *parsed > 12'000'000) throw std::runtime_error("波特率范围 1–12000000");
            baud = static_cast<uint32_t>(*parsed);
        } else if ((arg.empty() || arg[0] != '-') && !port) {
            port = arg;
        } else {
            throw std::runtime_error(kUsage);
        }
    }
    if (port) {
        std::optional<Device> device;
        for (const Device& candidate : app.devices) {
            if (candidate.path == *port) {
                device = candidate;
                break;
            }
        }
        if (!device) {
            std::error_code error;
            const auto resolved = std::filesystem::canonical(*port, error);
            if (!error) {
                for (const Device& candidate : app.devices) {
                    if (std::filesystem::path(candidate.path) == resolved) {
                        device = candidate;
                        break;
                    }
                }
            }
        }
        if (!device) device = explicit_device(*port);
        app.select(*device, baud);
    } else if (baud) {
        app.profile.settings.baud = *baud;
    }
}
void SerialPage::set_active(bool active) {
    if (active_ == active) return;
    active_ = active;
    if (!app_) return;
    if (active) {
        app_->resume();
    } else {
        app_->suspend();
    }
}
void SerialPage::tick() {
    if (app_) app_->tick();
}
std::optional<tui::TimePoint> SerialPage::next_deadline() const {
    if (!active_ || !app_) return std::nullopt;
    return app_->deadline();
}
void SerialPage::draw(Screen& screen, Rect area) {
    cursor_.reset();
    tab_hits_.clear();
    row_hits_.clear();
    if (area.width <= 2 || area.height <= 1) return;
    if (!error_.empty()) {
        draw_error(screen, area);
        return;
    }
    if (!app_) return;
    App& app = *app_;
    draw_title(screen, area);
    if (area.height >= 4) draw_tabs(screen, area);
    const int footer = area.y + area.height - 1;
    const int hints = footer - 1;
    const Rect body{area.x, area.y + 2, area.width, area.height - 4};
    if (body.height > 0 && body.width > 2) {
        switch (app.page) {
            case 0:
                draw_monitor(screen, body);
                break;
            case 1:
                draw_ports(screen, body);
                break;
            case 2:
                draw_settings(screen, body);
                break;
            case 3:
                draw_commands(screen, body);
                break;
            default:
                draw_flash(screen, body);
                break;
        }
    }
    tui::put_hints(screen, area.x + 1, hints, area.width - 2, page_hints(app.page));
    tui::put(screen, area.x + 1, footer, tui::clip(app.status, area.width - 2), Style{tui::kFg}, area.width - 2);
    if (app.input) {
        draw_input(screen);
    } else if (confirm_flash_) {
        draw_confirm(screen);
    }
    if (app.help) draw_help(screen);
}
void SerialPage::draw_title(Screen& screen, Rect area) {
    const App& app = *app_;
    const std::string state = app.flashing() ? "烧录" : app.connected ? "● 已连接" : app.device ? "○ 已断开" : "○ 待连接";
    std::string full = app.device ? app.device->path : "未选择端口";
    std::string device = full;
    if (area.width < 125) {
        const size_t slash = full.find_last_of('/');
        if (slash != std::string::npos && slash + 1 < full.size()) device = full.substr(slash + 1);
    }
    const Settings& settings = app.profile.settings;
    const char parity = settings.parity.empty() ? 'n' : static_cast<char>(std::toupper(static_cast<unsigned char>(settings.parity[0])));
    const std::string title = "串口 · " + state + " · " + device + " · " + format("%u  %u%c%u", settings.baud, settings.bits, parity, settings.stop) +
                              " · " + format("RX %.1fkB/s  TX %.1fkB/s", app.rate / 1000.0, app.rate_tx / 1000.0);
    tui::put(screen, area.x + 1, area.y, tui::clip(title, area.width - 1), Style{tui::kBrightFg}, area.width - 1);
}
void SerialPage::draw_tabs(Screen& screen, Rect area) {
    const size_t page = app_->page;
    int x = area.x + 1;
    const int y = area.y + 1;
    for (size_t i = 0; i < kPageNames.size(); ++i) {
        const int start = x;
        x = tui::put(screen, x, y, std::to_string(i + 1), Style{tui::kMuted}, std::max(area.x + area.width - x, 0));
        const Style style = i == page ? Style{tui::kBrightFg, {}, true} : Style{tui::kMuted};
        x = tui::put(screen, x + 1, y, kPageNames[i], style, std::max(area.x + area.width - x - 1, 0));
        tab_hits_.emplace_back(Rect{start, y, x - start + 1, 1}, i);
        x += 2;
    }
}
void SerialPage::draw_monitor(Screen& screen, Rect area) {
    const App& app = *app_;
    const int send_rows = area.height >= 6 ? 2 : 0;
    const Rect main{area.x, area.y, area.width, std::max(area.height - send_rows, 0)};
    Rect capture = main;
    std::optional<Rect> plot;
    if (app.graph && main.height >= 12) {
        if (main.width >= 125) {
            const int left = main.width * 67 / 100;
            capture = Rect{main.x, main.y, left, main.height};
            plot = Rect{main.x + left + 1, main.y, main.width - left - 1, main.height};
        } else {
            const int graph_rows = std::min(10, std::max(main.height - 6, 4));
            capture = Rect{main.x, main.y, main.width, main.height - graph_rows};
            plot = Rect{main.x, main.y + main.height - graph_rows, main.width, graph_rows};
        }
    }
    if (capture.height >= 1) draw_capture(screen, capture);
    if (plot && plot->height >= 3) draw_graph(screen, *plot);
    if (send_rows > 0 && main.height + send_rows <= area.height) draw_send(screen, Rect{area.x, area.y + main.height, area.width, send_rows});
}
void SerialPage::draw_capture(Screen& screen, Rect area) {
    App& app = *app_;
    const Capture& view = app.view_capture();
    const size_t total = view.records.size();
    const bool filtering = !trim_text(app.filter).empty();
    size_t matching = total;
    std::vector<const Record*> visible;
    if (filtering) {
        const std::vector<uint64_t>& ids = app.filtered_ids();
        matching = ids.size();
        const uint64_t front = view.records.empty() ? 0 : view.records.front().id;
        for (const uint64_t id : ids) {
            if (id < front) continue;
            const size_t index = static_cast<size_t>(id - front);
            if (index >= view.records.size()) continue;
            const Record& record = view.records[index];
            if (const auto anchor = app.view_anchor(); anchor && record.id > *anchor) continue;
            visible.push_back(&record);
        }
    } else {
        for (const Record& record : view.records) {
            if (const auto anchor = app.view_anchor(); anchor && record.id > *anchor) continue;
            visible.push_back(&record);
        }
    }
    std::string paused = "实时";
    if (const auto anchor = app.view_anchor()) {
        const bool overwritten = !view.records.empty() && view.records.front().id > *anchor;
        paused = "暂停 · 新增 " + std::to_string(view.next > *anchor + 1 ? view.next - (*anchor + 1) : 0) + " 行" + (overwritten ? " · 暂停位置已被淘汰" : "");
    }
    std::string title = std::string(" ") + kModeNames[app.mode] + " · " + paused + " · " + std::to_string(matching) + "/" + std::to_string(total) +
                        " 行 · 淘汰 " + std::to_string(view.evicted) + " · 日志 " + (app.logger ? "ON" : "OFF");
    if (!app.filter.empty()) title += " · 过滤 " + app.filter;
    if (!app.search.empty()) {
        const std::vector<uint64_t>& matches = app.search_matches();
        size_t position = 0;
        if (app.found) {
            for (size_t i = 0; i < matches.size(); ++i) {
                if (matches[i] == *app.found) position = i + 1;
            }
        }
        title += " · 搜索 " + app.search + " · 第 " + std::to_string(position) + "/共 " + std::to_string(matches.size()) + " 个";
    }
    tui::put(screen, area.x + 1, area.y, tui::clip(title, area.width - 2), Style{tui::kMuted}, area.width - 2);
    const int rows = area.height - 1;
    if (rows <= 0) return;
    const size_t end = visible.size() > app.scroll ? visible.size() - app.scroll : 0;
    const size_t start = end > static_cast<size_t>(rows) ? end - static_cast<size_t>(rows) : 0;
    std::vector<const Record*> shown(visible.begin() + static_cast<ptrdiff_t>(start), visible.begin() + static_cast<ptrdiff_t>(end));
    bool preview = false;
    std::string preview_text;
    if (app.mode == 0 && !app.view_anchor() && !app.framer.pending().empty()) {
        const std::string plain_text = plain(decode_bytes(app.profile.encoding, app.framer.pending()));
        if (trim_text(app.filter).empty() || tui::match(app.filter, plain_text)) {
            preview = true;
            preview_text = "  RX · " + plain_text + (app.framer.truncated() ? " [行截断]" : " ▏");
            if (shown.size() >= static_cast<size_t>(rows) && !shown.empty()) shown.erase(shown.begin());
        }
    }
    int y = area.y + 1;
    if (shown.empty() && !preview) {
        tui::put(screen, area.x + 2, y, tui::clip(app.filter.empty() ? "等待数据 · i 发送命令 · 2 选择串口" : "没有匹配 · Esc 清除过滤", area.width - 3),
                 Style{tui::kMuted}, area.width - 3);
        return;
    }
    for (const Record* record : shown) {
        if (y >= area.y + 1 + rows) break;
        draw_record(screen, Rect{area.x, y++, area.width, 1}, *record);
    }
    if (preview && y < area.y + 1 + rows) {
        tui::put(screen, area.x + 2, y, tui::clip(preview_text, area.width - 3), Style{tui::kMuted}, area.width - 3);
    }
}
void SerialPage::draw_record(Screen& screen, Rect row, const Record& record) {
    const App& app = *app_;
    const bool found = app.found && *app.found == record.id;
    const bool is_match = !app.search.empty() && tui::match(app.search, record.plain).has_value();
    const bool warned = std::any_of(app.store.config.highlights.begin(), app.store.config.highlights.end(), [&](const std::string& needle) {
        if (needle.empty()) return false;
        std::string upper = record.plain;
        for (char& c : upper) c = static_cast<char>(c >= 'a' && c <= 'z' ? c - 32 : c);
        std::string target;
        for (const char c : needle) target += static_cast<char>(c >= 'a' && c <= 'z' ? c - 32 : c);
        return upper.find(target) != std::string::npos;
    });
    const uint32_t warn_color = record.plain.find("WARN") != std::string::npos ? tui::kYellow : tui::kRed;
    if (found || is_match) tui::fill(screen, row, tui::kSelection);
    std::string clock;
    if (app.timestamp == 0) {
        clock = record.clock;
    } else if (app.timestamp == 1) {
        clock = format("+%9.3f", record.elapsed);
    }
    const std::string prefix = clock + " " + padded_kind(record.kind) + " │ ";
    const int interior = std::max(row.width - 2, 1);
    const int prefix_width = tui::width_of(prefix);
    const int remaining = std::max(interior - prefix_width, 0);
    uint32_t base = tui::kFg;
    if (record.kind == "TX") base = tui::kGreen;
    else if (record.kind == "错误") base = tui::kRed;
    else if (record.kind == "断开") base = tui::kYellow;
    if (found) base = tui::kBlue;
    const std::optional<uint32_t> background = (found || is_match) ? std::optional<uint32_t>(tui::kSelection) : std::nullopt;
    tui::put(screen, row.x + 2, row.y, tui::clip(prefix, interior), Style{tui::kMuted, background, false, warned}, interior);
    if (remaining <= 0) return;
    std::string body;
    if (record.kind == "RX" && app.mode == 1) {
        body = hex_text(record.raw, static_cast<size_t>(remaining / 3));
    } else if (record.kind == "RX" && app.mode == 2) {
        body = mix_text(record.raw);
    } else {
        body = record.text;
    }
    const std::string query = !app.search.empty() ? app.search : app.filter;
    const int body_x = row.x + 2 + std::min(prefix_width, interior);
    if (!query.empty()) {
        // Rust highlights the plain form of the currently displayed body, so HEX/MIX rows keep
        // their hex layout while a search is active.
        const std::string plain_body = tui::clip(plain(body), remaining);
        std::vector<std::pair<size_t, size_t>> ranges;
        if (const auto hit = tui::match(query, plain_body)) ranges = hit->ranges;
        tui::put_ranges(screen, body_x, row.y, plain_body, ranges, Style{base, background, false, warned}, remaining);
    } else if (record.kind == "RX" && app.mode == 0) {
        int used = 0;
        for (const AnsiSpan& span : ansi_line(body)) {
            if (used >= remaining) break;
            const std::string clipped = tui::clip(span.text, remaining - used);
            if (clipped.empty()) continue;
            const int width = tui::width_of(clipped);
            uint32_t fg = span.style.fg.value_or(warned ? warn_color : base);
            std::optional<uint32_t> bg = span.style.bg ? span.style.bg : background;
            if (span.style.reversed) {
                const uint32_t old = fg;
                fg = bg.value_or(tui::kBg);
                bg = old;
            }
            tui::put(screen, body_x + used, row.y, clipped, Style{fg, bg, span.style.underline, span.style.bold || warned}, remaining - used);
            used += width;
        }
    } else {
        // HEX and MIX already built their body from the raw bytes; plain() also strips ANSI
        // from TX, error and connection messages.
        const std::string plain_body = tui::clip(plain(body), remaining);
        tui::put(screen, body_x, row.y, plain_body, Style{warned ? warn_color : base, background, false, warned}, remaining);
    }
}
void SerialPage::draw_send(Screen& screen, Rect area) {
    const App& app = *app_;
    if (area.height < 1) return;
    tui::put(screen, area.x + 1, area.y, " 发送 · x 模式 · e 行尾 · t 重复", Style{tui::kMuted}, area.width - 2);
    if (area.height < 2) return;
    int x = tui::put(screen, area.x + 2, area.y + 1, "▏i / Enter 输入 ", Style{tui::kBlue}, area.width - 3);
    const std::string repeat = app.repeat ? format(" · 每 %lldms", static_cast<long long>(app.repeat->every.count())) : "";
    x = tui::put(screen, x, area.y + 1, " " + std::string(app.tx_hex ? "HEX" : "TEXT") + " · 行尾 " + app.profile.ending + " · " + encoding_name(app.profile.encoding) + repeat,
                  Style{tui::kFg}, std::max(area.x + area.width - x - 1, 0));
    tui::put(screen, x, area.y + 1, format(" · RX %llu B / TX %llu B", static_cast<unsigned long long>(app.rx_total), static_cast<unsigned long long>(app.tx_total)),
             Style{tui::kMuted}, std::max(area.x + area.width - x - 2, 0));
}
void SerialPage::draw_ports(Screen& screen, Rect area) {
    const App& app = *app_;
    if (area.height < 1) return;
    tui::put(screen, area.x + 1, area.y, tui::clip(" 端口 · 自动发现 · 每 750ms 刷新 · Enter 连接 · u 断开 · " + std::to_string(app.devices.size()) + " 个", area.width - 2),
             Style{tui::kMuted}, area.width - 2);
    if (app.devices.empty()) {
        draw_empty(screen, Rect{area.x, area.y + 1, area.width, area.height - 1},
                   {"", "未发现 ttyACM / ttyUSB 设备", "", "插入开发板或 USB 转串口，列表每 750ms 自动刷新。",
                    "也可：mayon-tools serial /dev/serial/by-id/… -b 115200", "", "相同 VID:PID + 序列号 + 接口自动重连；无序列号按物理 USB 位置。",
                    "当前未打开任何设备。按 Enter 选择后才会连接。"},
                   area.width - 2);
        return;
    }
    if (area.height < 3) return;
    const auto columns = port_columns(area.width);
    tui::draw_table_header(screen, Rect{area.x, area.y + 1, area.width, 1}, columns);
    const int rows = area.height - 2;
    port_offset_ = tui::scroll_to(app.selected, port_offset_, static_cast<size_t>(rows), app.devices.size());
    for (int i = 0; i < rows && port_offset_ + static_cast<size_t>(i) < app.devices.size(); ++i) {
        const size_t index = port_offset_ + static_cast<size_t>(i);
        const Device& device = app.devices[index];
        const Rect line{area.x, area.y + 2 + i, area.width, 1};
        const std::vector<std::string> cells{device.path, format("%04x:%04x", device.vid, device.pid), device.product,
                                             device.serial && !device.serial->empty() ? *device.serial : "无 · USB位置匹配"};
        tui::draw_table_row(screen, line, columns, cells, index == app.selected);
        row_hits_.emplace_back(line, index);
    }
}
void SerialPage::draw_settings(Screen& screen, Rect area) {
    const App& app = *app_;
    if (area.height < 1) return;
    const Settings& s = app.profile.settings;
    tui::put(screen, area.x + 1, area.y, " 参数 · Enter 修改 · 按设备自动保存", Style{tui::kMuted}, area.width - 2);
    const auto columns = setting_columns(area.width);
    if (area.height >= 3) {
        tui::draw_table_header(screen, Rect{area.x, area.y + 1, area.width, 1}, columns);
        const std::vector<std::vector<std::string>> rows{
            {"波特率", std::to_string(s.baud), "b 常用 / B 自定义"},
            {"数据位", std::to_string(s.bits), "Enter 循环 5–8"},
            {"校验", s.parity, "Enter none/even/odd"},
            {"停止位", std::to_string(s.stop), "Enter 1/2"},
            {"流控", s.flow, "Enter none/hardware/software"},
            {"DTR", s.dtr ? "true" : "false", "d 切换 / D 100ms脉冲"},
            {"RTS", s.rts ? "true" : "false", "r 切换 / R 100ms脉冲"},
            {"编码", encoding_name(app.profile.encoding), "g UTF-8 / GBK"},
        };
        const int available = area.height - 2;
        for (size_t i = 0; i < rows.size() && static_cast<int>(i) < available; ++i) {
            tui::draw_table_row(screen, Rect{area.x, area.y + 2 + static_cast<int>(i), area.width, 1}, columns, rows[i], i == app.settings_index);
        }
    }
    const std::vector<std::string> info{
        " 常用波特率：9600 · 19200 · 38400 · 57600 · 115200 · 230400",
        "             460800 · 921600 · 1000000 · 2000000",
        "",
        " 行尾 " + app.profile.ending + " · e 切换 CR / LF / CRLF / 无",
        " 配置：" + app.store.config_path.string(),
        "",
        " DTR/RTS 的电平与复位极性取决于接线；不支持的驱动会报告错误。",
    };
    int y = area.y + 10;
    for (const std::string& line : info) {
        if (y >= area.y + area.height) break;
        tui::put(screen, area.x + 1, y++, tui::clip(line, area.width - 2), Style{tui::kMuted}, area.width - 2);
    }
}
void SerialPage::draw_commands(Screen& screen, Rect area) {
    const App& app = *app_;
    if (area.height < 2) return;
    const int needed = 2 + static_cast<int>(app.store.config.favorites.size());
    const int top_height = std::clamp(needed, 3, std::max(area.height - 4, 3));
    const Rect top{area.x, area.y, area.width, top_height};
    const Rect bottom{area.x, area.y + top_height, area.width, area.height - top_height};
    tui::put(screen, top.x + 1, top.y, " 收藏 · a 添加 名称=命令 · Enter 载入（不立即发送）", Style{tui::kMuted}, top.width - 2);
    const auto columns = favorite_columns(top.width);
    const auto& favorites = app.store.config.favorites;
    int rows = top.height - 2;
    if (rows > 0 && !favorites.empty()) {
        tui::draw_table_header(screen, Rect{top.x, top.y + 1, top.width, 1}, columns);
        favorite_offset_ = tui::scroll_to(app.favorite_index, favorite_offset_, static_cast<size_t>(rows), favorites.size());
        for (int i = 0; i < rows && favorite_offset_ + static_cast<size_t>(i) < favorites.size(); ++i) {
            const size_t index = favorite_offset_ + static_cast<size_t>(i);
            const Rect line{top.x, top.y + 2 + i, top.width, 1};
            tui::draw_table_row(screen, line, columns, {favorites[index].name, favorites[index].hex ? "HEX" : "TEXT", favorites[index].value},
                                index == app.favorite_index);
            row_hits_.emplace_back(line, index);
        }
    } else if (rows > 0) {
        draw_empty(screen, Rect{top.x, top.y + 1, top.width, rows}, {" 还没有收藏。按 a 添加：名称=命令"}, top.width - 2);
    }
    if (bottom.height >= 1) {
        tui::put(screen, bottom.x + 1, bottom.y, " 历史 · i 输入 · ↑↓ 调用 · F 发送文件 · t 定时", Style{tui::kMuted}, bottom.width - 2);
        int y = bottom.y + 1;
        const int room = bottom.height - 1;
        for (auto it = app.store.history.rbegin(); it != app.store.history.rend() && y < bottom.y + 1 + room; ++it) {
            tui::put(screen, bottom.x + 1, y++, tui::clip(" " + *it, bottom.width - 2), Style{tui::kMuted}, bottom.width - 2);
        }
    }
}
void SerialPage::draw_flash(Screen& screen, Rect area) {
    const App& app = *app_;
    if (area.height < 1) return;
    const auto detected = detected_flash();
    std::string detected_text;
    for (const std::string& name : detected) detected_text += (detected_text.empty() ? "" : " / ") + name;
    const int info_height = std::min(7, area.height);
    tui::put(screen, area.x + 1, area.y, " 烧录联动 · 先确认端口关闭 → 运行命令 → 保留输出 → 按设备身份重连", Style{tui::kMuted}, area.width - 2);
    int y = area.y + 1;
    const auto line = [&](const std::string& text, const Style& style) {
        if (y < area.y + info_height) tui::put(screen, area.x + 1, y++, tui::clip(text, area.width - 2), style, area.width - 2);
    };
    line(" 检测到：" + std::string(detected_text.empty() ? "未发现烧录工具" : detected_text), Style{tui::kMuted});
    line(" 命令：" + std::string(app.profile.flash.empty() ? "尚未配置 · o 编辑（不自动推断芯片型号）" : app.profile.flash), Style{tui::kFg});
    line(" 目录：" + std::string(app.profile.flash_dir.empty() ? "当前启动目录" : app.profile.flash_dir), Style{tui::kFg});
    line("", Style{tui::kFg});
    line(" o 编辑命令   O 工作目录   F5 执行   X 执行（y 确认）   Esc 取消", Style{tui::kBlue});
    if (area.height <= info_height) return;
    const Rect out{area.x, area.y + info_height, area.width, area.height - info_height};
    const bool running = app.flashing() || app.flash_waiting();
    tui::put(screen, out.x + 1, out.y, running ? " 执行中 · Esc 取消" : " 烧录输出", Style{running ? tui::kYellow : tui::kMuted}, out.width - 2);
    const int room = out.height - 1;
    const int skip = std::max(0, static_cast<int>(app.flash_lines.size()) - room);
    int row = out.y + 1;
    for (size_t i = static_cast<size_t>(skip); i < app.flash_lines.size() && row < out.y + 1 + room; ++i, ++row) {
        tui::put(screen, out.x + 2, row, tui::clip(app.flash_lines[i], out.width - 3), Style{tui::kFg}, out.width - 3);
    }
}
void SerialPage::draw_graph(Screen& screen, Rect area) {
    const App& app = *app_;
    tui::put(screen, area.x + 1, area.y, tui::clip(" 波形 · 最近1024点/通道 · w 收起", area.width - 2), Style{tui::kMuted}, area.width - 2);
    if (app.series.empty()) {
        draw_empty(screen, Rect{area.x + 1, area.y + 1, area.width - 1, area.height - 1}, {"", " 等待数值行…", "", " a=1.2,b=3", " 或 1.2,3,4"}, area.width - 3);
        return;
    }
    const int label_right = area.x + area.width - 2;
    std::vector<std::tuple<std::string, double, size_t>> legend;
    size_t series_number = 0;
    for (const auto& [name, values] : app.series) legend.emplace_back(name, values.empty() ? 0.0 : values.back().second, series_number++);
    int legend_x = label_right;
    for (auto it = legend.rbegin(); it != legend.rend(); ++it) {
        const std::string text = " " + std::get<0>(*it) + " " + format("%.3f", std::get<1>(*it)) + " ";
        const int width = tui::width_of(text);
        if (legend_x - width < area.x + 1) break;
        legend_x -= width;
        tui::put(screen, legend_x, area.y, text, Style{kSeriesColors[std::get<2>(*it) % kSeriesColors.size()]}, width);
    }
    const int top = area.y + 1;
    const int bottom = area.y + area.height - 2;
    if (bottom - top < 2 || area.width < 24) {
        if (bottom >= top) draw_empty(screen, Rect{area.x + 1, top, area.width - 1, bottom - top + 1}, {" 空间不足，w 收起波形", "", " 或用更高的窗口"}, area.width - 3);
        return;
    }
    double low = std::numeric_limits<double>::infinity();
    double high = -std::numeric_limits<double>::infinity();
    double x_end = 1.0;
    double x_start = x_end;
    for (const auto& [name, values] : app.series) {
        for (const auto& point : values) {
            low = std::min(low, point.second);
            high = std::max(high, point.second);
        }
        if (!values.empty()) x_end = std::max(x_end, values.back().first);
    }
    x_start = x_end;
    for (const auto& [name, values] : app.series) {
        if (!values.empty()) x_start = std::min(x_start, values.front().first);
    }
    x_start = std::min(x_start, x_end - 1.0);
    if (!std::isfinite(low) || !std::isfinite(high)) return;
    const double pad = std::max((high - low) * 0.1, 0.1);
    const double y_low = low - pad;
    const double y_high = high + pad;
    const int plot_left = area.x + 9;
    const int plot_right = area.x + area.width - 2;
    const int columns = plot_right - plot_left + 1;
    const int rows = bottom - top + 1;
    if (columns < 2 || rows < 1) return;
    const int dots_w = columns * 2;
    const int dots_h = rows * 4;
    std::vector<uint8_t> bits(static_cast<size_t>(columns) * static_cast<size_t>(rows), 0);
    std::vector<uint8_t> color_of(bits.size(), 0);
    const auto dot_bit = [](int x, int y) -> uint8_t {
        static constexpr uint8_t kBits[4][2]{{0x01, 0x08}, {0x02, 0x10}, {0x04, 0x20}, {0x40, 0x80}};
        return kBits[y & 3][x & 1];
    };
    const double span_x = std::max(x_end - x_start, 0.000001);
    const double span_y = std::max(y_high - y_low, 0.000001);
    const auto dot_x = [&](double x) { return std::clamp(static_cast<int>(std::lround((x - x_start) / span_x * (dots_w - 1))), 0, dots_w - 1); };
    const auto dot_y = [&](double y) { return std::clamp(static_cast<int>(std::lround((y_high - y) / span_y * (dots_h - 1))), 0, dots_h - 1); };
    const auto set_dot = [&](int dx, int dy, uint8_t color) {
        const size_t cell = static_cast<size_t>(dy / 4) * static_cast<size_t>(columns) + static_cast<size_t>(dx / 2);
        bits[cell] = static_cast<uint8_t>(bits[cell] | dot_bit(dx % 2, dy % 4));
        color_of[cell] = color;
    };
    size_t series_index = 0;
    for (const auto& [name, values] : app.series) {
        const uint8_t color = static_cast<uint8_t>(series_index++ % kSeriesColors.size());
        std::optional<std::pair<int, int>> last;
        for (const auto& point : values) {
            const int x = dot_x(point.first);
            const int y = dot_y(point.second);
            if (last) {
                const int steps = std::max(std::abs(x - last->first), std::abs(y - last->second));
                for (int i = 1; i <= steps; ++i) {
                    const double t = static_cast<double>(i) / steps;
                    set_dot(static_cast<int>(std::lround(last->first + (x - last->first) * t)), static_cast<int>(std::lround(last->second + (y - last->second) * t)),
                            color);
                }
            } else {
                set_dot(x, y, color);
            }
            last = std::pair<int, int>{x, y};
        }
    }
    for (int r = 0; r < rows; ++r) {
        for (int c = 0; c < columns; ++c) {
            const size_t cell = static_cast<size_t>(r) * static_cast<size_t>(columns) + static_cast<size_t>(c);
            if (bits[cell] == 0) continue;
            std::string glyph;
            tui::append(glyph, static_cast<char32_t>(0x2800 + bits[cell]));
            tui::put(screen, plot_left + c, top + r, glyph, Style{kSeriesColors[color_of[cell] % kSeriesColors.size()]});
        }
    }
    // Axis labels: two y values on the left and the seconds range underneath.
    tui::put_right(screen, plot_left - 2, top, format("%.1f", high), Style{tui::kMuted});
    tui::put_right(screen, plot_left - 2, bottom, format("%.1f", low), Style{tui::kMuted});
    if (area.height >= 3) {
        tui::put(screen, plot_left, bottom + 1, format("%.0f", x_start), Style{tui::kMuted}, columns / 2);
        tui::put_right(screen, plot_right, bottom + 1, format("%.0f 秒", x_end), Style{tui::kMuted});
    }
}
void SerialPage::draw_input(Screen& screen) { cursor_ = tui::draw_input(screen, input_label(*app_), app_->input->text); }
void SerialPage::draw_confirm(Screen& screen) {
    const App& app = *app_;
    const std::string message = "命令：" + (app.profile.flash.empty() ? "（未配置）" : app.profile.flash) + "\n目录：" +
                                (app.profile.flash_dir.empty() ? "当前启动目录" : app.profile.flash_dir) + "\n串口会先关闭再执行，结束后按设备身份重连。";
    tui::draw_confirm(screen, "确认烧录 · X 触发 · y 执行", message, "y");
}
void SerialPage::draw_help(Screen& screen) {
    std::vector<std::string> lines;
    for (const std::string& line : split_lines(kHelp)) lines.push_back(line);
    lines.push_back("配置：" + app_->store.config_path.string());
    tui::draw_help(screen, "帮助 · ? / Esc 关闭", lines);
}
void SerialPage::draw_error(Screen& screen, Rect area) {
    tui::put(screen, area.x + 1, area.y, "串口", Style{tui::kBrightFg}, area.width - 2);
    int y = area.y + 2;
    for (const std::string& line : tui::wrap(error_, area.width - 2, 6)) {
        if (y >= area.y + area.height - 1) break;
        tui::put(screen, area.x + 1, y++, line, Style{tui::kRed}, area.width - 2);
    }
    tui::put_hints(screen, area.x + 1, area.y + area.height - 1, area.width - 2, {{"R", "重试"}, {"q/Esc", "关闭"}});
}
bool SerialPage::handle(const InputEvent& event) {
    if (!error_.empty()) {
        if (event.type != InputEvent::Type::Key) return false;
        if (event.key.ctrl && event.key.ch == U'c') return true;
        if (event.key.is(U'R')) {
            load();
            return false;
        }
        return event.key.is(U'q') || event.key.code == KeyCode::Escape;
    }
    if (!app_) return false;
    switch (event.type) {
        case InputEvent::Type::Key:
            return key(event.key);
        case InputEvent::Type::Paste:
            if (!app_->help && !confirm_flash_) paste(event.paste);
            return false;
        case InputEvent::Type::MouseClick:
        case InputEvent::Type::WheelUp:
        case InputEvent::Type::WheelDown:
            if (!app_->help && !confirm_flash_) {
                if (event.type == InputEvent::Type::MouseClick) click(event.x, event.y);
                else wheel(event.type == InputEvent::Type::WheelUp ? -1 : 1);
            }
            return false;
        case InputEvent::Type::FocusIn:
        case InputEvent::Type::FocusOut:
            return false;
    }
    return false;
}
bool SerialPage::key(const Key& k) {
    if (k.ctrl && k.ch == U'c') return true;
    App& app = *app_;
    if (confirm_flash_) {
        if (k.is(U'y')) {
            confirm_flash_ = false;
            app.request_flash();
        } else if (k.code == KeyCode::Escape || k.is(U'n')) {
            confirm_flash_ = false;
        }
        return false;
    }
    if (app.help) {
        if (k.code == KeyCode::Escape || k.is(U'?')) app.help = false;
        return false;
    }
    if (app.input) {
        Input input = std::move(*app.input);
        app.input.reset();
        if (k.code == KeyCode::Escape) {
            if (input.kind == InputKind::Filter) app.filter = input.before;
            if (input.kind == InputKind::Search) app.search = input.before;
            return false;
        }
        if (k.code == KeyCode::Enter) {
            if (auto done = app.submit(input.kind, input.text.str()); !done) {
                app.status = done.error();
                app.input = std::move(input);
            }
            return false;
        }
        const auto update_live = [&] {
            if (input.kind == InputKind::Filter) app.filter = input.text.str();
            if (input.kind == InputKind::Search) {
                app.search = input.text.str();
                app.found.reset();
            }
        };
        if (k.code == KeyCode::Up && input.kind == InputKind::Send) {
            app.history_index = app.history_index > 0 ? app.history_index - 1 : 0;
            if (app.history_index < app.store.history.size()) input.text.set(app.store.history[app.history_index]);
        } else if (k.code == KeyCode::Down && input.kind == InputKind::Send) {
            app.history_index = std::min(app.history_index + 1, app.store.history.size());
            input.text.set(app.history_index < app.store.history.size() ? app.store.history[app.history_index] : "");
        } else if (k.code == KeyCode::Up && (input.kind == InputKind::Filter || input.kind == InputKind::Search)) {
            if (app.page == 0) app.scroll_up(1);
            else move_selection(-1);
        } else if (k.code == KeyCode::Down && (input.kind == InputKind::Filter || input.kind == InputKind::Search)) {
            if (app.page == 0) app.scroll = app.scroll > 0 ? app.scroll - 1 : 0;
            else move_selection(1);
        } else if (input.text.handle(k)) {
            update_live();
        }
        app.input = std::move(input);
        return false;
    }
    if (k.code == KeyCode::Escape) {
        if (!app.filter.empty()) {
            app.filter.clear();
        } else if (!app.search.empty()) {
            app.search.clear();
            app.found.reset();
        } else {
            app.cancel_flash();
        }
        return false;
    }
    if (k.ctrl && k.ch == U'f') {
        app.open(InputKind::Search, app.search);
        return false;
    }
    if (k.ctrl || k.alt) return false;
    switch (k.code) {
        case KeyCode::Up:
            move_selection(-1);
            return false;
        case KeyCode::Down:
            move_selection(1);
            return false;
        case KeyCode::PageUp:
            if (app.page != 0) move_selection(-20);
            else app.scroll_up(20);
            return false;
        case KeyCode::PageDown:
            if (app.page != 0) move_selection(20);
            else app.scroll = app.scroll > 20 ? app.scroll - 20 : 0;
            return false;
        case KeyCode::Home:
            if (app.page != 0) move_selection(-1'000'000);
            return false;
        case KeyCode::End:
            if (app.page != 0) {
                move_selection(1'000'000);
            } else {
                app.anchor.reset();
                app.wire_anchor.reset();
                app.scroll = 0;
            }
            return false;
        case KeyCode::Enter:
            if (app.page == 1) {
                if (app.selected < app.devices.size()) app.select(app.devices[app.selected], std::nullopt);
            } else if (app.page == 2) {
                edit_setting();
            } else if (app.page == 3) {
                if (app.favorite_index < app.store.config.favorites.size()) {
                    const Favorite& favorite = app.store.config.favorites[app.favorite_index];
                    app.tx_hex = favorite.hex;
                    app.open(InputKind::Send, favorite.value);
                }
            } else {
                app.open(InputKind::Send, "");
            }
            return false;
        case KeyCode::F5:
            app.request_flash();
            return false;
        case KeyCode::Char:
            break;
        default:
            return false;
    }
    switch (k.ch) {
        case U'q':
            return true;
        case U'?':
            app.help = true;
            return false;
        case U'1':
        case U'2':
        case U'3':
        case U'4':
        case U'5':
            app.page = static_cast<size_t>(k.ch - U'1');
            return false;
        case U'k':
            move_selection(-1);
            return false;
        case U'j':
            move_selection(1);
            return false;
        case U'i':
            app.open(InputKind::Send, "");
            return false;
        case U'/':
        case U'f':
            app.open(InputKind::Filter, app.filter);
            return false;
        case U'n':
            app.search_next();
            return false;
        case U'N':
            app.search_previous();
            return false;
        case U'p':
        case U' ':
            app.pause();
            return false;
        case U'v':
            app.mode = (app.mode + 1) % 3;
            app.anchor.reset();
            app.wire_anchor.reset();
            app.scroll = 0;
            app.found.reset();
            return false;
        case U'T':
            app.timestamp = (app.timestamp + 1) % 3;
            return false;
        case U'w':
            app.graph = !app.graph;
            return false;
        case U'g':
            if (app.page != 0) move_selection(-1'000'000);
            else app.toggle_encoding();
            return false;
        case U'G':
            if (app.page != 0) move_selection(1'000'000);
            else {
                app.anchor.reset();
                app.wire_anchor.reset();
                app.scroll = 0;
            }
            return false;
        case U'x':
            app.tx_hex = !app.tx_hex;
            return false;
        case U'e':
            app.profile.ending = app.profile.ending == "CRLF" ? "LF" : app.profile.ending == "LF" ? "CR" : app.profile.ending == "CR" ? "无" : "CRLF";
            app.persist();
            return false;
        case U'l':
            app.logging();
            return false;
        case U'c':
            app.csv = !app.csv;
            app.status = std::string("CSV ") + (app.csv ? "开启" : "关闭") + "，下次开启日志生效";
            return false;
        case U'b': {
            size_t current = 3;
            for (size_t i = 0; i < kCommonBauds.size(); ++i) {
                if (kCommonBauds[i] == app.profile.settings.baud) current = i;
            }
            app.profile.settings.baud = kCommonBauds[(current + 1) % kCommonBauds.size()];
            app.apply();
            return false;
        }
        case U'B':
            app.open(InputKind::Baud, std::to_string(app.profile.settings.baud));
            return false;
        case U's': {
            const Settings& s = app.profile.settings;
            app.open(InputKind::Settings, format("baud=%u bits=%u parity=%s stop=%u flow=%s", s.baud, s.bits, s.parity.c_str(), s.stop, s.flow.c_str()));
            return false;
        }
        case U'h':
            app.open(InputKind::Highlights, [&] {
                std::string joined;
                for (const std::string& word : app.store.config.highlights) joined += (joined.empty() ? "" : ",") + word;
                return joined;
            }());
            return false;
        case U'd':
            app.profile.settings.dtr = !app.profile.settings.dtr;
            lines();
            return false;
        case U'r':
            app.profile.settings.rts = !app.profile.settings.rts;
            lines();
            return false;
        case U'D':
            app.command(Command::pulse(true, 100));
            return false;
        case U'R':
            app.command(Command::pulse(false, 100));
            return false;
        case U'u':
            if (!app.flashing()) {
                app.repeat.reset();
                app.command(Command::disconnect());
            }
            return false;
        case U'a':
            app.open(InputKind::Favorite, "");
            return false;
        case U'F':
            app.open(InputKind::File, "");
            return false;
        case U't':
            app.open(InputKind::Timer, app.repeat ? std::to_string(app.repeat->every.count()) : "1000");
            return false;
        case U'o':
            app.open(InputKind::FlashCommand, app.profile.flash);
            return false;
        case U'O':
            app.open(InputKind::FlashDir, app.profile.flash_dir);
            return false;
        case U'X':
            if (app.flashing() || app.flash_waiting() || !app.device || trim_text(app.profile.flash).empty()) {
                app.request_flash();
            } else {
                confirm_flash_ = true;
            }
            return false;
        default:
            return false;
    }
}
void SerialPage::paste(const std::string& text) {
    App& app = *app_;
    if (!app.input) return;
    const std::string before = app.input->text.str();
    app.input->text.paste(text);
    if (app.input->text.str() == before) return;
    if (app.input->kind == InputKind::Filter) app.filter = app.input->text.str();
    if (app.input->kind == InputKind::Search) {
        app.search = app.input->text.str();
        app.found.reset();
    }
}
void SerialPage::click(int x, int y) {
    App& app = *app_;
    for (const auto& [rect, index] : tab_hits_) {
        if (rect.contains(x, y)) {
            app.page = index;
            return;
        }
    }
    for (const auto& [rect, index] : row_hits_) {
        if (!rect.contains(x, y)) continue;
        if (app.page == 1) app.selected = index;
        if (app.page == 3) app.favorite_index = index;
        return;
    }
}
void SerialPage::wheel(int delta) {
    if (!app_) return;
    App& app = *app_;
    if (app.page == 0) {
        if (delta < 0) {
            app.scroll_up(3);
        } else {
            app.scroll = app.scroll > 3 ? app.scroll - 3 : 0;
        }
        return;
    }
    move_selection(delta);
}
void SerialPage::move_selection(int delta) {
    App& app = *app_;
    size_t* index = nullptr;
    size_t length = 0;
    if (app.page == 1) {
        index = &app.selected;
        length = app.devices.size();
    } else if (app.page == 2) {
        index = &app.settings_index;
        length = 8;
    } else if (app.page == 3) {
        index = &app.favorite_index;
        length = app.store.config.favorites.size();
    } else {
        return;
    }
    if (delta < 0) {
        const size_t step = static_cast<size_t>(-static_cast<long long>(delta));
        *index = *index > step ? *index - step : 0;
    } else {
        *index = std::min(*index + static_cast<size_t>(delta), length > 0 ? length - 1 : 0);
    }
    *index = std::min(*index, length > 0 ? length - 1 : 0);
}
void SerialPage::edit_setting() {
    App& app = *app_;
    switch (app.settings_index) {
        case 0:
            app.open(InputKind::Baud, std::to_string(app.profile.settings.baud));
            break;
        case 1:
            app.profile.settings.bits = app.profile.settings.bits == 8 ? 5 : app.profile.settings.bits + 1;
            app.apply();
            break;
        case 2:
            app.profile.settings.parity =
                app.profile.settings.parity == "none" ? "even" : app.profile.settings.parity == "even" ? "odd" : "none";
            app.apply();
            break;
        case 3:
            app.profile.settings.stop = app.profile.settings.stop == 1 ? 2 : 1;
            app.apply();
            break;
        case 4:
            app.profile.settings.flow =
                app.profile.settings.flow == "none" ? "hardware" : app.profile.settings.flow == "hardware" ? "software" : "none";
            app.apply();
            break;
        case 5:
            app.profile.settings.dtr = !app.profile.settings.dtr;
            lines();
            break;
        case 6:
            app.profile.settings.rts = !app.profile.settings.rts;
            lines();
            break;
        default:
            app.toggle_encoding();
            break;
    }
}
void SerialPage::lines() {
    App& app = *app_;
    app.command(Command::lines(app.profile.settings.dtr, app.profile.settings.rts));
    app.persist();
}

namespace {
// Mirrors Rust's u32 FromStr error messages, which the CLI prints verbatim.
std::expected<uint32_t, std::string> parse_u32(const std::string& text) {
    if (text.empty()) return std::unexpected("cannot parse integer from empty string");
    if (text.size() == 1 && (text[0] == '+' || text[0] == '-')) return std::unexpected("invalid digit found in string");
    size_t at = text[0] == '+' ? 1 : 0;
    uint64_t value = 0;
    for (; at < text.size(); ++at) {
        const char c = text[at];
        if (c < '0' || c > '9') return std::unexpected("invalid digit found in string");
        value = value * 10 + static_cast<uint64_t>(c - '0');
        if (value > 0xFFFF'FFFFu) return std::unexpected("number too large to fit in target type");
    }
    return static_cast<uint32_t>(value);
}
std::expected<void, std::string> validate_args(const std::vector<std::string>& args) {
    bool port = false;
    for (size_t i = 0; i < args.size(); ++i) {
        if (args[i] == "-b" || args[i] == "--baud") {
            if (++i >= args.size()) return std::unexpected("-b 缺少波特率");
            const auto number = parse_u32(args[i]);
            if (!number) return std::unexpected(number.error());
            if (*number == 0 || *number > 12'000'000) return std::unexpected("波特率范围 1–12000000");
        } else if ((args[i].empty() || args[i][0] != '-') && !port) {
            port = true;
        } else {
            return std::unexpected("无效串口参数");
        }
    }
    return {};
}
std::string hex4(uint16_t value) { return format("%04x", value); }
int run_cli(const std::vector<std::string>& args, std::ostream& out, std::ostream& err) {
    if (!args.empty() && (args[0] == "--help" || args[0] == "-h")) {
        out << "mayon-tools serial [<端口> [-b 波特率]]\nmayon-tools serial list\n配置和日志仍在 serial-mayon 的原目录。\n";
        return 0;
    }
    if (!args.empty() && args[0] == "list") {
        if (args.size() != 1) {
            err << "Error: list 不接受额外参数\n";
            return 1;
        }
        out << "端口\tVID:PID\t产品\t序列号\t接口\n";
        for (const Device& device : discover()) out << format_device_row(device) << '\n';
        return 0;
    }
    if (auto valid = validate_args(args); !valid) {
        err << "Error: " << valid.error() << '\n';
        return 1;
    }
    return -1;
}
}  // namespace
}  // namespace serial

namespace serial {
std::string format_device_row(const Device& device) {
    return device.path + '\t' + hex4(device.vid) + ':' + hex4(device.pid) + '\t' + device.product + '\t' + (device.serial ? *device.serial : "无") + '\t' +
           device.interface;
}
}  // namespace serial

std::unique_ptr<tui::Page> make_serial_page() { return std::make_unique<serial::SerialPage>(); }
std::unique_ptr<tui::Page> make_serial_page(const std::vector<std::string>& args) { return std::make_unique<serial::SerialPage>(args); }
int serial_cli(int argc, char** argv) {
    std::vector<std::string> args;
    for (int i = 1; i < argc; ++i) args.emplace_back(argv[i]);
    return serial::run_cli(args, std::cout, std::cerr);
}
