use crate::{
    app::{App, InputKind, BAUDS},
    codec,
    transport::Command,
};
use crossterm::event::{
    self, Event, KeyCode as K, KeyEvent, KeyEventKind, KeyModifiers as M, MouseEventKind,
};
use mayon_ui::{self as ui, theme::*};
use ratatui::{
    layout::{Constraint as C, Layout, Rect},
    style::{Modifier, Style},
    symbols::Marker,
    text::{Line, Span},
    widgets::{Axis, Chart, Dataset, GraphType, Paragraph},
    Frame,
};
use std::{io, time::Duration};

const HELP:&str="1 监视  2 端口  3 参数  4 命令  5 烧录   q 退出\n\nEnter / i 发送输入 · ↑↓ 输入历史 · Esc 取消输入\nx 发送 TEXT/HEX · e 行尾 · F 发送文件（原字节 ≤1MiB）\nt 定时重复上次发送（毫秒；0 停止）\n/ 搜索 · n 下一条 · f 过滤 · 空内容清除\np / Space 暂停跟随 · PgUp/PgDn / 滚轮 回滚 · End 跟随\nv 接收 TEXT/HEX/MIX · T 时间戳 · g UTF-8/GBK\nw 波形开关 · l 日志开关 · c CSV（下次开始日志生效）\nb 常用波特率 · B 自定义 · s 全部参数 · h 高亮词\nd DTR · r RTS · D / R 脉冲100ms（恢复原电平）\n4 命令页：a 收藏 · ↑↓ 选择 · Enter 载入（不立即发送）\n5 烧录页：o 命令 · O 工作目录 · F5 执行 · Esc 取消\n2 端口页：↑↓/鼠标选择 · Enter 连接 · u 主动断开\n\n暂停仍接收/记日志。回滚默认10万行，上限32MiB；满后淘汰最旧行。\n原始 .bin 保留日志开启后的全部接收字节；.log 带时间戳。";

pub fn run(mut app: App) -> io::Result<()> {
    let (mut terminal, _guard) = ui::terminal()?;
    crossterm::execute!(io::stdout(), event::EnableBracketedPaste)?;
    loop {
        app.tick();
        terminal.draw(|f| draw(f, &app))?;
        if event::poll(Duration::from_millis(40))? {
            match event::read()? {
                Event::Key(k) if k.kind != KeyEventKind::Release && key(&mut app, k) => {
                    break;
                }
                Event::Paste(value) => {
                    if let Some(input) = &mut app.input {
                        let remaining = 65536usize.saturating_sub(input.text.len());
                        input.text.extend(value.chars().take(remaining));
                    }
                }
                Event::Mouse(mouse) => match mouse.kind {
                    MouseEventKind::ScrollUp => {
                        if app.page == 0 {
                            app.scroll_up(3);
                        } else {
                            move_selection(&mut app, -1);
                        }
                    }
                    MouseEventKind::ScrollDown => {
                        if app.page == 0 {
                            app.scroll = app.scroll.saturating_sub(3);
                        } else {
                            move_selection(&mut app, 1);
                        }
                    }
                    MouseEventKind::Down(event::MouseButton::Left) => {
                        if mouse.row == 1 {
                            let x = mouse.column;
                            let index = if x < 11 {
                                0
                            } else if x < 22 {
                                1
                            } else if x < 33 {
                                2
                            } else if x < 44 {
                                3
                            } else {
                                4
                            };
                            app.page = index;
                        } else if app.page == 1 && mouse.row >= 5 {
                            app.selected =
                                (mouse.row as usize - 5).min(app.devices.len().saturating_sub(1));
                        }
                    }
                    _ => {}
                },
                _ => {}
            }
        }
    }
    Ok(())
}
fn move_selection(app: &mut App, delta: i32) {
    let (index, len) = match app.page {
        1 => (&mut app.selected, app.devices.len()),
        2 => (&mut app.settings_index, 8),
        3 => (&mut app.favorite_index, app.store.config.favorites.len()),
        _ => return,
    };
    *index = if delta > 0 {
        (*index + 1).min(len.saturating_sub(1))
    } else {
        index.saturating_sub(1)
    };
}
fn key(app: &mut App, k: KeyEvent) -> bool {
    if k.code == K::Char('c') && k.modifiers.contains(M::CONTROL) {
        return true;
    }
    if app.help {
        if matches!(k.code, K::Esc | K::Char('?')) {
            app.help = false;
        }
        return false;
    }
    if let Some(mut input) = app.input.take() {
        match k.code {
            K::Esc => return false,
            K::Enter => {
                if let Err(error) = app.submit(input.kind, input.text.clone()) {
                    app.status = error;
                    app.input = Some(input);
                }
                return false;
            }
            K::Backspace => {
                input.text.pop();
            }
            K::Char('u') if k.modifiers.contains(M::CONTROL) => input.text.clear(),
            K::Char(c)
                if !k.modifiers.intersects(M::CONTROL | M::ALT) && input.text.len() < 65536 =>
            {
                input.text.push(c);
            }
            K::Up if input.kind == InputKind::Send => {
                app.history_index = app.history_index.saturating_sub(1);
                if let Some(value) = app.store.history.get(app.history_index) {
                    input.text = value.clone();
                }
            }
            K::Down if input.kind == InputKind::Send => {
                app.history_index = (app.history_index + 1).min(app.store.history.len());
                input.text = app
                    .store
                    .history
                    .get(app.history_index)
                    .cloned()
                    .unwrap_or_default();
            }
            _ => {}
        }
        app.input = Some(input);
        return false;
    }
    match k.code {
        K::Char('q') => return true,
        K::Char('?') => app.help = true,
        K::Char(c @ '1'..='5') => app.page = (c as u8 - b'1') as usize,
        K::Up | K::Char('k') => move_selection(app, -1),
        K::Down | K::Char('j') => move_selection(app, 1),
        K::Enter if app.page == 1 => {
            if let Some(device) = app.devices.get(app.selected).cloned() {
                app.select(device, None);
            }
        }
        K::Enter if app.page == 2 => edit_setting(app),
        K::Enter if app.page == 3 => {
            if let Some(favorite) = app.store.config.favorites.get(app.favorite_index) {
                app.tx_hex = favorite.hex;
                app.open(InputKind::Send, favorite.value.clone());
            }
        }
        K::Enter | K::Char('i') => app.open(InputKind::Send, String::new()),
        K::Char('/') => app.open(InputKind::Search, app.search.clone()),
        K::Char('f') => app.open(InputKind::Filter, app.filter.clone()),
        K::Char('n') => app.search_next(),
        K::Char('p' | ' ') => app.pause(),
        K::PageUp => app.scroll_up(20),
        K::PageDown => app.scroll = app.scroll.saturating_sub(20),
        K::End => {
            app.anchor = None;
            app.wire_anchor = None;
            app.scroll = 0;
        }
        K::Char('v') => {
            app.mode = (app.mode + 1) % 3;
            app.anchor = None;
            app.wire_anchor = None;
            app.scroll = 0;
            app.found = None;
        }
        K::Char('T') => app.timestamp = (app.timestamp + 1) % 3,
        K::Char('w') => app.graph = !app.graph,
        K::Char('g') => app.toggle_encoding(),
        K::Char('x') => app.tx_hex = !app.tx_hex,
        K::Char('e') => {
            app.profile.ending = match app.profile.ending.as_str() {
                "CRLF" => "LF",
                "LF" => "CR",
                "CR" => "无",
                _ => "CRLF",
            }
            .into();
            app.persist();
        }
        K::Char('l') => app.logging(),
        K::Char('c') => {
            app.csv = !app.csv;
            app.status = format!(
                "CSV {}，下次开启日志生效",
                if app.csv { "开启" } else { "关闭" }
            );
        }
        K::Char('b') => {
            let current = BAUDS
                .iter()
                .position(|b| *b == app.profile.settings.baud)
                .unwrap_or(3);
            app.profile.settings.baud = BAUDS[(current + 1) % BAUDS.len()];
            app.apply();
        }
        K::Char('B') => app.open(InputKind::Baud, app.profile.settings.baud.to_string()),
        K::Char('s') => {
            let s = &app.profile.settings;
            app.open(
                InputKind::Settings,
                format!(
                    "baud={} bits={} parity={} stop={} flow={}",
                    s.baud, s.bits, s.parity, s.stop, s.flow
                ),
            );
        }
        K::Char('h') => app.open(InputKind::Highlights, app.store.config.highlights.join(",")),
        K::Char('d') => {
            app.profile.settings.dtr = !app.profile.settings.dtr;
            lines(app);
        }
        K::Char('r') => {
            app.profile.settings.rts = !app.profile.settings.rts;
            lines(app);
        }
        K::Char('D') => {
            app.command(Command::Pulse {
                dtr: true,
                millis: 100,
            });
        }
        K::Char('R') => {
            app.command(Command::Pulse {
                dtr: false,
                millis: 100,
            });
        }
        K::Char('u') if app.flash.is_none() => {
            app.repeat = None;
            app.command(Command::Disconnect);
        }
        K::Char('a') => app.open(InputKind::Favorite, String::new()),
        K::Char('F') => app.open(InputKind::File, String::new()),
        K::Char('t') => app.open(
            InputKind::Timer,
            app.repeat
                .as_ref()
                .map(|r| r.every.as_millis().to_string())
                .unwrap_or_else(|| "1000".into()),
        ),
        K::Char('o') => app.open(InputKind::FlashCommand, app.profile.flash.clone()),
        K::Char('O') => app.open(InputKind::FlashDir, app.profile.flash_dir.clone()),
        K::F(5) => app.request_flash(),
        K::Esc => app.cancel_flash(),
        _ => {}
    }
    false
}
fn lines(app: &mut App) {
    app.command(Command::Lines {
        dtr: app.profile.settings.dtr,
        rts: app.profile.settings.rts,
    });
    app.persist();
}
fn edit_setting(app: &mut App) {
    match app.settings_index {
        0 => app.open(InputKind::Baud, app.profile.settings.baud.to_string()),
        1 => {
            app.profile.settings.bits = if app.profile.settings.bits == 8 {
                5
            } else {
                app.profile.settings.bits + 1
            };
            app.apply();
        }
        2 => {
            app.profile.settings.parity = match app.profile.settings.parity.as_str() {
                "none" => "even",
                "even" => "odd",
                _ => "none",
            }
            .into();
            app.apply();
        }
        3 => {
            app.profile.settings.stop = if app.profile.settings.stop == 1 { 2 } else { 1 };
            app.apply();
        }
        4 => {
            app.profile.settings.flow = match app.profile.settings.flow.as_str() {
                "none" => "hardware",
                "hardware" => "software",
                _ => "none",
            }
            .into();
            app.apply();
        }
        5 => {
            app.profile.settings.dtr = !app.profile.settings.dtr;
            lines(app);
        }
        6 => {
            app.profile.settings.rts = !app.profile.settings.rts;
            lines(app);
        }
        _ => app.toggle_encoding(),
    }
}
fn draw(f: &mut Frame, app: &App) {
    let full_device = app
        .device
        .as_ref()
        .map(|d| d.path.as_str())
        .unwrap_or("未选择端口");
    let device = if f.area().width < 125 {
        std::path::Path::new(full_device)
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or(full_device)
    } else {
        full_device
    };
    let state = if app.flash.is_some() {
        "烧录"
    } else if app.connected {
        "● 已连接"
    } else if app.device.is_some() {
        "○ 已断开"
    } else {
        "○ 待连接"
    };
    let title = format!(
        " SERIAL MAYON  {state} · {device} · {}  {}{}{} · RX {:.1}kB/s  TX {:.1}kB/s",
        app.profile.settings.baud,
        app.profile.settings.bits,
        app.profile
            .settings
            .parity
            .chars()
            .next()
            .unwrap_or('n')
            .to_ascii_uppercase(),
        app.profile.settings.stop,
        app.rate / 1000.0,
        app.rate_tx / 1000.0
    );
    let body = ui::chrome(
        f,
        &title,
        &["监视", "端口", "参数", "命令", "烧录"],
        app.page,
        "i 发送  / 搜索  p 暂停  l 日志  w 波形  F5 烧录  ? 帮助  q 退出",
        &app.status,
    );
    match app.page {
        0 => monitor(f, body, app),
        1 => devices(f, body, app),
        2 => settings(f, body, app),
        3 => commands(f, body, app),
        _ => flash(f, body, app),
    }
    if let Some(input) = &app.input {
        let label = match input.kind {
            InputKind::Send => {
                if app.tx_hex {
                    "发送 HEX · 原字节，无附加行尾"
                } else {
                    "发送文本 · ↑↓ 历史"
                }
            }
            InputKind::Search => "搜索 · 空内容清除 · n 下一条",
            InputKind::Filter => "过滤 · 空内容显示全部",
            InputKind::Baud => "自定义波特率",
            InputKind::Settings => "串口参数 · baud / bits / parity / stop / flow",
            InputKind::Favorite => "收藏 · 名称=命令",
            InputKind::File => "发送文件 · 原字节，无行尾 · 路径",
            InputKind::Timer => "重复发送 · 毫秒 · 0 停止",
            InputKind::FlashCommand => "烧录命令 · 由 shell 执行 · 不猜型号",
            InputKind::FlashDir => "烧录工作目录 · 空值为启动目录",
            InputKind::Highlights => "高亮词 · 逗号分隔",
        };
        ui::input(
            f,
            label,
            &tail(&input.text, f.area().width.saturating_sub(8) as usize),
        );
    }
    if app.help {
        ui::help(f, HELP);
    }
}
fn tail(text: &str, width: usize) -> String {
    use ratatui::text::Span;
    let mut out = String::new();
    for ch in text.chars().rev() {
        let candidate = format!("{ch}{out}");
        if Span::raw(&candidate).width() > width {
            break;
        }
        out = candidate;
    }
    out
}
fn devices(f: &mut Frame, area: Rect, app: &App) {
    if app.devices.is_empty() {
        f.render_widget(Paragraph::new("\n  未发现 ttyACM / ttyUSB 设备\n\n  插入开发板或 USB 转串口，列表每 750ms 自动刷新。\n  也可：serial-mayon /dev/serial/by-id/… -b 115200\n\n  相同 VID:PID + 序列号 + 接口自动重连；无序列号按物理 USB 位置。\n  当前未打开任何设备。按 Enter 选择后才会连接。").style(ui::base()).block(ui::block(" 端口 · 自动发现 ",true)),area);
        return;
    }
    ui::table(
        f,
        area,
        " 端口 · Enter 连接 · 自动刷新 ",
        vec!["端口", "VID:PID", "产品 / 适配器", "序列号"],
        app.devices
            .iter()
            .map(|d| {
                vec![
                    d.path.clone(),
                    format!("{:04x}:{:04x}", d.vid, d.pid),
                    d.product.clone(),
                    d.serial
                        .clone()
                        .unwrap_or_else(|| "无 · USB位置匹配".into()),
                ]
            })
            .collect(),
        &[C::Length(17), C::Length(9), C::Min(14), C::Percentage(28)],
        app.selected,
    );
}
fn settings(f: &mut Frame, area: Rect, app: &App) {
    let s = &app.profile.settings;
    let chunks = Layout::vertical([C::Length(12), C::Min(1)]).split(area);
    ui::table(
        f,
        chunks[0],
        " 参数 · Enter 修改 · 按设备自动保存 ",
        vec!["参数", "值", "快捷键"],
        vec![
            vec![
                "波特率".into(),
                s.baud.to_string(),
                "b 常用 / B 自定义".into(),
            ],
            vec!["数据位".into(), s.bits.to_string(), "Enter 循环 5–8".into()],
            vec![
                "校验".into(),
                s.parity.clone(),
                "Enter none/even/odd".into(),
            ],
            vec!["停止位".into(), s.stop.to_string(), "Enter 1/2".into()],
            vec![
                "流控".into(),
                s.flow.clone(),
                "Enter none/hardware/software".into(),
            ],
            vec![
                "DTR".into(),
                s.dtr.to_string(),
                "d 切换 / D 100ms脉冲".into(),
            ],
            vec![
                "RTS".into(),
                s.rts.to_string(),
                "r 切换 / R 100ms脉冲".into(),
            ],
            vec![
                "编码".into(),
                format!("{:?}", app.profile.encoding),
                "g UTF-8 / GBK".into(),
            ],
        ],
        &[C::Length(12), C::Length(16), C::Min(20)],
        app.settings_index,
    );
    f.render_widget(Paragraph::new(format!("\n 常用波特率：9600 · 19200 · 38400 · 57600 · 115200 · 230400\n             460800 · 921600 · 1000000 · 2000000\n\n 行尾 {} · e 切换 CR / LF / CRLF / 无\n 配置：{}\n\n DTR/RTS 的电平与复位极性取决于接线；不支持的驱动会报告错误。",app.profile.ending,app.store.config_path.display())).style(ui::base()).block(ui::block(" 设备配置 ",false)),chunks[1]);
}
fn commands(f: &mut Frame, area: Rect, app: &App) {
    let chunks = Layout::vertical([C::Percentage(55), C::Min(4)]).split(area);
    ui::table(
        f,
        chunks[0],
        " 收藏 · a 添加 名称=命令 · Enter 载入 ",
        vec!["名称", "模式", "命令"],
        app.store
            .config
            .favorites
            .iter()
            .map(|c| {
                vec![
                    c.name.clone(),
                    if c.hex { "HEX".into() } else { "TEXT".into() },
                    c.value.clone(),
                ]
            })
            .collect(),
        &[C::Length(18), C::Length(6), C::Min(20)],
        app.favorite_index,
    );
    let lines: Vec<Line> = app
        .store
        .history
        .iter()
        .rev()
        .take(chunks[1].height.saturating_sub(2) as usize)
        .map(|s| Line::from(ui::muted(s.clone())))
        .collect();
    f.render_widget(
        Paragraph::new(lines).style(ui::base()).block(ui::block(
            " 历史 · i 输入 · ↑↓ 调用 · F 发送文件 · t 定时 ",
            false,
        )),
        chunks[1],
    );
}
fn flash(f: &mut Frame, area: Rect, app: &App) {
    let chunks = Layout::vertical([C::Length(9), C::Min(3)]).split(area);
    let detected = crate::app::detected_flash().join(" / ");
    let lines = vec![
        Line::from(ui::muted(format!(
            " 检测到：{}",
            if detected.is_empty() {
                "未发现烧录工具"
            } else {
                &detected
            }
        ))),
        Line::from(format!(
            " 命令：{}",
            if app.profile.flash.is_empty() {
                "尚未配置 · o 编辑（不自动推断芯片型号）"
            } else {
                &app.profile.flash
            }
        )),
        Line::from(format!(
            " 目录：{}",
            if app.profile.flash_dir.is_empty() {
                "当前启动目录"
            } else {
                &app.profile.flash_dir
            }
        )),
        Line::from(""),
        Line::from(ui::blue(
            " o 编辑命令   O 工作目录   F5 释放串口并执行   Esc 取消",
        )),
        Line::from(ui::muted(
            " 先确认端口关闭 → 运行命令 → 保留输出 → 按设备身份重连。",
        )),
    ];
    f.render_widget(
        Paragraph::new(lines)
            .style(ui::base())
            .block(ui::block(" 烧录联动 ", true)),
        chunks[0],
    );
    let skip = app
        .flash_lines
        .len()
        .saturating_sub(chunks[1].height.saturating_sub(2) as usize);
    f.render_widget(
        Paragraph::new(
            app.flash_lines
                .iter()
                .skip(skip)
                .map(|s| Line::from(s.clone()))
                .collect::<Vec<_>>(),
        )
        .style(ui::base())
        .block(ui::block(
            if app.flash.is_some() {
                " 执行中 · Esc 取消 "
            } else {
                " 烧录输出 "
            },
            false,
        )),
        chunks[1],
    );
}
fn monitor(f: &mut Frame, area: Rect, app: &App) {
    let main = Layout::vertical([C::Min(3), C::Length(3)]).split(area);
    let (capture, plot) = if app.graph && main[0].height >= 12 {
        if area.width >= 125 {
            let areas = Layout::horizontal([C::Percentage(67), C::Min(30)]).split(main[0]);
            (areas[0], Some(areas[1]))
        } else {
            let areas = Layout::vertical([C::Min(6), C::Length(10)]).split(main[0]);
            (areas[0], Some(areas[1]))
        }
    } else {
        (main[0], None)
    };
    let view = app.view_capture();
    let anchor = app.view_anchor();
    let mut records: Vec<_> = view
        .records
        .iter()
        .filter(|r| anchor.is_none_or(|anchor| r.id <= anchor))
        .filter(|r| {
            r.kind != "RX"
                || app.filter.is_empty()
                || codec::plain(&r.text)
                    .to_lowercase()
                    .contains(&app.filter.to_lowercase())
        })
        .collect();
    let height = capture.height.saturating_sub(2) as usize;
    let end = records.len().saturating_sub(app.scroll);
    let start = end.saturating_sub(height);
    records = records[start..end].to_vec();
    let width = capture.width.saturating_sub(2) as usize;
    let mut lines: Vec<Line> = records.iter().map(|r| record_line(app, r, width)).collect();
    if app.mode == 0 && app.anchor.is_none() && !app.framer.pending().is_empty() {
        let raw = app.framer.pending();
        let text = app.profile.encoding.decode(raw);
        let preview = match app.mode {
            1 => hex(raw, width.saturating_sub(7) / 3),
            2 => format!("{} │ {}", codec::plain(&text), hex(raw, 12)),
            _ => codec::plain(&text),
        };
        if app.filter.is_empty() || preview.contains(&app.filter) {
            if lines.len() >= height && !lines.is_empty() {
                lines.remove(0);
            }
            lines.push(Line::from(ui::muted(clip(
                &format!(
                    "  RX · {preview}{}",
                    if app.framer.truncated() {
                        " [行截断]"
                    } else {
                        " ▏"
                    }
                ),
                width,
            ))));
        }
    }
    if lines.is_empty() {
        lines.push(Line::from(ui::muted(" 等待数据 · i 发送命令 · 2 选择串口")));
    }
    let paused = if let Some(anchor) = anchor {
        let overwritten = view.records.front().is_some_and(|r| r.id > anchor);
        format!(
            "暂停 · 新增 {} 行{}",
            view.next.saturating_sub(anchor + 1),
            if overwritten {
                " · 暂停位置已被淘汰"
            } else {
                ""
            }
        )
    } else {
        "实时".into()
    };
    let title = format!(
        " {} · {} · {} 行 · 淘汰 {} · 日志 {} {} ",
        ["TEXT", "HEX", "MIX"][app.mode],
        paused,
        view.records.len(),
        view.evicted,
        if app.logger.is_some() { "ON" } else { "OFF" },
        if app.filter.is_empty() {
            String::new()
        } else {
            format!("· 过滤 {}", app.filter)
        }
    );
    f.render_widget(
        Paragraph::new(lines)
            .style(ui::base())
            .block(ui::block(title, true)),
        capture,
    );
    if let Some(plot) = plot {
        graph(f, plot, app);
    }
    let repeat = app
        .repeat
        .as_ref()
        .map(|r| format!(" · 每 {}ms", r.every.as_millis()))
        .unwrap_or_default();
    f.render_widget(
        Paragraph::new(Line::from(vec![
            ui::blue(" ▏i / Enter 输入 "),
            Span::raw(format!(
                " {} · 行尾 {} · {:?}{}",
                if app.tx_hex { "HEX" } else { "TEXT" },
                app.profile.ending,
                app.profile.encoding,
                repeat
            )),
            ui::muted(format!(" · RX {} B / TX {} B", app.rx_total, app.tx_total)),
        ]))
        .style(ui::base())
        .block(ui::block(" 发送 · x 模式 · e 行尾 · t 重复 ", false)),
        main[1],
    );
}
fn hex(raw: &[u8], limit: usize) -> String {
    let text = raw
        .iter()
        .take(limit)
        .map(|b| format!("{b:02X}"))
        .collect::<Vec<_>>()
        .join(" ");
    if raw.len() > limit {
        format!("{text} …")
    } else {
        text
    }
}
fn record_line(app: &App, r: &crate::app::Record, width: usize) -> Line<'static> {
    let timestamp = match app.timestamp {
        0 => r.at.format("%H:%M:%S%.3f").to_string(),
        1 => format!("+{:9.3}", r.elapsed),
        _ => String::new(),
    };
    let prefix = format!("{timestamp} {:>2} │ ", r.kind);
    let plain = codec::plain(&r.text);
    let body = if r.kind == "RX" {
        match app.mode {
            1 => hex(&r.raw, width.saturating_sub(prefix.len()) / 3),
            2 => format!(
                "{:<47} │ {}",
                hex(&r.raw, 16),
                r.raw
                    .iter()
                    .map(|b| if (32..127).contains(b) {
                        *b as char
                    } else {
                        '.'
                    })
                    .collect::<String>()
            ),
            _ => r.text.clone(),
        }
    } else {
        r.text.clone()
    };
    let mut spans = vec![ui::muted(prefix.clone())];
    let remaining = width.saturating_sub(Span::raw(&prefix).width());
    if app.mode == 0 && r.kind == "RX" {
        let ansi = codec::ansi_line(&body);
        let mut used = 0;
        for mut span in ansi.spans {
            if used >= remaining {
                break;
            }
            let clipped = clip(&span.content, remaining - used);
            used += Span::raw(&clipped).width();
            span.content = clipped.into();
            spans.push(span);
        }
    } else {
        spans.push(Span::styled(
            clip(&codec::plain(&body), remaining),
            Style::default().fg(if r.kind == "TX" {
                CYAN
            } else if r.kind == "错误" {
                RED
            } else if r.kind == "断开" {
                YELLOW
            } else {
                FG
            }),
        ));
    }
    let mut line = Line::from(spans);
    let is_match =
        !app.search.is_empty() && plain.to_lowercase().contains(&app.search.to_lowercase());
    if app.found == Some(r.id) {
        line = line.style(Style::default().bg(SELECTION).fg(BLUE));
    } else if is_match {
        line = line.style(Style::default().bg(SELECTION));
    }
    if app
        .store
        .config
        .highlights
        .iter()
        .any(|needle| !needle.is_empty() && plain.to_uppercase().contains(&needle.to_uppercase()))
    {
        line = line.style(
            Style::default()
                .fg(if plain.contains("WARN") { YELLOW } else { RED })
                .add_modifier(Modifier::BOLD),
        );
    }
    line
}
fn graph(f: &mut Frame, area: Rect, app: &App) {
    if app.series.is_empty() {
        f.render_widget(
            Paragraph::new("\n 等待数值行…\n\n a=1.2,b=3\n 或 1.2,3,4\n\n w 收起波形")
                .style(ui::base().fg(MUTED))
                .block(ui::block(" 波形 · Braille ", false)),
            area,
        );
        return;
    }
    let colors = [BLUE, GREEN, YELLOW, CYAN, RED];
    let data: Vec<_> = app
        .series
        .iter()
        .map(|(name, values)| (name, values.iter().copied().collect::<Vec<_>>()))
        .collect();
    let all = data.iter().flat_map(|(_, values)| values.iter());
    let min = all.clone().map(|(_, v)| *v).fold(f64::INFINITY, f64::min);
    let max = all.map(|(_, v)| *v).fold(f64::NEG_INFINITY, f64::max);
    let pad = ((max - min) * 0.1).max(0.1);
    let x_end = data
        .iter()
        .filter_map(|(_, v)| v.last().map(|(x, _)| *x))
        .fold(1.0, f64::max);
    let x_start = data
        .iter()
        .filter_map(|(_, v)| v.first().map(|(x, _)| *x))
        .fold(x_end, f64::min)
        .min(x_end - 1.0);
    let sets = data
        .iter()
        .enumerate()
        .map(|(i, (name, values))| {
            Dataset::default()
                .name(format!(
                    "{} {:.2}",
                    name,
                    values.last().map(|(_, v)| *v).unwrap_or_default()
                ))
                .marker(Marker::Braille)
                .graph_type(GraphType::Line)
                .style(Style::default().fg(colors[i % colors.len()]))
                .data(values)
        })
        .collect();
    let legend = Line::from(
        data.iter()
            .enumerate()
            .flat_map(|(i, (name, values))| {
                [Span::styled(
                    format!(
                        " {name} {:.3} ",
                        values.last().map(|(_, v)| *v).unwrap_or_default()
                    ),
                    Style::default().fg(colors[i % colors.len()]),
                )]
            })
            .collect::<Vec<_>>(),
    );
    let chart = Chart::new(sets)
        .style(ui::base())
        .block(ui::block(" 波形 · 最近1024点/通道 ", false).title_bottom(legend))
        .x_axis(
            Axis::default()
                .title("秒")
                .style(Style::default().fg(MUTED))
                .bounds([x_start, x_end])
                .labels([format!("{x_start:.0}"), format!("{x_end:.0}")]),
        )
        .y_axis(
            Axis::default()
                .style(Style::default().fg(MUTED))
                .bounds([min - pad, max + pad])
                .labels([format!("{min:.1}"), format!("{max:.1}")]),
        );
    f.render_widget(chart, area);
}
