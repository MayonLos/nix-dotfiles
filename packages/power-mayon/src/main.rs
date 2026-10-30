use crossterm::event::{self, Event, KeyCode, KeyEventKind, MouseEventKind};
use mayon_ui::{self as ui, theme::*};
use ratatui::{
    layout::{Constraint, Layout, Rect},
    style::Style,
    symbols::Marker,
    text::{Line, Span},
    widgets::{Axis, Chart, Dataset, GraphType, Paragraph, Wrap},
};
use serde_json::Value;
use std::{
    io::{self, Write},
    process::{Command, Stdio},
    sync::mpsc,
    thread,
    time::{Duration, Instant},
};

fn backend(args: &[String]) -> io::Result<std::process::Output> {
    let script = std::env::var("POWER_MAYON_BACKEND")
        .unwrap_or_else(|_| format!("{}/backend.py", env!("CARGO_MANIFEST_DIR")));
    let python = std::env::var("POWER_MAYON_PYTHON").unwrap_or_else(|_| "python3".into());
    Command::new(python).arg(script).args(args).output()
}
fn execute(args: &[&str]) -> Result<Value, String> {
    let output = backend(&args.iter().map(|s| s.to_string()).collect::<Vec<_>>())
        .map_err(|e| e.to_string())?;
    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).trim().to_string());
    }
    serde_json::from_slice(&output.stdout).or_else(|_| {
        Ok(Value::String(
            String::from_utf8_lossy(&output.stdout).trim().to_string(),
        ))
    })
}
fn string(v: &Value) -> String {
    v.as_str().unwrap_or("不可读").to_string()
}
fn metric(v: &Value, unit: &str) -> String {
    v.as_f64()
        .map(|v| format!("{v:.1}{unit}"))
        .unwrap_or_else(|| "不可读".into())
}
fn duration(v: &Value) -> String {
    v.as_u64()
        .map(|s| format!("{}h {:02}m", s / 3600, s % 3600 / 60))
        .unwrap_or_else(|| "待稳定功率".into())
}
fn mode_label(value: &str) -> &str {
    match value {
        "power-saver" => "省电",
        "balanced" => "均衡",
        "performance" => "性能",
        _ => "不可用",
    }
}
fn array(v: &Value) -> Vec<&Value> {
    v.as_array().map(|a| a.iter().collect()).unwrap_or_default()
}
struct App {
    data: Value,
    page: usize,
    selected: usize,
    scroll: u16,
    filter: String,
    editing: bool,
    help: bool,
    confirm: Option<String>,
    message: String,
    nvidia: bool,
    body: Rect,
    modes_area: Rect,
}
impl App {
    fn draw(&mut self, f: &mut ratatui::Frame) {
        let data = &self.data;
        let current = data["profile"]["current"].as_str().unwrap_or("unknown");
        let ac = match data["ac_online"].as_bool() {
            Some(true) => "AC 插电",
            Some(false) => "电池供电",
            _ => "电源未知",
        };
        let auto = if data["automatic"]["enabled"] == true {
            "自动开启"
        } else {
            "自动关闭"
        };
        self.body = ui::chrome(
            f,
            &format!(
                " power-mayon  ·  {ac}  ·  {}  ·  {auto}",
                mode_label(current)
            ),
            &["概览", "进程", "历史", "规则"],
            self.page,
            " j/k 移动  Enter 模式  c 养护  / 过滤  ? 帮助  q 退出",
            &self.message,
        );
        self.modes_area = Rect::default();
        match self.page {
            0 => self.overview(f),
            1 => self.processes(f),
            2 => self.history(f),
            _ => self.rules(f),
        }
        if self.editing {
            ui::input(f, " 过滤进程 · Enter 确认 ", &self.filter);
        }
        if self.help {
            ui::help(f, "1–4 / Tab 切页 · j/k / 滚轮 移动 · q 退出\n概览：Enter 选择模式；s 省电 / b 均衡 / p 性能\nc 切换电池养护（固件固定范围，不伪造可调阈值）\n进程：/ 过滤（名称或PID）· Esc 清空\n历史：仅TUI打开或 watch 期间记录，30秒一条，最多720条\n规则：a 切换AC · d 切换电池 · f 切换GameMode · e 开启/关闭\n自动默认关闭；手动模式需先关闭自动。\nGameMode默认keep沿用钩子；显式规则最多30秒后生效。\ng 显式开启/停止 NVIDIA 查询：检查active后仍有唤醒竞态\n默认仅读PCI状态和可读进程fd；GPU进程列表可能不完整。\n耗电估算按CPU ticks分摊RAPL，不等于进程实际总耗电。\n鼠标：点击顶部切页、模式行；滚轮移动。? / Esc 关闭");
        }
        if let Some(action) = &self.confirm {
            let text = match action.as_str() {
                "nvidia" => "启用 NVIDIA 采样？\n只查询当前active设备，检查后仍可能休眠；nvidia-smi可能唤醒它。\n若只想查看休眠状态，请保持默认。\n\ny 确认 · n / Esc 取消",
                "auto" => "开启自动电源规则？\nAC/电池/GameMode规则由30秒定时器执行；GameMode默认keep沿用钩子。\n先移除Noctalia旧插拔电切换钩子，避免两个控制方冲突。\n\ny 确认 · n / Esc 取消",
                _ => "更改固件电池养护开关？\n复用 legion-conservation 单属性权限；固件决定保护范围。\n\ny 确认 · n / Esc 取消",
            };
            ui::dialog(f, " 确认 ", text);
        }
    }
    fn overview(&mut self, f: &mut ratatui::Frame) {
        let areas = Layout::vertical([Constraint::Min(5), Constraint::Length(7)]).split(self.body);
        let mut lines = vec![];
        for b in array(&self.data["batteries"]) {
            let time = if b["status"] != "Discharging" && b["status"] != "Charging" {
                "无充放电计时".into()
            } else if b["status"] == "Discharging" {
                duration(&b["time_to_empty_s"])
            } else {
                duration(&b["time_to_full_s"])
            };
            lines.push(Line::from(vec![
                ui::blue(format!(
                    " {}  {}",
                    string(&b["name"]),
                    metric(&b["percent"], "%")
                )),
                Span::raw(format!(
                    "   {}   {}   {time}",
                    string(&b["status"]),
                    metric(&b["power_w"], " W")
                )),
            ]));
            lines.push(Line::from(format!(
                " 健康 {} · 循环 {} · 容量 {} / {}",
                metric(&b["health_percent"], "%"),
                metric(&b["cycles"], ""),
                metric(&b["full_wh"], " Wh"),
                metric(&b["design_wh"], " Wh")
            )));
        }
        if array(&self.data["batteries"]).is_empty() {
            lines.push(Line::from(" 未发现电池"));
        }
        let c = &self.data["conservation"];
        let cons = match c["enabled"].as_bool() {
            Some(true) => "已开启",
            Some(false) => "关闭",
            None => "不可用",
        };
        lines.push(Line::from(format!(
            " 养护 {cons}  ·  固件固定保护范围  ·  c 切换"
        )));
        lines.push(Line::from(""));
        let cpu = &self.data["cpu"];
        lines.push(Line::from(format!(
            " CPU  {} · {} · {}",
            metric(&cpu["busy_percent"], "%"),
            metric(&cpu["frequency_mhz"], " MHz"),
            metric(&cpu["package_power_w"], " W (RAPL)")
        )));
        lines.push(Line::from(ui::muted(format!(
            " governor {} · RAPL权限不足时不推算瓦数",
            string(&cpu["governor"])
        ))));
        for d in array(&self.data["gpu"]["devices"]) {
            lines.push(Line::from(format!(
                " {} {}  {} / {}",
                string(&d["vendor"]),
                string(&d["pci"]),
                string(&d["runtime_status"]),
                string(&d["power_state"])
            )));
            if d["vendor"] == "Intel" && d["frequency_mhz"].is_number() {
                lines.push(Line::from(format!(
                    " Intel  {} · {}",
                    metric(&d["frequency_mhz"], " MHz"),
                    metric(&d["utilization_percent"], "%")
                )));
            }
            if d["power_w"].is_number() {
                lines.push(Line::from(format!(
                    " NVIDIA  {} · {} · {}",
                    metric(&d["power_w"], " W"),
                    metric(&d["temperature_c"], " °C"),
                    metric(&d["utilization_percent"], "%")
                )));
            }
        }
        lines.push(Line::from(ui::muted(if self.nvidia {
            " NVIDIA查询已开启 · g 停止"
        } else {
            " NVIDIA查询默认关闭（避免唤醒）· g 显式开启"
        })));
        for error in array(&self.data["gpu"]["errors"]) {
            lines.push(Line::from(ui::muted(format!(" {}", string(error)))));
        }
        if let Some(error) = self.data["profile"]["error"].as_str() {
            lines.push(Line::from(ui::muted(format!(" {error}"))));
        }
        lines.push(Line::from(""));
        for d in array(&self.data["temperatures"]) {
            lines.push(Line::from(format!(
                " {}  {}",
                string(&d["name"]),
                metric(&d["celsius"], " °C")
            )));
        }
        for d in array(&self.data["fans"]) {
            lines.push(Line::from(format!(
                " {}  {}",
                string(&d["name"]),
                metric(&d["rpm"], " RPM")
            )));
        }
        self.scroll = self.scroll.min(
            lines
                .len()
                .saturating_sub(areas[0].height.saturating_sub(2) as usize) as u16,
        );
        f.render_widget(
            Paragraph::new(lines)
                .block(ui::block(" 电池与硬件 · 滚轮查看传感器 ", false))
                .scroll((self.scroll, 0))
                .wrap(Wrap { trim: false }),
            areas[0],
        );
        self.modes_area = areas[1];
        let rows: Vec<Vec<String>> = ["power-saver", "balanced", "performance"]
            .iter()
            .map(|mode| {
                vec![
                    mode_label(mode).into(),
                    (*mode).into(),
                    if self.data["profile"]["current"] == *mode {
                        "当前".into()
                    } else if array(&self.data["profile"]["available"])
                        .iter()
                        .any(|v| **v == *mode)
                    {
                        "Enter 选择".into()
                    } else {
                        "不可用".into()
                    },
                ]
            })
            .collect();
        ui::table(
            f,
            areas[1],
            " 性能模式 · s / b / p 一键选择 ",
            vec!["模式", "PPD", "状态"],
            rows,
            &[
                Constraint::Length(10),
                Constraint::Min(15),
                Constraint::Length(12),
            ],
            self.selected.min(2),
        );
    }
    fn processes(&self, f: &mut ratatui::Frame) {
        let areas = Layout::vertical([
            Constraint::Length(3),
            Constraint::Percentage(57),
            Constraint::Min(4),
        ])
        .split(self.body);
        f.render_widget(Paragraph::new(" 估算 = RAPL package W × CPU时间占比（含idle）；不含GPU/IO。\n 无RAPL权限：仅CPU占比。独显列表为设备打开者，可能含空闲客户端。").style(ui::base().fg(MUTED)).wrap(Wrap { trim: false }), areas[0]);
        let rows: Vec<Vec<String>> = array(&self.data["processes"])
            .into_iter()
            .filter(|v| self.matches(v))
            .map(|p| {
                vec![
                    p["pid"].to_string(),
                    string(&p["name"]),
                    metric(&p["cpu_percent"], "%"),
                    metric(&p["estimated_power_w"], " W"),
                ]
            })
            .collect();
        let chosen = self.selected.min(rows.len().saturating_sub(1));
        ui::table(
            f,
            areas[1],
            format!(" CPU 进程 · 估算 · / {} ", self.filter).as_str(),
            vec!["PID", "进程", "全机CPU", "估算功耗"],
            rows,
            &[
                Constraint::Length(8),
                Constraint::Min(12),
                Constraint::Length(12),
                Constraint::Length(13),
            ],
            chosen,
        );
        let rows: Vec<Vec<String>> = array(&self.data["gpu"]["processes"])
            .into_iter()
            .filter(|v| self.matches(v))
            .map(|p| {
                vec![
                    p["pid"].to_string(),
                    string(&p["name"]),
                    array(&p["devices"])
                        .iter()
                        .map(|v| string(v))
                        .collect::<Vec<_>>()
                        .join(", "),
                ]
            })
            .collect();
        let chosen = self.selected.min(rows.len().saturating_sub(1));
        ui::table(
            f,
            areas[2],
            " dGPU 设备打开者 · 当前用户可读fd ",
            vec!["PID", "进程", "设备"],
            rows,
            &[
                Constraint::Length(8),
                Constraint::Min(12),
                Constraint::Percentage(45),
            ],
            chosen,
        );
    }
    fn matches(&self, p: &Value) -> bool {
        format!("{} {}", p["pid"], string(&p["name"]))
            .to_lowercase()
            .contains(&self.filter.to_lowercase())
    }
    fn history(&self, f: &mut ratatui::Frame) {
        let areas = Layout::vertical([
            Constraint::Length(3),
            Constraint::Length(8),
            Constraint::Min(5),
        ])
        .split(self.body);
        let values = array(&self.data["history"]);
        f.render_widget(Paragraph::new(format!(" 每30秒一条 · 最多720条 · 已记录 {} 条\n 电池充/放电功率幅值，AC时不代表整机墙上功耗；缺测显示为空白。", values.len())).style(ui::base().fg(MUTED)).wrap(Wrap { trim: false }), areas[0]);
        let width = areas[1].width.saturating_sub(2) as usize;
        let tail = values.iter().rev().take(width).copied().collect::<Vec<_>>();
        let points: Vec<(f64, f64)> = tail
            .iter()
            .rev()
            .enumerate()
            .filter_map(|(i, value)| value["battery_w"].as_f64().map(|v| (i as f64, v)))
            .collect();
        let max = points.iter().map(|(_, y)| *y).fold(1.0f64, f64::max) * 1.1;
        let x_max = (tail.len().saturating_sub(1) as f64).max(1.0);
        let datasets = vec![Dataset::default()
            .name("电池 W")
            .marker(Marker::Braille)
            .graph_type(GraphType::Line)
            .style(Style::default().fg(BLUE))
            .data(&points)];
        f.render_widget(
            Chart::new(datasets)
                .block(ui::block(" 电池功率 W · 最近样本 ", false))
                .x_axis(
                    Axis::default()
                        .bounds([0.0, x_max])
                        .labels([Span::raw("较早"), Span::raw("现在")])
                        .style(Style::default().fg(MUTED)),
                )
                .y_axis(
                    Axis::default()
                        .bounds([0.0, max])
                        .labels([Span::raw("0"), Span::raw(format!("{:.0}", max))])
                        .style(Style::default().fg(MUTED)),
                ),
            areas[1],
        );
        let rows: Vec<Vec<String>> = values
            .iter()
            .rev()
            .take(80)
            .map(|v| {
                vec![
                    v["timestamp"].to_string(),
                    metric(&v["battery_w"], " W"),
                    metric(&v["cpu_w"], " W"),
                    string(&v["profile"]),
                ]
            })
            .collect();
        let chosen = self.selected.min(rows.len().saturating_sub(1));
        ui::table(
            f,
            areas[2],
            " 样本 · Unix时间戳 ",
            vec!["时间", "电池", "CPU RAPL", "模式"],
            rows,
            &[
                Constraint::Length(13),
                Constraint::Length(13),
                Constraint::Length(13),
                Constraint::Min(12),
            ],
            chosen,
        );
    }
    fn rules(&self, f: &mut ratatui::Frame) {
        let a = &self.data["automatic"];
        let rows: Vec<Vec<String>> = vec![
            vec!["插电 AC".into(), string(&a["ac"]), "a 循环".into()],
            vec!["电池".into(), string(&a["battery"]), "d 循环".into()],
            vec!["GameMode".into(), string(&a["gamemode"]), "f 循环".into()],
        ];
        let areas = Layout::vertical([Constraint::Length(8), Constraint::Min(4)]).split(self.body);
        ui::table(
            f,
            areas[0],
            " 自动规则 · 默认关闭 · e 开启/关闭 ",
            vec!["条件", "模式", "操作"],
            rows,
            &[
                Constraint::Length(12),
                Constraint::Min(15),
                Constraint::Length(18),
            ],
            self.selected.min(2),
        );
        let pending = if a["gamemode_pending"] == true {
            "当前GameMode活跃或恢复待处理"
        } else {
            "当前无GameMode恢复日志"
        };
        f.render_widget(Paragraph::new(format!("\n {pending}\n\n 开启后由用户定时器每30秒应用；TUI退出后规则仍生效。\n 开启前先由主代理移除Noctalia旧插拔电钩子，避免反复覆盖。\n 自动启用时手动mode拒绝；关闭自动后保留当前模式。\n GameMode keep让出；自定义规则最多30秒后生效，退出后由钩子恢复。\n 规则只配置PPD，不写governor、scx、风扇或显卡电源。\n\n 配置：$XDG_CONFIG_HOME/power-mayon/config.json\n 历史：$XDG_STATE_HOME/power-mayon/history.json\n 历史只在TUI或显式 watch运行时采集。" )).block(ui::block(" 行为与数据归属 ", false)).wrap(Wrap { trim: false }), areas[1]);
    }
}
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if !args.is_empty() && args != ["tui"] {
        let script = std::env::var("POWER_MAYON_BACKEND")
            .unwrap_or_else(|_| format!("{}/backend.py", env!("CARGO_MANIFEST_DIR")));
        let python = std::env::var("POWER_MAYON_PYTHON").unwrap_or_else(|_| "python3".into());
        let status = Command::new(python)
            .arg(script)
            .args(args)
            .stdin(Stdio::inherit())
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit())
            .status()?;
        std::process::exit(status.code().unwrap_or(1));
    }
    // Match Kitty padding to the shared palette, then restore the user's
    // configured background when leaving the alternate screen.
    struct Background;
    impl Drop for Background {
        fn drop(&mut self) {
            print!("\x1b]111\x07");
            let _ = io::stdout().flush();
        }
    }
    let _background = Background;
    if let ratatui::style::Color::Rgb(r, g, b) = BG {
        print!("\x1b]11;#{r:02x}{g:02x}{b:02x}\x07");
        io::stdout().flush()?;
    }
    let (mut terminal, _guard) = ui::terminal()?;
    let mut app = App {
        data: Value::Null,
        page: 0,
        selected: 0,
        scroll: 0,
        filter: String::new(),
        editing: false,
        help: false,
        confirm: None,
        message: "只读采样中 · 自动规则默认关闭".into(),
        nvidia: false,
        body: Rect::default(),
        modes_area: Rect::default(),
    };
    let (tx, rx) = mpsc::channel();
    let mut busy = false;
    let mut last = Instant::now() - Duration::from_secs(10);
    let mut action: Option<Vec<String>> = None;
    loop {
        if let Ok((data, message)) = rx.try_recv() {
            busy = false;
            if let Some(data) = data {
                app.data = data;
            }
            if let Some(message) = message {
                app.message = message;
            }
        }
        if !busy && (action.is_some() || last.elapsed() >= Duration::from_secs(3)) {
            let tx = tx.clone();
            let nvidia = app.nvidia;
            let command = action.take();
            thread::spawn(move || {
                let message = command.map(|cmd| {
                    match execute(&cmd.iter().map(|s| s.as_str()).collect::<Vec<_>>()) {
                        Ok(_) => "操作完成".into(),
                        Err(e) => e,
                    }
                });
                let mut args = vec!["sample"];
                if nvidia {
                    args.push("--nvidia");
                }
                let (data, message) = match execute(&args) {
                    Ok(data) => (Some(data), message),
                    Err(e) => (None, Some(e)),
                };
                let _ = tx.send((data, message));
            });
            busy = true;
            last = Instant::now();
        }
        terminal.draw(|f| app.draw(f))?;
        if !event::poll(Duration::from_millis(80))? {
            continue;
        }
        let event = event::read()?;
        let key = match event {
            Event::Key(k) if k.kind == KeyEventKind::Press => k.code,
            Event::Mouse(m) => match m.kind {
                MouseEventKind::ScrollDown => KeyCode::Char('j'),
                MouseEventKind::ScrollUp => KeyCode::Char('k'),
                MouseEventKind::Down(_) if m.row == 1 && m.column < 41 => {
                    app.page = ((m.column.saturating_sub(1)) / 10).min(3) as usize;
                    app.selected = 0;
                    continue;
                }
                MouseEventKind::Down(_)
                    if app.page == 0
                        && app.modes_area.contains((m.column, m.row).into())
                        && m.row >= app.modes_area.y + 2
                        && m.row < app.modes_area.y + 5 =>
                {
                    app.selected = (m.row - app.modes_area.y - 2) as usize;
                    KeyCode::Enter
                }
                _ => continue,
            },
            _ => continue,
        };
        if app.editing {
            match key {
                KeyCode::Esc => {
                    app.editing = false;
                    app.filter.clear();
                }
                KeyCode::Enter => app.editing = false,
                KeyCode::Backspace => {
                    app.filter.pop();
                }
                KeyCode::Char(c) => app.filter.push(c),
                _ => {}
            }
            continue;
        }
        if app.help {
            if matches!(key, KeyCode::Esc | KeyCode::Char('?') | KeyCode::Char('q')) {
                app.help = false;
            }
            continue;
        }
        if let Some(confirmation) = app.confirm.clone() {
            if key == KeyCode::Char('y') {
                match confirmation.as_str() {
                    "nvidia" => app.nvidia = true,
                    "auto" => action = Some(vec!["auto".into(), "enable".into()]),
                    _ => {
                        action = Some(vec![
                            "conservation".into(),
                            if app.data["conservation"]["enabled"] == true {
                                "off".into()
                            } else {
                                "on".into()
                            },
                        ])
                    }
                }
                app.confirm = None;
                last = Instant::now() - Duration::from_secs(10);
            } else if matches!(key, KeyCode::Esc | KeyCode::Char('n')) {
                app.confirm = None;
            }
            continue;
        }
        match key {
            KeyCode::Char('q') => break,
            KeyCode::Char('?') => app.help = true,
            KeyCode::Char('1'..='4') => {
                if let KeyCode::Char(c) = key {
                    app.page = c as usize - '1' as usize;
                }
                app.selected = 0;
                app.scroll = 0;
            }
            KeyCode::Tab => {
                app.page = (app.page + 1) % 4;
                app.selected = 0;
                app.scroll = 0;
            }
            KeyCode::Char('j') | KeyCode::Down => {
                let max = match app.page {
                    0 | 3 => 2,
                    1 => array(&app.data["processes"])
                        .len()
                        .max(array(&app.data["gpu"]["processes"]).len())
                        .saturating_sub(1),
                    _ => array(&app.data["history"]).len().min(80).saturating_sub(1),
                };
                app.selected = (app.selected + 1).min(max);
                app.scroll = app.scroll.saturating_add(1);
            }
            KeyCode::Char('k') | KeyCode::Up => {
                app.selected = app.selected.saturating_sub(1);
                app.scroll = app.scroll.saturating_sub(1);
            }
            KeyCode::Char('/') => {
                app.page = 1;
                app.editing = true;
                app.selected = 0;
            }
            KeyCode::Esc => app.filter.clear(),
            KeyCode::Char('g') => {
                if app.nvidia {
                    app.nvidia = false;
                } else {
                    app.confirm = Some("nvidia".into());
                }
            }
            KeyCode::Char('c') => app.confirm = Some("conservation".into()),
            KeyCode::Char('e') if app.page == 3 => {
                if app.data["automatic"]["enabled"] == true {
                    action = Some(vec!["auto".into(), "disable".into()]);
                } else {
                    app.confirm = Some("auto".into());
                }
            }
            KeyCode::Char('a' | 'd' | 'f') if app.page == 3 => {
                let key = match key {
                    KeyCode::Char('a') => "ac",
                    KeyCode::Char('d') => "battery",
                    _ => "gamemode",
                };
                let modes: &[&str] = if key == "gamemode" {
                    &["keep", "power-saver", "balanced", "performance"]
                } else {
                    &["power-saver", "balanced", "performance"]
                };
                let current = app.data["automatic"][key].as_str().unwrap_or("balanced");
                let next = modes
                    [(modes.iter().position(|m| *m == current).unwrap_or(0) + 1) % modes.len()];
                action = Some(vec![
                    "auto".into(),
                    "configure".into(),
                    format!("--{key}"),
                    next.into(),
                ]);
            }
            KeyCode::Enter if app.page == 0 => {
                action = Some(vec![
                    "mode".into(),
                    ["power-saver", "balanced", "performance"][app.selected.min(2)].into(),
                ])
            }
            KeyCode::Char('s' | 'b' | 'p') if app.page == 0 => {
                action = Some(vec![
                    "mode".into(),
                    match key {
                        KeyCode::Char('s') => "power-saver",
                        KeyCode::Char('p') => "performance",
                        _ => "balanced",
                    }
                    .into(),
                ])
            }
            _ => {}
        }
    }
    Ok(())
}
