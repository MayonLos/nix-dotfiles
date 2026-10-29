//! Pure rendering: terminal-cell widths and scrolling are handled explicitly.
use crate::{
    app::{App, Dialog, Page},
    theme::*,
};
use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::Style,
    text::{Line, Span},
    widgets::{Block, Clear, List, ListItem, ListState, Paragraph, Wrap},
    Frame,
};

use mayon_ui::{base, blue, marker, muted};
fn block(title: String, focused: bool) -> Block<'static> {
    mayon_ui::block(title, focused)
}
fn row(lines: Vec<Line<'static>>, selected: bool) -> ListItem<'static> {
    ListItem::new(lines).style(if selected {
        base().bg(SELECTION)
    } else {
        base()
    })
}
pub fn tab_at(column: u16) -> Option<char> {
    use unicode_width::UnicodeWidthStr;
    let mut start = 1;
    for (key, title) in [('1', "1 代理"), ('2', "2 订阅"), ('3', "3 连接")] {
        let width = title.width() as u16 + 2;
        if (start..start + width).contains(&column) {
            return Some(key);
        }
        start += width + 2;
    }
    None
}
pub fn draw(frame: &mut Frame, app: &mut App) {
    let area = frame.area();
    frame.render_widget(Block::default().style(base()), area);
    if area.width < 44 || area.height < 12 {
        frame.render_widget(
            Paragraph::new("请将终端放大至至少 44 × 12\nq 退出")
                .style(base())
                .wrap(Wrap { trim: false }),
            area,
        );
        return;
    }
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(1),
            Constraint::Length(2),
            Constraint::Min(4),
            Constraint::Length(2),
        ])
        .split(area);
    let mode = match app.config.mode.as_str() {
        "rule" => "规则",
        "global" => "全局",
        "direct" => "直连",
        _ => "--",
    };
    let traffic = app
        .traffic
        .map(|(up, down)| format!("↑{} ↓{}", bytes(up), bytes(down)))
        .unwrap_or_else(|| "↑-- ↓--".into());
    let header = if !app.online {
        " 󰒍 Clash · 未运行".into()
    } else if area.width >= 100 {
        format!(
            " 󰒍 Clash · 运行  ·  {mode}  ·  TUN {}  ·  {traffic}  ·  {} 连接  ·  {}",
            if app.config.tun.enable { "on" } else { "off" },
            app.connections.len(),
            app.version
        )
    } else {
        format!(
            " 󰒍 运行 {mode} TUN:{}  {traffic}  {} conn {}",
            if app.config.tun.enable { "on" } else { "off" },
            app.connections.len(),
            app.version.replace("Meta ", "")
        )
    };
    mayon_ui::status(frame, chunks[0], &header);
    let page = match app.page {
        Page::Proxies => 0,
        Page::Profiles => 1,
        Page::Connections => 2,
    };
    frame.render_widget(
        Paragraph::new(mayon_ui::tabs_line(&["代理", "订阅", "连接"], page)),
        chunks[1],
    );
    if !app.online {
        frame.render_widget(
            Paragraph::new(
                "\n\n  Clash 未运行 · s 启动\n\n  打开 Verge 即启动，退出 Verge 即关闭。",
            )
            .style(base().fg(MUTED))
            .block(block(" Clash ".into(), false)),
            chunks[2],
        );
    } else {
        match app.page {
            Page::Proxies => proxies(frame, app, chunks[2]),
            Page::Profiles => profiles(frame, app, chunks[2]),
            Page::Connections => connections(frame, app, chunks[2]),
        }
    }
    let hint = if !app.online {
        " s 启动 Verge  r 刷新  ? 帮助  q 退出"
    } else {
        match app.page {
            Page::Proxies => " j/k 移动  Tab 面板  Enter 选择  t/T 测速  / 过滤  m 模式  ? 帮助",
            Page::Profiles => " j/k 移动  i 导入  f 刷新用量  u 更新  Enter 切换  o Verge  ? 帮助",
            Page::Connections => " j/k 移动  x 关闭连接  X 关闭 Clash  r 刷新  ? 帮助",
        }
    };
    mayon_ui::footer(frame, chunks[3], hint, &format!(" {}", app.status));
    if app.help {
        help(frame);
    }
    if let Some(dialog) = &app.dialog {
        dialog_view(frame, dialog);
    }
}

fn proxies(frame: &mut Frame, app: &App, area: Rect) {
    let columns =
        Layout::horizontal([Constraint::Percentage(32), Constraint::Percentage(68)]).split(area);
    let groups = app.groups();
    let group_rows: Vec<_> = groups
        .iter()
        .enumerate()
        .map(|(index, name)| {
            let proxy = &app.proxies[name];
            let selected = index == app.group;
            let width = columns[0].width.saturating_sub(5) as usize;
            row(
                vec![
                    Line::from(vec![marker(selected), Span::raw(clip(name, width))]),
                    Line::from(vec![
                        Span::raw("  "),
                        muted(clip(
                            &format!("{} · {}", proxy.kind, proxy.now.as_deref().unwrap_or("--")),
                            width.saturating_sub(1),
                        )),
                    ]),
                ],
                selected,
            )
        })
        .collect();
    let mut state = ListState::default().with_selected((!groups.is_empty()).then_some(app.group));
    frame.render_stateful_widget(
        List::new(group_rows).block(block(
            format!(" 代理组 {} ", groups.len()),
            !app.nodes_focus,
        )),
        columns[0],
        &mut state,
    );
    let nodes = app.nodes();
    let current = app
        .group_name()
        .and_then(|g| app.proxies.get(&g))
        .and_then(|p| p.now.as_deref());
    let node_rows: Vec<_> = nodes
        .iter()
        .enumerate()
        .map(|(index, name)| {
            let selected = index == app.node;
            let (label, color) = match app.delay(name) {
                Some(Some(delay)) => (format!("{delay} ms"), delay_color(Some(delay))),
                Some(None) => ("超时".into(), RED),
                None => ("--".into(), MUTED),
            };
            let width = columns[1].width.saturating_sub(16) as usize;
            let clipped = clip(name, width);
            let pad = width.saturating_sub(unicode_width::UnicodeWidthStr::width(clipped.as_str()));
            row(
                vec![Line::from(vec![
                    marker(selected),
                    Span::styled(
                        if current == Some(name.as_str()) {
                            "● "
                        } else {
                            "  "
                        },
                        Style::default().fg(CYAN),
                    ),
                    Span::raw(clipped),
                    Span::raw(" ".repeat(pad + 1)),
                    Span::styled(label, Style::default().fg(color)),
                ])],
                selected,
            )
        })
        .collect();
    let progress = app
        .measuring
        .map(|(done, total)| format!(" · ⟳ {done}/{total} Esc 取消"))
        .unwrap_or_default();
    let filter = if app.filter.is_empty() && !app.filtering {
        String::new()
    } else {
        format!(" · /{}{}", app.filter, if app.filtering { "▏" } else { "" })
    };
    let title = clip(
        &format!(" 节点 {}{progress}{filter} ", nodes.len()),
        columns[1].width.saturating_sub(2) as usize,
    );
    let mut state = ListState::default().with_selected((!nodes.is_empty()).then_some(app.node));
    frame.render_stateful_widget(
        List::new(node_rows).block(block(title, app.nodes_focus)),
        columns[1],
        &mut state,
    );
    if nodes.is_empty() {
        let inner = Rect {
            x: columns[1].x + 2,
            y: columns[1].y + 2,
            width: columns[1].width.saturating_sub(4),
            height: 2,
        };
        frame.render_widget(
            Paragraph::new("无匹配节点 · Esc 清除过滤").style(Style::default().fg(MUTED)),
            inner,
        );
    }
}

fn profiles(frame: &mut Frame, app: &App, area: Rect) {
    let width = area.width.saturating_sub(6) as usize;
    let rows: Vec<_> = app
        .store
        .items
        .iter()
        .enumerate()
        .map(|(index, item)| {
            let selected = index == app.profile;
            let current = item
                .uid
                .as_ref()
                .is_some_and(|uid| Some(uid) == app.store.current.as_ref());
            let refreshed = item
                .uid
                .as_ref()
                .and_then(|uid| app.usage.get(uid))
                .copied();
            let usage = refreshed.or(item.extra);
            let mut lines = vec![Line::from(vec![
                marker(selected),
                Span::styled(if current { "● " } else { "  " }, Style::default().fg(CYAN)),
                Span::styled(
                    clip(
                        item.name.as_deref().unwrap_or("未命名订阅"),
                        width.saturating_sub(12),
                    ),
                    Style::default().fg(BRIGHTFG),
                ),
                blue(if current { "  当前" } else { "" }),
            ])];
            if let Some(usage) = usage {
                let fraction = usage.progress();
                let count = width.saturating_sub(10).min(28);
                let fill = (fraction.unwrap_or(0.0) * count as f64).round() as usize;
                lines.push(Line::from(vec![
                    Span::raw("   "),
                    Span::styled("━".repeat(fill), Style::default().fg(BLUE)),
                    Span::styled("─".repeat(count - fill), Style::default().fg(BORDER)),
                    muted(
                        fraction
                            .map(|p| format!("  {:.0}%", p * 100.0))
                            .unwrap_or_else(|| "  无配额".into()),
                    ),
                ]));
                let total = if usage.total > 0 {
                    bytes(usage.total)
                } else {
                    "未知".into()
                };
                let remaining = usage
                    .remaining_bytes()
                    .map(bytes)
                    .unwrap_or_else(|| "未知".into());
                lines.push(Line::from(muted(clip(
                    &format!(
                        "   已用 {} / {} · 剩余 {}",
                        bytes(usage.used_bytes()),
                        total,
                        remaining
                    ),
                    width,
                ))));
                let expiry = usage
                    .expires_at()
                    .map(|d| d.format("%Y-%m-%d").to_string())
                    .unwrap_or_else(|| "未知 / 不限".into());
                let updated = item
                    .updated_at()
                    .map(|d| d.format("%m-%d %H:%M").to_string())
                    .unwrap_or_else(|| "未知".into());
                lines.push(Line::from(muted(clip(
                    &format!(
                        "   到期 {expiry} · 更新 {updated}{}",
                        if refreshed.is_some() {
                            " · 实时用量"
                        } else {
                            ""
                        }
                    ),
                    width,
                ))));
            } else {
                lines.push(Line::from(""));
                lines.push(Line::from(muted("   无用量信息 · f 从订阅响应头刷新")));
                lines.push(Line::from(muted(format!(
                    "   类型 {}",
                    item.kind.as_deref().unwrap_or("unknown")
                ))));
            }
            lines.push(Line::from(""));
            if selected {
                lines[0] = lines[0].clone().style(base().bg(SELECTION));
            }
            row(lines, false)
        })
        .collect();
    let mut state = ListState::default().with_selected((!rows.is_empty()).then_some(app.profile));
    frame.render_stateful_widget(
        List::new(rows).block(block(
            " 󰑓 Verge 订阅 · 只读快照 / 导入交给 Verge ".into(),
            true,
        )),
        area,
        &mut state,
    );
    if app.store.items.is_empty() {
        frame.render_widget(
            Paragraph::new(
                "无可显示订阅 · r 重读文件 · i 导入\n不会直接改写 Verge 的 profiles.yaml",
            )
            .style(Style::default().fg(MUTED)),
            Rect {
                x: area.x + 3,
                y: area.y + 2,
                width: area.width.saturating_sub(6),
                height: 3,
            },
        );
    }
}

fn connections(frame: &mut Frame, app: &App, area: Rect) {
    let width = area.width.saturating_sub(5) as usize;
    let rows: Vec<_> = app
        .connections
        .iter()
        .enumerate()
        .map(|(index, connection)| {
            let selected = index == app.connection;
            let meta = &connection.metadata;
            let host = if meta.host.is_empty() {
                &meta.destination_ip
            } else {
                &meta.host
            };
            row(
                vec![
                    Line::from(vec![
                        marker(selected),
                        Span::raw(clip(
                            &format!("{}:{}  {}", host, meta.destination_port, meta.network),
                            width,
                        )),
                    ]),
                    Line::from(muted(clip(
                        &format!(
                            "  {} → {}   ↑{} ↓{}",
                            connection.rule,
                            connection.chains.join(" → "),
                            bytes(connection.upload),
                            bytes(connection.download)
                        ),
                        width,
                    ))),
                ],
                selected,
            )
        })
        .collect();
    let mut state =
        ListState::default().with_selected((!rows.is_empty()).then_some(app.connection));
    frame.render_stateful_widget(
        List::new(rows).block(block(
            format!(" 活动连接 {} · x 关闭所选 ", app.connections.len()),
            true,
        )),
        area,
        &mut state,
    );
    if app.connections.is_empty() {
        frame.render_widget(
            Paragraph::new("暂无活动连接").style(Style::default().fg(MUTED)),
            Rect {
                x: area.x + 3,
                y: area.y + 2,
                width: area.width.saturating_sub(6),
                height: 1,
            },
        );
    }
}

fn modal(frame: &mut Frame, width: u16, height: u16) -> Rect {
    let area = frame.area();
    let width = width.min(area.width.saturating_sub(4));
    let height = height.min(area.height.saturating_sub(2));
    let popup = Rect::new(
        area.x + (area.width - width) / 2,
        area.y + (area.height - height) / 2,
        width,
        height,
    );
    frame.render_widget(Clear, popup);
    frame.render_widget(Block::default().style(base().bg(SURFACE)), popup);
    popup
}
fn help(frame: &mut Frame) {
    let popup = modal(frame, 76, 22);
    let text = vec![
        Line::from(blue("  移动与面板")),
        Line::from("  j/k ↑/↓ 选择    g/G 首尾    h/l 或 Tab 切面板"),
        Line::from("  1 代理    2 订阅    3 活动连接    q / Ctrl-C 退出"),
        Line::from(""),
        Line::from(blue("  代理与概览")),
        Line::from("  Enter 切换节点    t 测当前    T 测整组（并发 4）"),
        Line::from("  Esc 取消测速 / 清除过滤    / 中文或英文子串过滤"),
        Line::from("  m 模式轮换：rule → global → direct    r 刷新"),
        Line::from("  s 启动 Verge    X 确认退出 Verge / 关闭 Clash"),
        Line::from(""),
        Line::from(blue("  订阅")),
        Line::from("  i 导入 URL（Tab 输入名称）    f 经代理刷新用量"),
        Line::from("  u 更新 / Enter 切换 → 在 Verge 中完成    o 打开 Verge"),
        Line::from("  用量只存内存；不写 profiles.yaml，不读取密钥"),
        Line::from(""),
        Line::from(blue("  连接")),
        Line::from("  x 立即关闭当前连接    每 2 秒刷新快照"),
        Line::from(""),
        Line::from(muted(concat!(
            "  ? / Esc 关闭帮助    ·    clashtui-mayon ",
            env!("CARGO_PKG_VERSION")
        ))),
    ];
    frame.render_widget(
        Paragraph::new(text)
            .style(base().bg(SURFACE))
            .block(block(" 󰋖 帮助 ".into(), true))
            .wrap(Wrap { trim: false }),
        popup,
    );
}
fn dialog_view(frame: &mut Frame, dialog: &Dialog) {
    match dialog {
        Dialog::Stop => mayon_ui::dialog(
            frame,
            " 关闭 Clash ",
            "向本用户的 Verge GUI 发送 SIGTERM。\nVerge 将复位系统代理、关闭 TUN 并停止内核。\n\nEnter / y 确认 · Esc / n 取消",
        ),
        Dialog::Import { url, name, field } => {
            let popup = modal(frame, 76, 15);
            // URLs are never rendered: tokens may be present even in query strings.
            let masked = if url.is_empty() {
                "输入 http(s) URL（内容隐藏）".into()
            } else {
                format!("{} 个字符 · URL 已隐藏", url.chars().count())
            };
            let lines = vec![
                Line::from(""),
                Line::from(vec![
                    blue(if !field { " ▏URL   " } else { "  URL   " }),
                    Span::raw(masked),
                ]),
                Line::from(""),
                Line::from(vec![
                    blue(if *field { " ▏名称  " } else { "  名称  " }),
                    Span::raw(clip(name, popup.width.saturating_sub(12) as usize)),
                ]),
                Line::from(""),
                Line::from(muted("  Verge 2.4.7 会将完整导入链接写入它自己的日志。")),
                Line::from(muted("  名称留空可直接导入；指定名称需在 Verge 中完成。")),
                Line::from(muted("  本程序不保存 URL，也不读取 API 密钥。")),
                Line::from(""),
                Line::from(blue("  Tab 切字段    Enter 交给 Verge    Esc 取消")),
            ];
            frame.render_widget(
                Paragraph::new(lines)
                    .style(base().bg(SURFACE))
                    .block(block(" 导入订阅 ".into(), true))
                    .wrap(Wrap { trim: false }),
                popup,
            );
        }
        Dialog::Verge { reason } => {
            let popup = modal(frame, 72, 9);
            frame.render_widget(
                Paragraph::new(vec![
                    Line::from(""),
                    Line::from(format!("  {reason}")),
                    Line::from(""),
                    Line::from(muted("  profiles.yaml 仍由 Verge 独占写入。")),
                    Line::from(blue("  Enter / o 在 Verge 中打开    Esc 返回")),
                ])
                .style(base().bg(SURFACE))
                .block(block(" 在 Verge 中完成 ".into(), true))
                .wrap(Wrap { trim: false }),
                popup,
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::app::Options;
    #[test]
    fn tabs_use_unicode_cell_ranges() {
        assert_eq!(tab_at(2), Some('1'));
        assert_eq!(tab_at(12), Some('2'));
        assert_eq!(tab_at(22), Some('3'));
    }
    #[test]
    fn renders_chinese_at_wide_and_narrow_sizes() {
        for width in [48, 80, 132] {
            let mut app = App::new(Options {
                socket: "/nonexistent.sock".into(),
                profiles: "/nonexistent.yaml".into(),
                test_url: "http://example.invalid".into(),
                usage_proxy: None,
                no_verge: true,
                lifecycle: crate::lifecycle::Lifecycle::default(),
            })
            .unwrap();
            app.online = true;
            app.proxies.insert(
                "香港 选择".into(),
                crate::api::Proxy {
                    all: vec!["香港 节点".into()],
                    ..Default::default()
                },
            );
            for page in [Page::Proxies, Page::Profiles, Page::Connections] {
                app.page = page;
                let mut terminal =
                    ratatui::Terminal::new(ratatui::backend::TestBackend::new(width, 24)).unwrap();
                terminal.draw(|f| draw(f, &mut app)).unwrap();
                let text = terminal
                    .backend()
                    .buffer()
                    .content()
                    .iter()
                    .map(|c| c.symbol())
                    .collect::<String>();
                let expected = match page {
                    Page::Proxies => "代理组",
                    Page::Profiles => "订阅",
                    Page::Connections => "活动连接",
                };
                assert!(
                    text.chars()
                        .filter(|c| !c.is_whitespace())
                        .collect::<String>()
                        .contains(expected),
                    "{expected} missing at {width} columns"
                );
                app.online = false;
                terminal.draw(|f| draw(f, &mut app)).unwrap();
                let text = terminal
                    .backend()
                    .buffer()
                    .content()
                    .iter()
                    .map(|c| c.symbol())
                    .collect::<String>();
                assert!(text
                    .chars()
                    .filter(|c| !c.is_whitespace())
                    .collect::<String>()
                    .contains("Clash未运行"));
                app.online = true;
            }
        }
    }
}
