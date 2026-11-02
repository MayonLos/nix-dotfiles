// Rendering for the Clash TUI. Pure drawing onto an FTXUI screen: the page state
// stays in App, and this file only records click geometry.
#include "app.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <ftxui/screen/screen.hpp>
#include <sstream>
#include <string>
#include <vector>

#include "ui/draw.hpp"
#include "ui/text.hpp"
#include "ui/widgets.hpp"

namespace clash {
namespace {
using ftxui::Screen;
using tui::Rect;
using tui::Style;

struct Span {
    std::string text;
    uint32_t fg = tui::kFg;
    bool bold = false;
};
using Line = std::vector<Span>;
Span span(std::string text, uint32_t fg = tui::kFg, bool bold = false) { return Span{std::move(text), fg, bold}; }
Span muted(std::string text) { return Span{std::move(text), tui::kMuted, false}; }
Line line(std::initializer_list<Span> parts) { return Line(parts); }

std::string repeat(std::string_view text, size_t count) {
    std::string out;
    out.reserve(text.size() * count);
    for (size_t i = 0; i < count; ++i) out += text;
    return out;
}
std::string filter_suffix(const App& app) {
    if (app.filter_text().empty() && !app.filtering) return {};
    return " · /" + app.filter_text();
}
std::string with_filter(const App& app, std::string text) { return std::move(text) + filter_suffix(app); }
uint32_t delay_color(uint64_t value) {
    if (value <= 249) return tui::kGreen;
    if (value <= 399) return tui::kBlue;
    if (value <= 9999) return tui::kYellow;
    return tui::kRed;
}
const char* group_label(const std::string& kind) {
    if (kind == "Selector") return "↦ 手动选择";
    if (kind == "URLTest") return "↯ 自动选择";
    if (kind == "Fallback") return "↪ 故障转移";
    if (kind == "LoadBalance") return "⇄ 负载均衡";
    if (kind == "Relay") return "⇢ 串联";
    return "◇ 代理组";
}
size_t visible_start(size_t selected, size_t length, size_t visible) {
    const size_t count = std::max<size_t>(visible, 1);
    return std::min(selected + 1 > count ? selected + 1 - count : 0, length > count ? length - count : 0);
}
void draw_spans(Screen& screen, int x, int y, int width, const Line& spans, const Matcher& matcher, std::optional<uint32_t> bg = {}) {
    int used = 0;
    for (const Span& part : spans) {
        if (used >= width) break;
        const int room = width - used;
        // Remote names, rules, hosts and log lines must not carry terminal escapes.
        const std::string cleaned = tui::clean(part.text);
        const std::string shown = tui::clip(cleaned, room);
        const auto ranges = matcher.highlight(cleaned);
        tui::put_ranges(screen, x + used, y, cleaned, ranges, Style{part.fg, bg, false, part.bold}, room);
        used += tui::width_of(shown);
    }
}
void draw_row(Screen& screen, Rect row, const Line& spans, const Matcher& matcher, bool selected) {
    std::optional<uint32_t> bg;
    if (selected) {
        tui::fill(screen, row, tui::kSelection);
        bg = tui::kSelection;
        tui::put(screen, row.x, row.y, "▌", Style{tui::kBlue, bg});
    }
    draw_spans(screen, row.x + (selected ? 1 : 0), row.y, row.width - (selected ? 1 : 0), spans, matcher, bg);
}
void draw_pane([[maybe_unused]] App& app, Screen& screen, Rect area, const std::string& title, const std::vector<Line>& lines, bool focused, const Matcher& matcher, int scroll = 0) {
    if (area.width <= 0 || area.height <= 0) return;
    tui::put(screen, area.x, area.y, "▌", Style{tui::kBlue});
    tui::put(screen, area.x + 2, area.y, tui::clip(title, std::max(area.width - 2, 0)), Style{focused ? tui::kBrightFg : tui::kMuted, {}, false, true}, std::max(area.width - 2, 0));
    const int rows = std::max(area.height - 1, 0);
    for (int i = 0; i < rows; ++i) {
        const int index = scroll + i;
        if (index < 0 || static_cast<size_t>(index) >= lines.size()) continue;
        draw_row(screen, Rect{area.x, area.y + 1 + i, area.width, 1}, lines[static_cast<size_t>(index)], matcher, false);
    }
}
// Usage lines: a thin bar, used/total and expiry, matching profiles.rs formatting.
std::vector<Line> usage_lines(const std::optional<Usage>& usage, int width) {
    if (!usage) return {line({muted("  用量未知 · 3 订阅 → f 读取用量响应头")})};
    const Usage& value = *usage;
    const int bar_width = std::clamp(width - 12, 4, 36);
    const double progress = value.progress().value_or(0.0);
    const size_t fill = static_cast<size_t>(std::lround(bar_width * progress));
    const std::string total = value.total == 0 ? "未知" : bytes_text(value.total);
    std::string expiry = "未知 / 不限";
    std::string days;
    if (const auto expires = value.expires_at()) {
        expiry = local_time(*expires, "%Y-%m-%d");
        const int64_t diff = (*expires - unix_now()) / 86400;
        days = diff < 0 ? " · 已到期" : " · 剩余 " + std::to_string(diff) + " 天";
    }
    Line bar;
    bar.push_back(span("  "));
    bar.push_back(span(repeat("━", fill) + repeat("─", static_cast<size_t>(bar_width) - fill), progress >= 0.9 ? tui::kYellow : tui::kBlue));
    char percent[32];
    std::snprintf(percent, sizeof percent, " %3.0f%% 已用", progress * 100.0);
    bar.push_back(muted(value.total > 0 ? percent : " 配额未知"));
    Line used;
    used.push_back(muted(tui::clip("  已用 " + bytes_text(value.used_bytes()) + " / " + total + " · 剩余 " +
                                      (value.remaining_bytes() ? bytes_text(*value.remaining_bytes()) : std::string("未知")),
                                  width)));
    bool warning = false;
    if (const auto expires = value.expires_at()) warning = (*expires - unix_now()) <= 7 * 86400;
    Line expiration;
    expiration.push_back(Span{tui::clip("  到期 " + expiry + days, width), warning ? tui::kYellow : tui::kMuted});
    return {bar, used, expiration};
}
void header(App& app, Screen& screen) {
    const std::string rate = app.traffic ? "↑" + bytes_text(app.traffic->up) + "/s ↓" + bytes_text(app.traffic->down) + "/s" : "流量 --";
    Tone tone = Tone::Warning;
    std::string phase = "○ 未运行";
    if (app.online) {
        tone = Tone::Success;
        phase = "● 运行";
    } else if (app.loading()) {
        tone = Tone::Info;
        phase = "◌ 连接中";
    }
    int x = tui::put(screen, 1, 0, "Clash", Style{tui::kBrightFg, {}, false, true});
    x = tui::put(screen, x + 2, 0, phase, Style{tone_color(tone)});
    const std::string mode = app.online ? tui::clean(app.config.mode) : "s 启动";
    tui::put(screen, x + 2, 0, tui::clip("  " + mode + "  " + rate, std::max(screen.dimx() - x - 2, 0)), Style{tui::kMuted});
}
void tabs(App& app, Screen& screen) {
    app.tab_hits.clear();
    int x = 1;
    for (size_t i = 0; i < kPageCount; ++i) {
        const int start = x;
        x = tui::put(screen, x, 1, std::to_string(i + 1), Style{tui::kMuted});
        x = tui::put(screen, x + 1, 1, kTabs[i], i == static_cast<size_t>(app.page) ? Style{tui::kBrightFg, {}, true} : Style{tui::kMuted});
        app.tab_hits.emplace_back(Rect{start, 1, x - start, 1}, i);
        x += 2;
    }
}
void overview(App& app, Screen& screen, Rect area) {
    const Matcher matcher(app.filter_text());
    const int height = std::max(area.height, 12);
    const int state_height = std::min(7, height);
    const int traffic_height = std::min(8, std::max(height - state_height, 4));
    const int subscription_height = std::max(height - state_height - traffic_height, 3);
    const Rect state{area.x, area.y, area.width, state_height};
    const Rect traffic{area.x, area.y + state_height, area.width, traffic_height};
    // One blank row keeps the border-less sections visually separate.
    const Rect subscriptions{area.x, area.y + state_height + traffic_height + (height > state_height + traffic_height + 4 ? 1 : 0), area.width,
                             subscription_height - (height > state_height + traffic_height + 4 ? 1 : 0)};
    std::vector<Line> lines;
    lines.push_back(line({span("  ● 运行中", tui::kBlue), muted("  " + app.version + " · " + app.config.mode)}));
    lines.push_back(line({span("  TUN " + std::string(app.config.tun ? "开启" : "关闭") + "   系统代理未设置 · 7 工具 / 设置")}));
    lines.push_back(line({span("  " + std::to_string(app.connections.size()) + " 条连接" + (app.connections_live ? "" : "（流已断开）") + "   内核连接内存 " + bytes_text(app.memory))}));
    lines.push_back(line({span(tui::clip("  " + app.chain(), std::max(area.width - 2, 0)))}));
    if (app.config.mode == "rule") {
        for (const std::string& name : app.group_names) {
            if (name == "GLOBAL") continue;
            const auto found = app.proxies.find(name);
            if (found != app.proxies.end()) {
                lines.push_back(line({muted(tui::clip("  参考组：" + name + " → " + found->second.now.value_or("按策略选择"), std::max(area.width - 2, 0)))}));
            }
            break;
        }
    }
    draw_pane(app, screen, state, "代理状态与出口", lines, true, matcher);
    // Traffic: independent axes for upload and download.
    tui::put(screen, traffic.x, traffic.y, "▌", Style{tui::kBlue});
    tui::put(screen, traffic.x + 2, traffic.y, "最近 60 秒 · 独立纵轴", Style{tui::kBrightFg, {}, false, true});
    const int halves[2] = {traffic.x, traffic.x + traffic.width / 2};
    const int half_width = std::max(traffic.width / 2 - 1, 4);
    for (int half = 0; half < 2; ++half) {
        std::vector<uint64_t> series;
        for (const auto& sample : app.history) series.push_back(half == 0 ? sample.first : sample.second);
        const uint64_t current = app.traffic ? (half == 0 ? app.traffic->up : app.traffic->down) : 0;
        const uint64_t total = half == 0 ? app.totals.first : app.totals.second;
        const uint32_t color = half == 0 ? tui::kBlue : tui::kGreen;
        const std::string label = std::string(half == 0 ? "↑ 上传 " : "↓ 下载 ") + (app.traffic ? bytes_text(current) + "/s" : "--");
        tui::put(screen, halves[half], traffic.y + 1, tui::clip(label, half_width), Style{color});
        const int chart_height = std::max(traffic.height - 3, 1);
        const int columns = std::min<int>(half_width, 60);
        const size_t take = std::min<size_t>(series.size(), static_cast<size_t>(columns));
        uint64_t maximum = 1;
        for (size_t i = series.size() - take; i < series.size(); ++i) maximum = std::max(maximum, series[i]);
        static const char* levels[] = {" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"};
        for (int row = 0; row < chart_height; ++row) {
            const int y = traffic.y + 2 + row;
            for (int column = 0; column < columns && static_cast<size_t>(column) < take; ++column) {
                const uint64_t value = series[series.size() - take + static_cast<size_t>(column)];
                const int cells = value == 0 ? 0 : std::max(1, static_cast<int>(std::ceil(static_cast<double>(value) / maximum * chart_height * 8.0)));
                const int from_bottom = (chart_height - 1 - row) * 8;
                const int level = std::clamp(cells - from_bottom, 0, 8);
                if (level > 0) tui::put(screen, halves[half] + column, y, levels[level], Style{color});
            }
        }
        tui::put(screen, halves[half], traffic.y + traffic.height - 1, tui::clip("本次内核累计 " + bytes_text(total), half_width), Style{tui::kMuted});
    }
    const Subscription* current = nullptr;
    for (const Subscription& item : app.store.items) {
        if (app.store.current && item.id == *app.store.current) current = &item;
    }
    std::vector<Line> subscription;
    if (current) {
        subscription.push_back(line({span("  " + current->name, tui::kBlue)}));
        std::optional<Usage> used = current->usage;
        if (const auto found = app.usage.find(current->id); found != app.usage.end()) used = found->second;
        const auto more = usage_lines(used, std::max(area.width - 5, 8));
        subscription.insert(subscription.end(), more.begin(), more.end());
    } else {
        subscription.push_back(line({span("  尚无当前订阅 · 3 订阅 → i 导入")}));
        subscription.push_back(line({muted("  订阅提供节点和规则。粘贴服务商提供的订阅链接添加。")}));
    }
    draw_pane(app, screen, subscriptions, "当前订阅 · 3 查看所有订阅", subscription, true, matcher);
}
void proxies(App& app, Screen& screen, Rect area) {
    const int left_width = std::max(area.width * 32 / 100, 12);
    const Rect left{area.x, area.y, left_width, area.height};
    const Rect right{area.x + left_width, area.y, area.width - left_width, area.height};
    const Matcher matcher(app.filters[static_cast<size_t>(PageKind::Proxies)].str());
    const int rows = std::max(left.height - 1, 0) / 2;
    const size_t start = visible_start(app.group, app.group_names.size(), static_cast<size_t>(rows));
    std::vector<Line> groups;
    app.row_hits.clear();
    for (size_t i = start; i < app.group_names.size() && i < start + static_cast<size_t>(rows); ++i) {
        const std::string& name = app.group_names[i];
        const Proxy& proxy = app.proxies.at(name);
        Line name_line;
        name_line.push_back(span(tui::clip(name, std::max(left_width - 3, 1))));
        groups.push_back(std::move(name_line));
        groups.push_back(line({muted(tui::clip("  " + std::string(group_label(proxy.kind)) + " · " + proxy.now.value_or("按策略"), std::max(left_width - 2, 1)))}));
        app.row_hits.push_back({{left.x, left.y + 1 + static_cast<int>((i - start) * 2), left.width, 2}, i, true});
    }
    draw_pane(app, screen, left, "代理组 " + std::to_string(app.group_names.size()), {}, !app.nodes_focus, matcher);
    // Draw the interleaved two-line group rows (pane() only handles one line per row).
    for (size_t i = 0; i < groups.size() && i / 2 < static_cast<size_t>(rows); ++i) {
        const int y = left.y + 1 + static_cast<int>(i);
        draw_row(screen, Rect{left.x, y, left.width, 1}, groups[i], matcher, i % 2 == 0 && (start + i / 2) == app.group);
    }
    const int node_rows = std::max(right.height - 1, 0);
    const size_t node_start = visible_start(app.node, app.node_names.size(), static_cast<size_t>(node_rows));
    std::vector<Line> nodes;
    const std::string current = app.current_node().value_or("");
    for (size_t i = node_start; i < app.node_names.size() && i < node_start + static_cast<size_t>(node_rows); ++i) {
        const std::string& name = app.node_names[i];
        Line row;
        row.push_back(span(current == name ? "● " : "  ", tui::kGreen));
        int label_width = 4;
        std::string label = "--";
        uint32_t label_color = tui::kMuted;
        const auto delay = app.delay(name);
        if (delay) {
            if (*delay) {
                label = std::to_string(**delay) + "ms";
                label_color = **delay >= app.opts_.prefs.timeout_ms ? tui::kRed : delay_color(**delay);
            } else {
                label = "超时";
                label_color = tui::kRed;
            }
        }
        label_width = tui::width_of(label);
        const int content_width = std::max(right.width - 1, 2);
        const int room = std::max(content_width - 4 - label_width, 2);
        row.push_back(span(tui::clip(name, room)));
        const int used = 2 + tui::width_of(tui::clip(name, room));
        row.push_back(span(repeat(" ", static_cast<size_t>(std::max(content_width - used - label_width, 1)))));
        row.push_back(span(label, label_color));
        nodes.push_back(std::move(row));
        app.row_hits.push_back({{right.x, right.y + 1 + static_cast<int>(i - node_start), right.width, 1}, i, false});
    }
    std::string node_title = "节点 " + std::to_string(app.node_names.size()) + "/" +
                             std::to_string(app.group_name() && app.proxies.count(*app.group_name()) ? app.proxies[*app.group_name()].all.size() : 0) + " · " + sort_label(app.sort) +
                             (app.hide_timeout ? " · 隐藏超时" : "");
    if (app.measuring) node_title += " · 测速 " + std::to_string(app.measuring->first) + "/" + std::to_string(app.measuring->second);
    draw_pane(app, screen, right, with_filter(app, node_title), {}, app.nodes_focus, matcher);
    for (size_t i = 0; i < nodes.size(); ++i) {
        draw_row(screen, Rect{right.x, right.y + 1 + static_cast<int>(i), right.width, 1}, nodes[i], matcher, (node_start + i) == app.node);
    }
    if (nodes.empty()) {
        const std::string message = !app.filter_text().empty() ? "无匹配节点 · Esc 清除过滤" : "暂无节点 · r 刷新或 3 检查订阅";
        tui::put(screen, right.x + 1, right.y + 1, tui::clip(message, std::max(right.width - 2, 1)), Style{tui::kMuted});
    }
}
void providers(App& app, Screen& screen, Rect area) {
    const auto& map = app.page == PageKind::Rules ? app.rule_providers : app.providers;
    const Matcher matcher(app.filter_text());
    const int rows = std::max(area.height - 1, 0) / 2;
    const size_t start = visible_start(app.provider, app.provider_view.size(), static_cast<size_t>(rows));
    std::vector<Line> lines;
    app.row_hits.clear();
    for (size_t i = start; i < app.provider_view.size() && i < start + static_cast<size_t>(rows); ++i) {
        const std::string& name = app.provider_view[i];
        if (!map.count(name)) continue;
        const Provider& provider = map.at(name);
        lines.push_back(line({span(tui::clip(name + " · " + provider.vehicle_type + " · " + provider.kind, std::max(area.width - 4, 1)))}));
        const bool empty_update = provider.updated_at.empty() || provider.updated_at.rfind("0001-", 0) == 0;
        lines.push_back(line({muted(tui::clip("  " + std::to_string(app.page == PageKind::Rules ? provider.rule_count : provider.proxies.size()) + " 项 · 更新 " +
                                                  (empty_update ? "内核未提供" : provider.updated_at),
                                              std::max(area.width - 2, 1)))}));
        app.row_hits.push_back({{area.x, area.y + 1 + static_cast<int>((i - start) * 2), area.width, 2}, i, false});
    }
    if (lines.empty()) lines.push_back(line({muted(" 无匹配 provider · p 返回 · Esc 清除过滤")}));
    const std::string title = app.page == PageKind::Rules
                                  ? "规则源 " + std::to_string(app.provider_view.size()) + "/" + std::to_string(app.rule_providers.size()) + " · u 更新 / p 返回"
                                  : "节点源 " + std::to_string(app.provider_view.size()) + "/" + std::to_string(app.providers.size()) + " · t 健康检查 / u 更新 / p 返回";
    draw_pane(app, screen, area, with_filter(app, title), {}, false, matcher);
    for (size_t i = 0; i < lines.size() && i / 2 < static_cast<size_t>(rows); ++i) {
        draw_row(screen, Rect{area.x, area.y + 1 + static_cast<int>(i), area.width, 1}, lines[i], matcher, i % 2 == 0 && (start + i / 2) == app.provider);
    }
}
void profiles(App& app, Screen& screen, Rect area) {
    const Matcher matcher(app.filter_text());
    const int rows = std::max(area.height - 1, 0) / 5;
    const size_t start = visible_start(app.profile, app.store.items.size(), static_cast<size_t>(rows));
    std::vector<Line> lines;
    app.row_hits.clear();
    for (size_t i = start; i < app.store.items.size() && i < start + static_cast<size_t>(rows); ++i) {
        const Subscription& item = app.store.items[i];
        const bool current = app.store.current && *app.store.current == item.id;
        Line name_line;
        name_line.push_back(span(current ? "● " : "  ", tui::kBlue));
        name_line.push_back(span(tui::clip(item.name, std::max(area.width - 5, 1))));
        lines.push_back(std::move(name_line));
        std::optional<Usage> used = item.usage;
        if (const auto found = app.usage.find(item.id); found != app.usage.end()) used = found->second;
        auto usage = usage_lines(used, std::max(area.width - 4, 8));
        usage.resize(3, Line{});
        lines.insert(lines.end(), usage.begin(), usage.end());
        lines.push_back(line({muted(tui::clip("  节点 " + std::to_string(item.nodes) + "（配置内） · 上次更新 " + local_time(item.updated, "%m-%d %H:%M"), std::max(area.width - 2, 1)))}));
        app.row_hits.push_back({{area.x, area.y + 1 + static_cast<int>((i - start) * 5), area.width, 5}, i, false});
    }
    if (lines.empty()) {
        lines = {
            line({}),
            line({span("  还没有订阅 · i 导入", tui::kBlue)}),
            line({}),
            line({span("  1. 向服务商获取订阅链接")}),
            line({span("  2. 按 i 粘贴订阅链接，下载并校验后添加")}),
            line({span("  3. 回到 TUI 自动刷新，再到 2 代理选择节点")}),
            line({}),
            line({muted("  订阅不会自动启动服务；准备好后 s 手动启动。")}),
        };
    }
    const std::string title = app.native_busy ? "订阅 · 下载 / 校验 / 应用中…" : "订阅 · ● 当前 · 仅保存在本机私有目录";
    draw_pane(app, screen, area, title, {}, false, matcher);
    for (size_t i = 0; i < lines.size() && i / 5 < static_cast<size_t>(rows); ++i) {
        draw_row(screen, Rect{area.x, area.y + 1 + static_cast<int>(i), area.width, 1}, lines[i], matcher, i == 0 && (start + i / 5) == app.profile);
    }
}
void connections(App& app, Screen& screen, Rect area) {
    const Matcher matcher(app.filters[static_cast<size_t>(PageKind::Connections)].str());
    const int rows = std::max(area.height - 1, 0) / 2;
    const size_t start = visible_start(app.connection, app.connection_view.size(), static_cast<size_t>(rows));
    std::vector<Line> lines;
    app.row_hits.clear();
    for (size_t i = start; i < app.connection_view.size() && i < start + static_cast<size_t>(rows); ++i) {
        const Connection& connection = app.connections[app.connection_view[i]];
        const std::string host = connection.metadata.host.empty() ? connection.metadata.destination_ip : connection.metadata.host;
        const std::string right = (app.rates.count(connection.id) ? bytes_text(app.rates.at(connection.id)) : std::string("--")) + " /s  " + age_text(connection.start);
        const int left_room = std::max(area.width - 5 - tui::width_of(right), 2);
        const std::string left = tui::clip(host + ":" + connection.metadata.destination_port, left_room);
        Line first;
        first.push_back(span(left));
        first.push_back(span(repeat(" ", static_cast<size_t>(std::max(left_room - tui::width_of(left), 0)))));
        first.push_back(span(right, tui::kBlue));
        lines.push_back(std::move(first));
        std::string chains;
        for (const std::string& part : connection.chains) {
            if (!chains.empty()) chains += " → ";
            chains += part;
        }
        lines.push_back(line({muted(tui::clip("  " + connection.metadata.process + " · " + connection.rule + " → " + chains + " · ↑" + bytes_text(connection.upload) + " ↓" +
                                                  bytes_text(connection.download),
                                              std::max(area.width - 2, 1)))}));
        app.row_hits.push_back({{area.x, area.y + 1 + static_cast<int>((i - start) * 2), area.width, 2}, i, false});
    }
    if (lines.empty()) lines.push_back(line({muted(" 暂无匹配连接 · Esc 清除过滤")}));
    static const char* sorts[] = {"速率", "总量", "时长", "主机"};
    const std::string title = "活动连接 " + std::to_string(app.connection_view.size()) + "/" + std::to_string(app.connections.size()) + " · " + sorts[app.connection_sort % 4] + " · " +
                              (app.connections_live ? "实时" : "流已断开");
    draw_pane(app, screen, area, with_filter(app, title), {}, false, matcher);
    for (size_t i = 0; i < lines.size() && i / 2 < static_cast<size_t>(rows); ++i) {
        draw_row(screen, Rect{area.x, area.y + 1 + static_cast<int>(i), area.width, 1}, lines[i], matcher, i % 2 == 0 && (start + i / 2) == app.connection);
    }
}
void rules(App& app, Screen& screen, Rect area) {
    const Matcher matcher(app.filters[static_cast<size_t>(PageKind::Rules)].str());
    const int rows = std::max(area.height - 1, 0) / 2;
    const size_t start = visible_start(app.rule, app.rule_view.size(), static_cast<size_t>(rows));
    std::vector<Line> lines;
    app.row_hits.clear();
    for (size_t i = start; i < app.rule_view.size() && i < start + static_cast<size_t>(rows); ++i) {
        const Rule& rule = app.rules[app.rule_view[i]];
        lines.push_back(line({span(tui::clip(rule.kind + "  " + rule.payload, std::max(area.width - 4, 1)))}));
        std::string hits;
        if (rule.extra) {
            hits = "命中 " + std::to_string(rule.extra->hit_count) + " 次";
        } else {
            size_t count = 0;
            for (const Connection& connection : app.connections) {
                if (connection.rule == rule.kind && connection.rule_payload == rule.payload) ++count;
            }
            hits = "当前匹配连接 " + std::to_string(count) + "（非累计命中）";
        }
        lines.push_back(line({muted(tui::clip("  → " + rule.proxy + " · " + hits, std::max(area.width - 2, 1)))}));
        app.row_hits.push_back({{area.x, area.y + 1 + static_cast<int>((i - start) * 2), area.width, 2}, i, false});
    }
    if (lines.empty()) {
        const std::string message = !app.filter_text().empty() ? "没有匹配规则 · Esc 清除过滤" : app.resources_loading() ? "正在加载规则…" : "暂无规则 · r 刷新或检查当前订阅";
        lines.push_back(line({muted(message)}));
    }
    draw_pane(app, screen, area, with_filter(app, "规则 " + std::to_string(app.rule_view.size()) + "/" + std::to_string(app.rules.size()) + " · p 规则源"), {}, false, matcher);
    for (size_t i = 0; i < lines.size() && i / 2 < static_cast<size_t>(rows); ++i) {
        draw_row(screen, Rect{area.x, area.y + 1 + static_cast<int>(i), area.width, 1}, lines[i], matcher, i % 2 == 0 && (start + i / 2) == app.rule);
    }
}
void logs(App& app, Screen& screen, Rect area) {
    const Matcher matcher(app.filters[static_cast<size_t>(PageKind::Logs)].str());
    const int rows = std::max(area.height - 1, 0);
    const size_t start = visible_start(app.log, app.log_view.size(), static_cast<size_t>(rows));
    std::vector<Line> lines;
    app.row_hits.clear();
    for (size_t i = start; i < app.log_view.size() && i < start + static_cast<size_t>(rows); ++i) {
        const LogEntry& entry = app.logs[app.log_view[i]];
        const uint32_t color = entry.level == "error" ? tui::kRed : (entry.level == "warning" || entry.level == "warn") ? tui::kYellow : entry.level == "debug" ? tui::kMuted : tui::kGreen;
        std::string level = entry.level;
        level.resize(7, ' ');
        Line row;
        row.push_back(span(level, color));
        row.push_back(span(tui::clip(entry.payload, std::max(area.width - 10, 1))));
        lines.push_back(std::move(row));
        app.row_hits.push_back({{area.x, area.y + 1 + static_cast<int>(i - start), area.width, 1}, i, false});
    }
    if (lines.empty()) lines.push_back(line({muted(" 无匹配日志 · Esc 清除过滤 · L 切级别")}));
    static const char* levels[] = {"debug", "info", "warning", "error"};
    const std::string title = "日志 " + std::to_string(app.log_view.size()) + "/" + std::to_string(app.logs.size()) + " · " + levels[app.log_level % 4] + " · " +
                              (app.logs_paused ? "已暂停（丢弃新日志）" : app.logs_live ? "实时 · 最多 2000 条" : "等待日志流");
    draw_pane(app, screen, area, with_filter(app, title), {}, false, matcher);
    for (size_t i = 0; i < lines.size() && i < static_cast<size_t>(rows); ++i) {
        draw_row(screen, Rect{area.x, area.y + 1 + static_cast<int>(i), area.width, 1}, lines[i], matcher, (start + i) == app.log);
    }
}
void tools(App& app, Screen& screen, Rect area) {
    const Matcher matcher(app.filter_text());
    const int rows = std::max(area.height - 1, 0) / 3;
    const size_t start = visible_start(app.tool, 9, static_cast<size_t>(rows));
    std::vector<Line> lines;
    app.row_hits.clear();
    for (size_t i = start; i < 9 && i < start + static_cast<size_t>(rows); ++i) {
        std::string name;
        std::string detail;
        switch (i) {
            case 0: name = "清空 fake-ip 缓存"; detail = "移除 DNS 虚拟地址映射"; break;
            case 1: name = "清空 DNS 缓存"; detail = "下次解析时重新查询"; break;
            case 2: name = "更新 GeoIP / GeoSite"; detail = "通过 mihomo 下载并重载，数据保存在私有目录"; break;
            case 3: name = "TUN                 " + std::string(app.native_settings.tun ? "开启" : "关闭"); detail = "接管流量；关闭后只保留显式代理端口"; break;
            case 4: name = "模式                " + app.native_settings.mode; detail = "rule / global / direct"; break;
            case 5: name = "IPv6                " + std::string(app.native_settings.ipv6 ? "true" : "false"); detail = "同时调整 DNS IPv6"; break;
            case 6: name = "allow-lan           " + std::string(app.native_settings.allow_lan ? "true" : "false"); detail = "默认 false，仅本机访问；开启将监听所有地址"; break;
            case 7: name = "日志级别            " + app.native_settings.log_level; detail = "Enter 循环 info / debug / warning / error / silent"; break;
            default: name = "mixed-port          " + std::to_string(app.native_settings.mixed_port); detail = "Enter 编辑；设置持久保存并立即重载"; break;
        }
        lines.push_back(line({span(tui::clip(name, std::max(area.width - 2, 1)))}));
        lines.push_back(line({muted(tui::clip("  " + detail, std::max(area.width - 3, 1)))}));
        lines.push_back(line({}));
        app.row_hits.push_back({{area.x, area.y + 1 + static_cast<int>((i - start) * 3), area.width, 3}, i, false});
    }
    draw_pane(app, screen, area, "工具 / 设置 · Enter 应用 · 保存后重启仍保留", {}, false, matcher);
    for (size_t i = 0; i < lines.size() && i / 3 < static_cast<size_t>(rows); ++i) {
        draw_row(screen, Rect{area.x, area.y + 1 + static_cast<int>(i), area.width, 1}, lines[i], matcher, i == 0 && (start + i / 3) == app.tool);
    }
}
void offline(App& app, Screen& screen, Rect area) {
    const Matcher matcher(app.filter_text());
    std::vector<Line> lines;
    lines.push_back(line({}));
    lines.push_back(line({span("  " + app.launch_progress(), tui::kBlue)}));
    lines.push_back(line({}));
    lines.push_back(line({span("  s 启动服务    3 订阅    7 设置    ? 新手指引")}));
    lines.push_back(line({}));
    lines.push_back(line({muted("  手动开、手动关；服务不随开机启动。")}));
    lines.push_back(line({muted(app.store.items.empty() ? "  首次使用：i 添加订阅。" : "  订阅已就绪；s 启动后由 TUN 接管流量，X 关闭后直连。")}));
    draw_pane(app, screen, area, app.loading() ? "正在连接内核" : "Clash 未运行", lines, true, matcher);
}
// ---- Modal geometry ----------------------------------------------------------------------------
int dialog_height(const Dialog& dialog) {
    switch (dialog.kind) {
        case Dialog::Kind::Import: return 13;
        case Dialog::Kind::Detail: return 22;
        case Dialog::Kind::Confirm:
        case Dialog::Kind::Edit: return 9;
    }
    return 9;
}
Rect dialog_area(const App& app, const Dialog& dialog) { return tui::centered(app.screen_width, app.screen_height, 80, dialog_height(dialog)); }
Tone dialog_tone(const std::string& title) {
    if (title.find("错误") != std::string::npos || title.find("失败") != std::string::npos) return Tone::Error;
    if (title.find("确认") != std::string::npos) return Tone::Warning;
    return Tone::Action;
}
void draw_modal_frame(App& app, Screen& screen, const Dialog& dialog, const std::string& base, const std::vector<Line>& lines, int scroll) {
    const Rect area = dialog_area(app, dialog);
    if (area.width <= 0 || area.height <= 0) return;
    tui::fill(screen, area, tui::kSurface);
    const Tone tone = dialog_tone(base);
    tui::box(screen, area, " " + std::string(tone_symbol(tone)) + "  " + base + " ", true, tui::kSurface);
    const Matcher matcher("");
    int y = area.y + 1;
    for (size_t i = static_cast<size_t>(std::max(scroll, 0)); i < lines.size() && y < area.y + area.height - 3; ++i, ++y) {
        draw_spans(screen, area.x + 1, y, area.width - 2, lines[i], matcher, tui::kSurface);
    }
    const int button_y = area.y + area.height - 2;
    const std::string primary = dialog.kind == Dialog::Kind::Detail ? " [ Enter 返回 ]"
                                : dialog.kind == Dialog::Kind::Import ? " [ Enter 添加订阅 ]"
                                : dialog.kind == Dialog::Kind::Edit ? " [ Enter 保存 ]"
                                                                    : " [ Enter 确认 ]";
    tui::put(screen, area.x + 2, button_y, primary, Style{tui::kBlue, tui::kSurface});
    tui::put(screen, area.x + area.width / 2, button_y, " [ Esc 返回 / 取消 ]", Style{tui::kMuted, tui::kSurface});
}
std::pair<std::string, int> masked_window(const tui::TextInput& input, int room, bool masked) {
    std::string before = input.before_cursor();
    std::string all = input.str();
    if (masked) {
        before = repeat("*", tui::decode(before).size());
        all = repeat("*", tui::decode(all).size());
    }
    int cursor = tui::width_of(before);
    size_t skip = 0;
    const std::u32string before_chars = tui::decode(before);
    while (cursor >= room && skip < before_chars.size()) {
        cursor -= tui::width_of(tui::encode(std::u32string_view(before_chars).substr(skip++, 1)));
    }
    return {tui::clip(tui::encode(std::u32string_view(tui::decode(all)).substr(skip)), room), cursor};
}
void help_modal(App& app, Screen& screen) {
    static const char* bodies[] = {
        "mayon-clash.service 运行 mihomo，TUI 管配置与启停。\n服务不随开机启动：先 3 → i 添加，再 s 启动；X 确认关闭。\nTUN 接管 IP 流量，DNS hijack 交给内核；7 工具可调整并持久保存。\n不设置系统代理：TUN 已接管流量；显式程序可用本机 mixed-port。\nrule 按规则分流；global 全部走 GLOBAL；direct 绕过代理。\n关闭服务后 TUN 消失、网络直连；退出 TUI 本身不会关闭服务。",
        "组是节点的选择策略。Tab / h/l 切组与节点面板，Enter 选中。\n↦ Selector 手动；↯ URLTest 自动最快；↪ Fallback 首个可用。\nURLTest/Fallback 允许临时手动指定；T 整组测速会恢复自动选择。\n⇄ LoadBalance 按连接分配，⇢ Relay 串联；无固定节点，不能手动选。\nt 单测 · T 内核组测 · b 测过滤列表（配置并发）· Esc 取消本地队列。\nS 默认/延迟/名称排序 · H 隐藏超时 · c 跳当前 · / 拼音首字母/中英模糊过滤。\np 节点源：t 健康检查，u 更新（源内并发与测试 URL 由内核管理）。",
        "i 添加：粘贴 URL（仅显示脱敏地址），Tab 可选名称，Enter 下载校验。\nEnter 切换 · u 单个更新 · U 全部更新 · n 重命名 · e 编辑 URL。\nd 确认删除；当前项须先切换。用量、到期、配置内节点数显示于列表。\n先直连，失败且内核运行时经 mixed-port 重试；默认每 24h 更新。\nTUI 打开且内核运行时后台检查更新间隔；链接只存在私有 0600 索引。",
        "连接是应用访问目标的一次会话；规则决定它走哪个组与节点。\nS 按速率/总量/时长/主机排序 · / 主机、IP、进程、规则、链路过滤。\nEnter 查看目标、规则、链路、进程、开始时间；j/k 可滚动详情。\nx 关闭单个 · d 关闭过滤结果快照 · D 全部关闭，均先确认。\n速率由连续快照差值得到，首帧和断流时未知；WebSocket 每秒更新。",
        "规则从上至下决定目标的出站策略；/ 搜索类型、内容或策略。\nEnter 看完整规则及命中；内核提供累计命中时优先显示。\n否则显示当前连接匹配数，并非历史累计。p 查看规则源，u 更新。\n规则源属于当前内核配置。",
        "日志流来自当前内核，最多保留 2000 条，仅在进程内存。\nL 循环 debug/info/warning/error 最低级别 · / 搜索。\n空格暂停（丢弃新日志，界面停止追随）；再次空格恢复。\nj/k、PageUp/PageDown、g/G 滚动；G 回到追随。\n链接与常见凭据字段会隐藏；本程序不将日志写盘。",
        "Enter 选择工具并确认，Esc 取消；联网与文件错误会显示在底部。\nfake-ip 缓存存虚拟地址映射，DNS 缓存存解析结果。\nGeoIP/GeoSite 更新由内核处理；Nix store 资源只读时可能失败。\nm 循环 rule/global/direct。TUN 设置可在本页修改。",
    };
    std::vector<Line> lines;
    lines.push_back(line({}));
    lines.push_back(line({span("  " + std::to_string(app.help_page + 1) + " · " + kTabs[app.help_page], tui::kBlue)}));
    lines.push_back(line({}));
    std::istringstream stream(bodies[app.help_page % kPageCount]);
    for (std::string text; std::getline(stream, text);) lines.push_back(line({span("  " + text)}));
    lines.push_back(line({}));
    lines.push_back(line({muted("  1–7 / ←→ 分页 · j/k / 方向键移动 · g/G 首尾 · PgUp/PgDn 翻页")}));
    lines.push_back(line({span("  Tab 下一页 · ? / Esc 返回 · 鼠标滚轮可切帮助页", tui::kBlue)}));
    const Rect area = tui::centered(app.screen_width, app.screen_height, 80, 23);
    tui::fill(screen, area, tui::kSurface);
    tui::box(screen, area, " ›  新手指引与按页帮助 ", true, tui::kSurface);
    const Matcher matcher("");
    int y = area.y + 1;
    for (const Line& value : lines) {
        if (y >= area.y + area.height - 1) break;
        draw_spans(screen, area.x + 1, y++, area.width - 2, value, matcher, tui::kSurface);
    }
}
void dialog_modal(App& app, Screen& screen) {
    const Dialog& dialog = *app.dialog;
    const Rect area = dialog_area(app, dialog);
    std::vector<Line> lines;
    switch (dialog.kind) {
        case Dialog::Kind::Confirm:
            lines.push_back(line({}));
            lines.push_back(line({span("  " + dialog.body)}));
            lines.push_back(line({}));
            lines.push_back(line({span("  Enter / y 确认 · Esc / n 取消", tui::kBlue)}));
            draw_modal_frame(app, screen, dialog, "确认操作", lines, 0);
            break;
        case Dialog::Kind::Import:
            lines.push_back(line({}));
            lines.push_back(line({span(std::string(dialog.field ? "   " : "  >") + "URL：", tui::kBlue)}));
            lines.push_back(line({}));
            lines.push_back(line({span(std::string(dialog.field ? "  >" : "   ") + "名称：")}));
            lines.push_back(line({}));
            lines.push_back(line({muted("  名称留空：响应头标题 / 文件名，再回退主机名。")}));
            lines.push_back(line({muted("  URL 仅保存到私有索引，不写日志。")}));
            lines.push_back(line({}));
            lines.push_back(line({span("  Tab 切字段 · Enter 下载并校验 · Esc 取消", tui::kBlue)}));
            draw_modal_frame(app, screen, dialog, "导入订阅", lines, 0);
            break;
        case Dialog::Kind::Edit: {
            lines.push_back(line({}));
            lines.push_back(line({}));
            lines.push_back(line({}));
            lines.push_back(line({muted("  Enter 保存 · Esc 取消")}));
            draw_modal_frame(app, screen, dialog, dialog.title, lines, 0);
            break;
        }
        case Dialog::Kind::Detail: {
            std::vector<Line> wrapped;
            std::istringstream stream(dialog.text);
            for (std::string text; std::getline(stream, text);) {
                for (const std::string& part : tui::wrap(text, std::max(area.width - 4, 8), 1000)) wrapped.push_back(line({span(" " + part)}));
            }
            draw_modal_frame(app, screen, dialog, "详情 · j/k 滚动 / Esc 返回", wrapped, app.detail_scroll);
            break;
        }
    }
    // Inputs are painted on top of the label rows, with the cursor position returned.
    auto input_area = [&](int row, int prefix) {
        return Rect{area.x + prefix, area.y + row, std::max(area.width - prefix - 2, 1), 1};
    };
    if (dialog.kind == Dialog::Kind::Edit) {
        const bool masked = dialog.edit.kind == EditKind::Url;
        const Rect input = input_area(2, 4);
        const auto [text, cursor] = masked_window(dialog.value, input.width, masked);
        tui::put(screen, input.x, input.y, text, Style{tui::kBlue, tui::kSurface});
        app.cursor_ = std::make_pair(input.x + cursor, input.y);
    } else if (dialog.kind == Dialog::Kind::Import) {
        if (dialog.field) {
            const Rect input = input_area(4, 11);
            const auto [text, cursor] = masked_window(dialog.name, input.width, false);
            tui::put(screen, input.x, input.y, text, Style{tui::kBlue, tui::kSurface});
            app.cursor_ = std::make_pair(input.x + cursor, input.y);
        } else {
            const Rect input = input_area(2, 10);
            const auto [text, cursor] = masked_window(dialog.url, input.width, true);
            tui::put(screen, input.x, input.y, text, Style{tui::kBlue, tui::kSurface});
            app.cursor_ = std::make_pair(input.x + cursor, input.y);
        }
    }
}
std::vector<tui::Hint> hints_for(const App& app) {
    using H = tui::Hint;
    if (app.dialog) return {H{"Enter", "确认"}, H{"Esc", "取消"}};
    if (app.help) return {H{"1–7", "切页"}, H{"←/→", "切页"}, H{"Esc", "返回"}};
    if (app.filtering) return {H{"↑/↓", "选择"}, H{"Enter", "保留"}, H{"Esc", "恢复"}};
    if (!app.online && app.page != PageKind::Profiles && app.page != PageKind::Tools) return {H{"3", "订阅"}, H{"i", "添加"}, H{"s", "启动"}, H{"?", "帮助"}, H{"q", "退出"}};
    switch (app.page) {
        case PageKind::Overview: return {H{"2", "选节点"}, H{"3", "订阅"}, H{"7", "设置"}, H{"m", "模式"}, H{"X", "关闭"}, H{"?", "帮助"}, H{"q", "退出"}};
        case PageKind::Proxies:
            if (app.provider_mode) return {H{"j/k", "移动"}, H{"t", "健康检查"}, H{"u", "更新"}, H{"p", "返回节点"}, H{"/", "过滤"}, H{"?", "帮助"}};
            return {H{"j/k", "移动"}, H{"Tab", "面板"}, H{"Enter", "选节点"}, H{"t/T", "测速"}, H{"S", "排序"}, H{"/", "过滤"}, H{"?", "帮助"}};
        case PageKind::Profiles:
            return {H{"j/k", "移动"}, H{"i", "添加"}, H{"f", "刷新用量"}, H{"u", "更新"}, H{"Enter", "切换"}, H{"n", "改名"}, H{"e", "URL"}, H{"d", "删除"}, H{"?", "帮助"}};
        case PageKind::Connections: return {H{"j/k", "移动"}, H{"Enter", "详情"}, H{"S", "排序"}, H{"/", "过滤"}, H{"x", "关闭"}, H{"d", "关闭过滤"}, H{"D", "全关"}, H{"?", "帮助"}};
        case PageKind::Rules: return {H{"j/k", "移动"}, H{"/", "过滤"}, H{"Enter", "命中详情"}, H{"p", "规则源"}, H{"u", "更新源"}, H{"?", "帮助"}};
        case PageKind::Logs: return {H{"j/k", "滚动"}, H{"/", "搜索"}, H{"L", "级别"}, H{"空格", "暂停"}, H{"g/G", "首尾"}, H{"?", "帮助"}};
        case PageKind::Tools: return {H{"j/k", "移动"}, H{"Enter", "执行 / 编辑"}, H{"m", "模式"}, H{"?", "帮助"}};
    }
    return {};
}
}  // namespace

void ui_draw(App& app, Screen& screen, tui::Rect area) {
    app.screen_width = std::max(area.width, 1);
    app.screen_height = std::max(area.height, 1);
    app.tab_hits.clear();
    app.row_hits.clear();
    app.cursor_.reset();
    tui::fill(screen, area, tui::kBg);
    if (area.width < 44 || area.height < 12) {
        tui::put(screen, area.x + 1, area.y, "请放大终端至至少 44 × 12", Style{tui::kFg});
        tui::put(screen, area.x + 1, area.y + 1, "q 退出", Style{tui::kMuted});
        return;
    }
    header(app, screen);
    tabs(app, screen);
    const Rect content{0, 2, area.width, std::max(area.height - 4, 1)};
    if (!app.online && app.page != PageKind::Profiles && app.page != PageKind::Tools) {
        offline(app, screen, content);
    } else {
        switch (app.page) {
            case PageKind::Overview: overview(app, screen, content); break;
            case PageKind::Proxies:
                if (app.provider_mode) providers(app, screen, content);
                else proxies(app, screen, content);
                break;
            case PageKind::Profiles: profiles(app, screen, content); break;
            case PageKind::Connections: connections(app, screen, content); break;
            case PageKind::Rules:
                if (app.provider_mode) providers(app, screen, content);
                else rules(app, screen, content);
                break;
            case PageKind::Logs: logs(app, screen, content); break;
            case PageKind::Tools: tools(app, screen, content); break;
        }
    }
    const int footer = area.height - 2;
    if (app.filtering) {
        tui::put(screen, 1, footer, " 过滤 /", Style{tui::kBlue});
        const std::string before = app.filters[static_cast<size_t>(app.page)].before_cursor();
        const int room = std::max(area.width - 9, 1);
        const std::string before_text = tui::clip(" " + before, room);
        tui::put(screen, 8, footer, before_text, Style{tui::kBlue});
        app.cursor_ = std::make_pair(8 + tui::width_of(before_text), footer);
    } else {
        tui::put_hints(screen, 1, footer, area.width - 2, hints_for(app));
    }
    if (app.notice_until && *app.notice_until > std::chrono::steady_clock::now() && !app.notice_text.empty()) {
        const std::string text = std::string(tone_symbol(app.notice_tone)) + " " + tui::clean(app.notice_text);
        tui::put(screen, 1, area.height - 1, tui::clip(text, std::max(area.width - 2, 1)), Style{tone_color(app.notice_tone)});
    }
    if (app.help) help_modal(app, screen);
    if (app.dialog) dialog_modal(app, screen);
    if (app.help || app.dialog) {
        // The dialog covers any input; keeping a cursor there would blink on top of it.
        if (app.dialog && (app.dialog->kind == Dialog::Kind::Edit || app.dialog->kind == Dialog::Kind::Import)) {
            // Keep the input cursor from dialog_modal.
        } else {
            app.cursor_.reset();
        }
    }
}
}  // namespace clash
