//! Render only the visible rows; geometry is also used for mouse hit testing.
use crate::{
    app::{visible_start, App, Dialog, Page},
    profiles::Usage,
    theme::*,
};
use mayon_ui::{base, blue, marker, muted};
use ratatui::{
    layout::{Constraint, Layout, Rect, Size},
    style::Style,
    text::{Line, Span},
    widgets::{Block, Clear, Paragraph, Sparkline, Wrap},
    Frame,
};
use unicode_width::UnicodeWidthStr;

pub const TABS: [&str; 7] = ["概览", "代理", "订阅", "连接", "规则", "日志", "工具"];
pub fn tab_at(column: u16) -> Option<char> {
    let mut x = 1;
    for (i, title) in TABS.iter().enumerate() {
        let width = title.width() as u16 + 5;
        if (x..x + width).contains(&column) {
            return Some((b'1' + i as u8) as char);
        }
        x += width + 2;
    }
    None
}
fn block(title: impl Into<String>) -> Block<'static> {
    mayon_ui::block(title, true)
}
fn title(app: &App, text: &str, area: Rect) -> String {
    clip(
        &format!(
            " {text}{} ",
            if app.filter().is_empty() && !app.filtering {
                String::new()
            } else {
                format!(
                    " · /{}{}",
                    app.filter(),
                    if app.filtering { "▏" } else { "" }
                )
            }
        ),
        area.width.saturating_sub(2) as usize,
    )
}
fn pane(frame: &mut Frame, area: Rect, title: String, text: Vec<Line<'static>>) {
    frame.render_widget(Paragraph::new(text).style(base()).block(block(title)), area);
}
fn visible(area: Rect, selected: usize, len: usize, row_height: usize) -> std::ops::Range<usize> {
    let count = area.height.saturating_sub(2) as usize / row_height;
    let start = visible_start(selected, len, count);
    start..(start + count).min(len)
}
fn selected_line(parts: Vec<Span<'static>>, selected: bool) -> Line<'static> {
    Line::from(parts).style(if selected {
        base().bg(SELECTION)
    } else {
        base()
    })
}
pub fn draw(frame: &mut Frame, app: &App) {
    let area = frame.area();
    frame.render_widget(Block::default().style(base()), area);
    if area.width < 44 || area.height < 12 {
        frame.render_widget(
            Paragraph::new("请放大终端至至少 44 × 12\nq 退出").style(base()),
            area,
        );
        return;
    }
    let chunks = Layout::vertical([
        Constraint::Length(1),
        Constraint::Length(2),
        Constraint::Min(1),
        Constraint::Length(2),
    ])
    .split(area);
    let rate = app
        .traffic
        .as_ref()
        .map(|t| format!("↑{}/s ↓{}/s", bytes(t.up), bytes(t.down)))
        .unwrap_or_else(|| "流量 --".into());
    mayon_ui::status(
        frame,
        chunks[0],
        &format!(
            " 󰒍 Clash · {} · {} · {} · {rate}",
            "mayon-clash",
            if app.online { "运行" } else { "未运行" },
            if app.online {
                app.config.mode.as_str()
            } else {
                "s 启动"
            }
        ),
    );
    frame.render_widget(
        Paragraph::new(mayon_ui::tabs_line(&TABS, app.page as usize)),
        chunks[1],
    );
    if !app.online && app.page != Page::Profiles && app.page != Page::Tools {
        let progress = app.launch_progress();
        pane(
            frame,
            chunks[2],
            " Clash 未运行 ".into(),
            vec![
                Line::from(""),
                Line::from(blue(format!("  {progress}"))),
                Line::from(""),
                Line::from("  s 启动服务    3 订阅    7 设置    ? 新手指引"),
                Line::from(""),
                Line::from(muted("  手动开、手动关；服务不随开机启动。")),
                Line::from(muted(if app.store.items.is_empty() {
                    "  首次使用：i 添加订阅。"
                } else {
                    "  订阅已就绪；s 启动后由 TUN 接管流量，X 关闭后直连。"
                })),
            ],
        );
    } else {
        match app.page {
            Page::Overview => overview(frame, app, chunks[2]),
            Page::Proxies if !app.provider_mode => proxies(frame, app, chunks[2]),
            Page::Proxies | Page::Rules if app.provider_mode => providers(frame, app, chunks[2]),
            Page::Profiles => profiles(frame, app, chunks[2]),
            Page::Connections => connections(frame, app, chunks[2]),
            Page::Rules => rules(frame, app, chunks[2]),
            Page::Logs => logs(frame, app, chunks[2]),
            Page::Tools => tools(frame, app, chunks[2]),
            _ => {}
        }
    }
    let hint = match app.page {
        Page::Overview => " 2 选节点  3 订阅  7 设置  m 模式  X 关闭  ? 帮助  q 退出",
        Page::Proxies if app.provider_mode => {
            " j/k 移动  t 健康检查  u 更新  p 返回节点  / 过滤  ? 帮助"
        }
        Page::Proxies => " j/k 移动  Tab 面板  Enter 选节点  t/T 测速  S 排序  / 过滤  ? 帮助",
        Page::Profiles => {
            " j/k 移动  i 添加  f 刷新用量  u 更新  Enter 切换  n 改名  e URL  d 删除  ? 帮助"
        }
        Page::Connections => {
            " j/k 移动  Enter 详情  S 排序  / 过滤  x 关闭  d 关闭过滤  D 全关  ? 帮助"
        }
        Page::Rules => " j/k 移动  / 过滤  Enter 命中详情  p 规则源  u 更新源  ? 帮助",
        Page::Logs => " j/k 滚动  / 搜索  L 级别  空格 暂停  g/G 首尾  ? 帮助",
        Page::Tools => " j/k 移动  Enter 执行 / 编辑  m 模式  ? 帮助",
    };
    mayon_ui::footer(frame, chunks[3], hint, &format!(" {}", app.status));
    if app.help {
        help(frame, app);
    }
    if let Some(dialog) = &app.dialog {
        dialog_view(frame, dialog, app.detail_scroll);
    }
}
fn overview(frame: &mut Frame, app: &App, area: Rect) {
    let sections = Layout::vertical([
        Constraint::Length(7),
        Constraint::Length(8),
        Constraint::Min(5),
    ])
    .split(area);
    let mut state = vec![
        Line::from(vec![
            blue("  ● 运行中"),
            muted(format!("  {} · {}", app.version, app.config.mode)),
        ]),
        Line::from(format!(
            "  TUN {}   {}{}",
            if app.config.tun.enable {
                "开启"
            } else {
                "关闭"
            },
            "系统代理未设置 · 7 工具 / 设置",
            ""
        )),
        Line::from(format!(
            "  {} 条连接{}   内核连接内存 {}",
            app.connections.len(),
            if app.connections_live {
                ""
            } else {
                "（流已断开）"
            },
            bytes(app.memory)
        )),
        Line::from(clip(
            &format!("  {}", app.chain()),
            area.width.saturating_sub(2) as usize,
        )),
    ];
    if app.config.mode == "rule" {
        if let Some(group) = app.group_names.iter().find(|n| n.as_str() != "GLOBAL") {
            state.push(Line::from(muted(clip(
                &format!(
                    "  参考组：{group} → {}",
                    app.proxies[group].now.as_deref().unwrap_or("按策略选择")
                ),
                area.width.saturating_sub(2) as usize,
            ))));
        }
    }
    pane(frame, sections[0], " 代理状态与出口 ".into(), state);
    let traffic = sections[1];
    frame.render_widget(
        Block::default()
            .style(base())
            .borders(ratatui::widgets::Borders::ALL)
            .border_style(Style::default().fg(BORDER))
            .title(" 最近 60 秒 · 独立纵轴 "),
        traffic,
    );
    let inner = traffic.inner(ratatui::layout::Margin::new(2, 1));
    let halves =
        Layout::horizontal([Constraint::Percentage(50), Constraint::Percentage(50)]).split(inner);
    for (index, a) in halves.iter().enumerate() {
        let series: Vec<u64> = app
            .history
            .iter()
            .map(|t| if index == 0 { t.0 } else { t.1 })
            .collect();
        let speed = app
            .traffic
            .as_ref()
            .map(|t| bytes(if index == 0 { t.up } else { t.down }))
            .map(|s| format!("{s}/s"))
            .unwrap_or_else(|| "--".into());
        frame.render_widget(
            Paragraph::new(format!(
                "{} {speed}",
                if index == 0 {
                    "↑ 上传"
                } else {
                    "↓ 下载"
                }
            ))
            .style(base().fg(if index == 0 { BLUE } else { GREEN })),
            Rect::new(a.x, a.y, a.width, 1),
        );
        frame.render_widget(
            Sparkline::default()
                .data(&series)
                .style(Style::default().fg(if index == 0 { BLUE } else { GREEN })),
            Rect::new(
                a.x,
                a.y + 1,
                a.width.saturating_sub(1),
                a.height.saturating_sub(2),
            ),
        );
        frame.render_widget(
            Paragraph::new(format!(
                "本次内核累计 {}",
                bytes(if index == 0 {
                    app.totals.0
                } else {
                    app.totals.1
                })
            ))
            .style(base().fg(MUTED)),
            Rect::new(a.x, a.y + a.height.saturating_sub(1), a.width, 1),
        );
    }
    let current = app.store.items.iter().find(|i| i.uid == app.store.current);
    let text = match current {
        Some(item) => {
            let usage = item
                .uid
                .as_ref()
                .and_then(|id| app.usage.get(id))
                .copied()
                .or(item.extra);
            let mut text = vec![Line::from(blue(format!(
                "  {}",
                item.name.as_deref().unwrap_or("未命名订阅")
            )))];
            text.extend(usage_lines(usage, area.width.saturating_sub(5) as usize));
            text
        }
        None => vec![
            Line::from("  尚无当前订阅 · 3 订阅 → i 导入"),
            Line::from(muted(
                "  订阅提供节点和规则。粘贴服务商提供的订阅链接添加。",
            )),
        ],
    };
    pane(
        frame,
        sections[2],
        " 当前订阅 · 3 查看所有订阅 ".into(),
        text,
    );
}
fn proxies(frame: &mut Frame, app: &App, area: Rect) {
    let columns =
        Layout::horizontal([Constraint::Percentage(32), Constraint::Percentage(68)]).split(area);
    let mut groups = Vec::new();
    for i in visible(columns[0], app.group, app.group_names.len(), 2) {
        let n = &app.group_names[i];
        let p = &app.proxies[n];
        let selected = i == app.group;
        groups.push(selected_line(
            vec![
                marker(selected),
                Span::raw(clip(n, columns[0].width.saturating_sub(3) as usize)),
            ],
            selected,
        ));
        groups.push(Line::from(muted(clip(
            &format!(
                "  {} · {}",
                group_label(&p.kind),
                p.now.as_deref().unwrap_or("按策略")
            ),
            columns[0].width.saturating_sub(2) as usize,
        ))));
    }
    pane(
        frame,
        columns[0],
        format!(" 代理组 {} ", app.group_names.len()),
        groups,
    );
    let mut nodes = Vec::new();
    let width = columns[1].width.saturating_sub(16) as usize;
    for i in visible(columns[1], app.node, app.node_names.len(), 1) {
        let name = &app.node_names[i];
        let n = clip(name, width);
        let pad = width.saturating_sub(n.width());
        let (label, color) = match app.delay(name) {
            Some(Some(d)) => (
                format!("{d}ms"),
                if d >= app.opts.settings.timeout_ms {
                    RED
                } else {
                    delay_color(Some(d))
                },
            ),
            Some(None) => ("超时".into(), RED),
            None => ("--".into(), MUTED),
        };
        nodes.push(selected_line(
            vec![
                marker(i == app.node),
                Span::styled(
                    if app.current_node() == Some(name) {
                        "● "
                    } else {
                        "  "
                    },
                    Style::default().fg(CYAN),
                ),
                Span::raw(n),
                Span::raw(" ".repeat(pad + 1)),
                Span::styled(label, Style::default().fg(color)),
            ],
            i == app.node,
        ));
    }
    if nodes.is_empty() {
        nodes.push(Line::from(muted(" 无匹配节点 · Esc 清除过滤")));
    }
    let measuring = app
        .measuring
        .map(|(n, t)| format!(" · 测速 {n}/{t}"))
        .unwrap_or_default();
    pane(
        frame,
        columns[1],
        title(
            app,
            &format!(
                "节点 {} · {}{}{}",
                app.node_names.len(),
                app.sort.label(),
                if app.hide_timeout {
                    " · 隐藏超时"
                } else {
                    ""
                },
                measuring
            ),
            columns[1],
        ),
        nodes,
    );
}
pub fn group_label(kind: &str) -> &'static str {
    match kind {
        "Selector" => "↦ 手动选择",
        "URLTest" => "↯ 自动选择",
        "Fallback" => "↪ 故障转移",
        "LoadBalance" => "⇄ 负载均衡",
        "Relay" => "⇢ 串联",
        _ => "◇ 代理组",
    }
}
fn usage_lines(usage: Option<Usage>, width: usize) -> Vec<Line<'static>> {
    let Some(u) = usage else {
        return vec![Line::from(muted("  用量未知 · 3 订阅 → f 读取用量响应头"))];
    };
    let bar_width = width.saturating_sub(12).clamp(4, 36);
    let progress = u.progress().unwrap_or(0.0);
    let fill = (bar_width as f64 * progress).round() as usize;
    let total = if u.total == 0 {
        "未知".into()
    } else {
        bytes(u.total)
    };
    let expiry = u
        .expires_at()
        .map(|d| d.format("%Y-%m-%d").to_string())
        .unwrap_or_else(|| "未知 / 不限".into());
    let days = u
        .expires_at()
        .map(|d| (d - chrono::Local::now()).num_days());
    let warning = days.is_some_and(|d| d <= 7);
    vec![
        Line::from(vec![
            Span::raw("  "),
            Span::styled(
                format!("{}{}", "━".repeat(fill), "─".repeat(bar_width - fill)),
                Style::default().fg(if progress >= 0.9 { YELLOW } else { BLUE }),
            ),
            muted(if u.total > 0 {
                format!(" {:>3.0}% 已用", progress * 100.0)
            } else {
                " 配额未知".into()
            }),
        ]),
        Line::from(muted(clip(
            &format!(
                "  已用 {} / {total} · 剩余 {}",
                bytes(u.used_bytes()),
                u.remaining_bytes()
                    .map(bytes)
                    .unwrap_or_else(|| "未知".into())
            ),
            width,
        ))),
        Line::from(Span::styled(
            clip(
                &format!(
                    "  到期 {expiry}{}",
                    days.map(|d| if d < 0 {
                        " · 已到期".into()
                    } else {
                        format!(" · 剩余 {d} 天")
                    })
                    .unwrap_or_default()
                ),
                width,
            ),
            Style::default().fg(if warning { YELLOW } else { MUTED }),
        )),
    ]
}
fn profiles(frame: &mut Frame, app: &App, area: Rect) {
    let mut lines = Vec::new();
    for i in visible(area, app.profile, app.store.items.len(), 5) {
        let item = &app.store.items[i];
        let current = item
            .uid
            .as_ref()
            .is_some_and(|id| Some(id) == app.store.current.as_ref());
        let width = area.width.saturating_sub(4) as usize;
        lines.push(selected_line(
            vec![
                marker(i == app.profile),
                blue(if current { "● " } else { "  " }),
                Span::raw(clip(
                    &format!("{}{}", item.name.as_deref().unwrap_or("未命名订阅"), ""),
                    width.saturating_sub(3),
                )),
            ],
            i == app.profile,
        ));
        let usage = item
            .uid
            .as_ref()
            .and_then(|id| app.usage.get(id))
            .copied()
            .or(item.extra);
        let mut u = usage_lines(usage, width);
        while u.len() < 3 {
            u.push(Line::from(""));
        }
        lines.extend(u);
        let count = app
            .native_store
            .items
            .get(i)
            .map(|s| format!("{}（配置内）", s.nodes))
            .unwrap_or_else(|| "未知".into());
        lines.push(Line::from(muted(clip(
            &format!(
                "  节点 {count} · 上次更新 {}",
                item.updated_at()
                    .map(|d| d.format("%m-%d %H:%M").to_string())
                    .unwrap_or_else(|| "未知".into())
            ),
            width,
        ))));
    }
    if app.store.items.is_empty() {
        lines = vec![
            Line::from(""),
            Line::from(blue("  还没有订阅 · i 导入")),
            Line::from(""),
            Line::from("  1. 向服务商获取订阅链接"),
            Line::from("  2. 按 i 粘贴订阅链接，下载并校验后添加"),
            Line::from("  3. 回到 TUI 自动刷新，再到 2 代理选择节点"),
            Line::from(""),
            Line::from(muted("  订阅不会自动启动服务；准备好后 s 手动启动。")),
        ];
    }
    pane(
        frame,
        area,
        if app.native_busy {
            " 订阅 · 下载 / 校验 / 应用中… ".into()
        } else {
            " 订阅 · ● 当前 · 仅保存在本机私有目录 ".into()
        },
        lines,
    );
}
fn connections(frame: &mut Frame, app: &App, area: Rect) {
    let mut lines = Vec::new();
    for i in visible(area, app.connection, app.connection_view.len(), 2) {
        let c = &app.connections[app.connection_view[i]];
        let selected = i == app.connection;
        let host = if c.metadata.host.is_empty() {
            &c.metadata.destination_ip
        } else {
            &c.metadata.host
        };
        let right = format!(
            "{} /s  {}",
            app.rates
                .get(&c.id)
                .copied()
                .map(bytes)
                .unwrap_or_else(|| "--".into()),
            age(&c.start)
        );
        let width = area.width.saturating_sub(4) as usize;
        let left_width = width.saturating_sub(right.width() + 2);
        let left = clip(
            &format!("{host}:{}", c.metadata.destination_port),
            left_width,
        );
        lines.push(selected_line(
            vec![
                marker(selected),
                Span::raw(left.clone()),
                Span::raw(" ".repeat(left_width.saturating_sub(left.width()) + 1)),
                blue(right),
            ],
            selected,
        ));
        lines.push(Line::from(muted(clip(
            &format!(
                "  {} · {} → {} · ↑{} ↓{}",
                c.metadata.process,
                c.rule,
                c.chains.join(" → "),
                bytes(c.upload),
                bytes(c.download)
            ),
            width,
        ))));
    }
    if lines.is_empty() {
        lines.push(Line::from(muted(" 暂无匹配连接 · Esc 清除过滤")));
    }
    pane(
        frame,
        area,
        title(
            app,
            &format!(
                "活动连接 {}/{} · {} · {}",
                app.connection_view.len(),
                app.connections.len(),
                ["速率", "总量", "时长", "主机"][app.connection_sort],
                if app.connections_live {
                    "实时"
                } else {
                    "流已断开"
                }
            ),
            area,
        ),
        lines,
    );
}
fn age(start: &str) -> String {
    chrono::DateTime::parse_from_rfc3339(start)
        .ok()
        .map(|d| {
            let s = (chrono::Utc::now() - d.with_timezone(&chrono::Utc))
                .num_seconds()
                .max(0);
            if s < 60 {
                format!("{s}s")
            } else if s < 3600 {
                format!("{}m", s / 60)
            } else {
                format!("{}h", s / 3600)
            }
        })
        .unwrap_or_else(|| "--".into())
}
fn providers(frame: &mut Frame, app: &App, area: Rect) {
    let map = if app.page == Page::Rules {
        &app.rule_providers
    } else {
        &app.providers
    };
    let mut lines = Vec::new();
    for i in visible(area, app.provider, app.provider_view.len(), 2) {
        let n = &app.provider_view[i];
        let p = &map[n];
        let selected = i == app.provider;
        lines.push(selected_line(
            vec![
                marker(selected),
                Span::raw(clip(
                    &format!("{n} · {} · {}", p.vehicle_type, p.kind),
                    area.width.saturating_sub(4) as usize,
                )),
            ],
            selected,
        ));
        lines.push(Line::from(muted(clip(
            &format!(
                "  {} 项 · 更新 {}",
                if app.page == Page::Rules {
                    p.rule_count as usize
                } else {
                    p.proxies.len()
                },
                if p.updated_at.is_empty() || p.updated_at.starts_with("0001-") {
                    "内核未提供"
                } else {
                    &p.updated_at
                }
            ),
            area.width.saturating_sub(2) as usize,
        ))));
    }
    if lines.is_empty() {
        lines.push(Line::from(muted(
            " 无匹配 provider · p 返回 · Esc 清除过滤",
        )));
    }
    pane(
        frame,
        area,
        title(
            app,
            if app.page == Page::Rules {
                "规则源 · u 更新 / p 返回"
            } else {
                "节点源 · t 健康检查 / u 更新 / p 返回"
            },
            area,
        ),
        lines,
    );
}
fn rules(frame: &mut Frame, app: &App, area: Rect) {
    let mut lines = Vec::new();
    for i in visible(area, app.rule, app.rule_view.len(), 2) {
        let r = &app.rules[app.rule_view[i]];
        let selected = i == app.rule;
        lines.push(selected_line(
            vec![
                marker(selected),
                Span::raw(clip(
                    &format!("{}  {}", r.kind, r.payload),
                    area.width.saturating_sub(4) as usize,
                )),
            ],
            selected,
        ));
        let hits = r
            .extra
            .as_ref()
            .map(|e| format!("命中 {} 次", e.hit_count))
            .unwrap_or_else(|| {
                let count = app
                    .connections
                    .iter()
                    .filter(|c| c.rule == r.kind && c.rule_payload == r.payload)
                    .count();
                format!("当前匹配连接 {count}（非累计命中）")
            });
        lines.push(Line::from(muted(clip(
            &format!("  → {} · {hits}", r.proxy),
            area.width.saturating_sub(2) as usize,
        ))));
    }
    if lines.is_empty() {
        lines.push(Line::from(muted(" 无匹配规则")));
    }
    pane(
        frame,
        area,
        title(
            app,
            &format!(
                "规则 {}/{} · p 规则源",
                app.rule_view.len(),
                app.rules.len()
            ),
            area,
        ),
        lines,
    );
}
fn logs(frame: &mut Frame, app: &App, area: Rect) {
    let mut lines = Vec::new();
    for i in visible(area, app.log, app.log_view.len(), 1) {
        let l = &app.logs[app.log_view[i]];
        let color = match l.level.as_str() {
            "error" => RED,
            "warning" | "warn" => YELLOW,
            "debug" => MUTED,
            _ => GREEN,
        };
        lines.push(selected_line(
            vec![
                marker(i == app.log),
                Span::styled(format!("{:<7}", l.level), Style::default().fg(color)),
                Span::raw(clip(&l.payload, area.width.saturating_sub(12) as usize)),
            ],
            i == app.log,
        ));
    }
    if lines.is_empty() {
        lines.push(Line::from(muted(" 等待匹配日志 · L 切级别 · / 搜索")));
    }
    pane(
        frame,
        area,
        title(
            app,
            &format!(
                "日志 {} · {}+ · {}",
                app.log_view.len(),
                ["debug", "info", "warning", "error"][app.log_level],
                if app.logs_paused {
                    "已暂停（丢弃新日志）"
                } else if app.logs_live {
                    "实时 · 最多 2000 条"
                } else {
                    "等待日志流"
                }
            ),
            area,
        ),
        lines,
    );
}
fn tools(frame: &mut Frame, app: &App, area: Rect) {
    let mut entries = vec![
        (
            "清空 fake-ip 缓存".to_string(),
            "移除 DNS 虚拟地址映射".to_string(),
        ),
        ("清空 DNS 缓存".into(), "下次解析时重新查询".into()),
        (
            "更新 GeoIP / GeoSite".into(),
            "通过 mihomo 下载并重载，数据保存在私有目录".into(),
        ),
    ];
    {
        let s = &app.native_settings;
        entries.extend([
            (
                format!(
                    "TUN                 {}",
                    if s.tun { "开启" } else { "关闭" }
                ),
                "接管流量；关闭后只保留显式代理端口".into(),
            ),
            (
                format!("模式                {}", s.mode),
                "rule / global / direct".into(),
            ),
            (
                format!("IPv6                {}", s.ipv6),
                "同时调整 DNS IPv6".into(),
            ),
            (
                format!("allow-lan           {}", s.allow_lan),
                "默认 false，仅本机访问；开启将监听所有地址".into(),
            ),
            (
                format!("日志级别            {}", s.log_level),
                "Enter 循环 info / debug / warning / error / silent".into(),
            ),
            (
                format!("mixed-port          {}", s.mixed_port),
                "Enter 编辑；设置持久保存并立即重载".into(),
            ),
        ]);
    }
    let mut lines = vec![];
    for i in visible(area, app.tool, app.tools_len(), 3) {
        let (name, detail) = &entries[i];
        lines.push(selected_line(
            vec![marker(app.tool == i), Span::raw(name.clone())],
            app.tool == i,
        ));
        lines.push(Line::from(muted(clip(
            &format!("  {detail}"),
            area.width.saturating_sub(3) as usize,
        ))));
        lines.push(Line::from(""));
    }
    pane(
        frame,
        area,
        " 工具 / 设置 · Enter 应用 · 保存后重启仍保留 ".into(),
        lines,
    );
}
fn modal(frame: &mut Frame, title: &str, text: Vec<Line<'static>>, height: u16, scroll: u16) {
    let a = mayon_ui::centered(frame.area(), 80, height);
    frame.render_widget(Clear, a);
    frame.render_widget(
        Paragraph::new(text)
            .style(base().bg(SURFACE))
            .block(block(title.to_string()))
            .wrap(Wrap { trim: false })
            .scroll((scroll, 0)),
        a,
    );
}
fn help(frame: &mut Frame, app: &App) {
    let body = match Page::ALL[app.help_page] {
        Page::Overview => "mayon-clash.service 运行 mihomo，TUI 管配置与启停。\n服务不随开机启动：先 3 → i 添加，再 s 启动；X 确认关闭。\nTUN 接管 IP 流量，DNS hijack 交给内核；7 工具可调整并持久保存。\n不设置系统代理：TUN 已接管流量；显式程序可用本机 mixed-port。\nrule 按规则分流；global 全部走 GLOBAL；direct 绕过代理。\n关闭服务后 TUN 消失、网络直连；退出 TUI 本身不会关闭服务。",
        Page::Proxies => "组是节点的选择策略。Tab / h/l 切组与节点面板，Enter 选中。\n↦ Selector 手动；↯ URLTest 自动最快；↪ Fallback 首个可用。\nURLTest/Fallback 允许临时手动指定；T 整组测速会恢复自动选择。\n⇄ LoadBalance 按连接分配，⇢ Relay 串联；无固定节点，不能手动选。\nt 单测 · T 内核组测 · b 测过滤列表（配置并发）· Esc 取消本地队列。\nS 默认/延迟/名称排序 · H 隐藏超时 · c 跳当前 · / 拼音首字母/中英模糊过滤。\np 节点源：t 健康检查，u 更新（源内并发与测试 URL 由内核管理）。",
        Page::Profiles => "i 添加：粘贴 URL（仅显示脱敏地址），Tab 可选名称，Enter 下载校验。\nEnter 切换 · u 单个更新 · U 全部更新 · n 重命名 · e 编辑 URL。\nd 确认删除；当前项须先切换。用量、到期、配置内节点数显示于列表。\n先直连，失败且内核运行时经 mixed-port 重试；默认每 24h 更新。\nTUI 打开且内核运行时后台检查更新间隔；链接只存在私有 0600 索引。",
        Page::Connections => "连接是应用访问目标的一次会话；规则决定它走哪个组与节点。\nS 按速率/总量/时长/主机排序 · / 主机、IP、进程、规则、链路过滤。\nEnter 查看目标、规则、链路、进程、开始时间；j/k 可滚动详情。\nx 关闭单个 · d 关闭过滤结果快照 · D 全部关闭，均先确认。\n速率由连续快照差值得到，首帧和断流时未知；WebSocket 每秒更新。",
        Page::Rules => "规则从上至下决定目标的出站策略；/ 搜索类型、内容或策略。\nEnter 看完整规则及命中；内核提供累计命中时优先显示。\n否则显示当前连接匹配数，并非历史累计。p 查看规则源，u 更新。\n规则源属于当前内核配置。",
        Page::Logs => "日志流来自当前内核，最多保留 2000 条，仅在进程内存。\nL 循环 debug/info/warning/error 最低级别 · / 搜索。\n空格暂停（丢弃新日志，界面停止追随）；再次空格恢复。\nj/k、PageUp/PageDown、g/G 滚动；G 回到追随。\n链接与常见凭据字段会隐藏；本程序不将日志写盘。",
        Page::Tools => "Enter 选择工具并确认，Esc 取消；联网与文件错误会显示在底部。\nfake-ip 缓存存虚拟地址映射，DNS 缓存存解析结果。\nGeoIP/GeoSite 更新由内核处理；Nix store 资源只读时可能失败。\nm 循环 rule/global/direct。TUN 设置可在本页修改。",
    };
    let mut text = vec![
        Line::from(""),
        Line::from(blue(format!(
            "  {} · {}",
            app.help_page + 1,
            TABS[app.help_page]
        ))),
        Line::from(""),
    ];
    text.extend(body.lines().map(|s| Line::from(format!("  {s}"))));
    text.push(Line::from(""));
    text.push(Line::from(muted(
        "  1–7 / ←→ 分页 · j/k / 方向键移动 · g/G 首尾 · PgUp/PgDn 翻页",
    )));
    text.push(Line::from(blue(
        "  Tab 下一页 · ? / Esc 返回 · 鼠标滚轮可切帮助页",
    )));
    modal(frame, " 新手指引与按页帮助 ", text, 23, 0);
}
fn dialog_view(frame: &mut Frame, dialog: &Dialog, scroll: u16) {
    match dialog {
        Dialog::Edit {
            title,
            value,
            action,
        } => modal(
            frame,
            title,
            vec![
                Line::from(""),
                Line::from(blue(format!(
                    "  {}▏",
                    if matches!(action, crate::app::EditAction::Url(_)) {
                        crate::native::redact_url(value)
                    } else {
                        clip(value, 68)
                    }
                ))),
                Line::from(""),
                Line::from(muted("  Enter 保存 · Esc 取消")),
            ],
            9,
            0,
        ),
        Dialog::Confirm { body, .. } => modal(
            frame,
            " 确认操作 ",
            vec![
                Line::from(""),
                Line::from(format!("  {body}")),
                Line::from(""),
                Line::from(blue("  Enter / y 确认 · Esc / n 取消")),
            ],
            9,
            0,
        ),
        Dialog::Import { url, name, field } => modal(
            frame,
            " 导入订阅 ",
            vec![
                Line::from(""),
                Line::from(blue(format!(
                    "  {}URL：{}",
                    if !field { "▏" } else { " " },
                    crate::native::redact_url(url)
                ))),
                Line::from(""),
                Line::from(format!(
                    "  {}名称：{}",
                    if *field { "▏" } else { " " },
                    clip(name, 50)
                )),
                Line::from(""),
                Line::from(muted("  名称留空：响应头标题 / 文件名，再回退主机名。")),
                Line::from(muted("  URL 仅保存到私有索引，不写日志。")),
                Line::from(""),
                Line::from(blue("  Tab 切字段 · Enter 下载并校验 · Esc 取消")),
            ],
            13,
            0,
        ),
        Dialog::Detail(text) => modal(
            frame,
            " 详情 · j/k 滚动 / Esc 返回 ",
            text.lines().map(|s| Line::from(format!(" {s}"))).collect(),
            22,
            scroll,
        ),
    }
    let height = match dialog {
        Dialog::Confirm { .. } | Dialog::Edit { .. } => 9,
        Dialog::Import { .. } => 13,
        Dialog::Detail(_) => 22,
    };
    let a = mayon_ui::centered(frame.area(), 80, height);
    let buttons = Layout::horizontal([Constraint::Percentage(50), Constraint::Percentage(50)])
        .split(Rect::new(
            a.x + 1,
            a.bottom().saturating_sub(2),
            a.width.saturating_sub(2),
            1,
        ));
    let primary = match dialog {
        Dialog::Detail(_) => " [ Enter 返回 ]",
        Dialog::Import { .. } => " [ Enter 添加订阅 ]",
        Dialog::Edit { .. } => " [ Enter 保存 ]",
        Dialog::Confirm { .. } => " [ Enter 确认 ]",
    };
    frame.render_widget(Paragraph::new(primary).style(base().fg(BLUE)), buttons[0]);
    frame.render_widget(
        Paragraph::new(" [ Esc 返回 / 取消 ]").style(base().fg(MUTED)),
        buttons[1],
    );
}
pub fn dialog_click(
    size: Size,
    dialog: &Dialog,
    x: u16,
    y: u16,
) -> Option<crossterm::event::KeyCode> {
    use crossterm::event::KeyCode;
    let height = match dialog {
        Dialog::Confirm { .. } | Dialog::Edit { .. } => 9,
        Dialog::Import { .. } => 13,
        Dialog::Detail(_) => 22,
    };
    let a = mayon_ui::centered(Rect::new(0, 0, size.width, size.height), 80, height);
    if let Dialog::Import { field, .. } = dialog {
        if x > a.x && x < a.right() && ((y == a.y + 2 && *field) || (y == a.y + 4 && !field)) {
            return Some(KeyCode::Tab);
        }
    }
    if y == a.bottom().saturating_sub(2) && x > a.x && x < a.right().saturating_sub(1) {
        Some(if x < a.x + a.width / 2 {
            KeyCode::Enter
        } else {
            KeyCode::Esc
        })
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::app::Action;
    #[test]
    fn tabs_and_modal_actions_share_geometry() {
        for i in 0..7 {
            assert_eq!(tab_at(2 + i * 11), Some((b'1' + i as u8) as char));
        }
        let size = Size::new(90, 34);
        for dialog in [
            Dialog::Confirm {
                action: Action::Tool(0),
                body: "test".into(),
            },
            Dialog::Import {
                url: String::new(),
                name: String::new(),
                field: false,
            },
            Dialog::Detail("test".into()),
        ] {
            let height = match &dialog {
                Dialog::Confirm { .. } | Dialog::Edit { .. } => 9,
                Dialog::Import { .. } => 13,
                Dialog::Detail(_) => 22,
            };
            let a = mayon_ui::centered(Rect::new(0, 0, 90, 34), 80, height);
            assert_eq!(
                dialog_click(size, &dialog, a.x + 2, a.bottom() - 2),
                Some(crossterm::event::KeyCode::Enter)
            );
            assert_eq!(
                dialog_click(size, &dialog, a.right() - 2, a.bottom() - 2),
                Some(crossterm::event::KeyCode::Esc)
            );
        }
    }
}
