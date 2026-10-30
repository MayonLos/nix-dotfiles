use crate::{client, Config, Result};
use crossterm::event::{self, Event, KeyCode, MouseEventKind};
use mayon_ui::{base, block, blue, muted, terminal, theme::*};
use ratatui::{
    layout::{Constraint, Layout},
    text::{Line, Span},
    widgets::{Paragraph, Wrap},
};
use std::time::{Duration, Instant};
pub fn run() -> Result<()> {
    let (mut terminal, _guard) = terminal()?;
    let config = Config::load()?;
    let mut page = 0;
    let mut help = false;
    let mut filter = String::new();
    let mut filtering = false;
    let mut status = serde_json::json!({"phase":"inactive"});
    let mut refreshed = Instant::now() - Duration::from_secs(1);
    loop {
        if refreshed.elapsed() > Duration::from_millis(500) {
            status = client("status").unwrap_or_else(|_| serde_json::json!({"phase":"inactive"}));
            refreshed = Instant::now();
        }
        terminal.draw(|f| {
            let areas = Layout::vertical([
                Constraint::Length(1),
                Constraint::Length(2),
                Constraint::Min(4),
                Constraint::Length(2),
            ])
            .split(f.area());
            f.render_widget(
                Paragraph::new(" MAYON / VOICE                  本地中文语音输入")
                    .style(base().fg(BRIGHTFG)),
                areas[0],
            );
            f.render_widget(
                Paragraph::new(mayon_ui::tabs_line(&["状态", "配置"], page)).style(base()),
                areas[1],
            );
            let phase = match status["phase"].as_str().unwrap_or("inactive") {
                "recording" => "● 录音中",
                "transcribing" => "◌ 识别中",
                "idle" => "○ 就绪",
                _ => "○ 按需待命",
            };
            let lines = if help {
                vec![
                    Line::from(blue(" 快捷键")),
                    Line::from(" 空格 开始/结束录音    1/2 切页"),
                    Line::from(" / 过滤信息            ? 关闭帮助"),
                    Line::from(" q 退出界面（录音与服务独立运行）"),
                    Line::from(" 鼠标滚轮切页；点击顶部页签切页"),
                ]
            } else if page == 0 {
                vec![
                    Line::from(vec![blue("▏ "), Span::styled(phase, base().fg(GREEN))]),
                    Line::from(""),
                    Line::from(format!(" 引擎       {} / {}", config.engine, config.device)),
                    Line::from(format!(
                        " 上屏       {}",
                        status["delivery"].as_str().unwrap_or(&config.delivery)
                    )),
                    Line::from(""),
                    Line::from(muted(" 按空格说话，再按一次结束。")),
                    Line::from(muted(" 录音只暂存在私有 runtime；不保留转写历史。")),
                    Line::from(format!(
                        " 提示       {}",
                        status["error"]
                            .as_str()
                            .unwrap_or("首次使用先运行 mayon-voice models fetch")
                    )),
                ]
            } else {
                vec![
                    Line::from(blue("▏ 用户配置 · config.toml")),
                    Line::from(format!(
                        " 模型       {}",
                        clip(
                            &config
                                .model_dir
                                .strip_prefix(crate::home())
                                .map(|p| format!("~/{}", p.display()))
                                .unwrap_or_else(|_| config.model_dir.display().to_string()),
                            areas[2].width.saturating_sub(15) as usize
                        )
                    )),
                    Line::from(format!(
                        " 设备       {} / {} threads",
                        config.device, config.threads
                    )),
                    Line::from(format!(" 麦克风     {}", config.input_device)),
                    Line::from(format!(" 热词       {}", config.hotwords.join("、"))),
                    Line::from(format!(
                        " AI 润色    {}",
                        if config.polish {
                            "开启 · 最多 3s，失败回退"
                        } else {
                            "关闭"
                        }
                    )),
                    Line::from(format!(" 空闲退出   {}s", config.idle_seconds)),
                    Line::from(muted(" 配置由用户维护；下次守护进程启动读取。")),
                ]
            };
            let lines: Vec<_> = lines
                .into_iter()
                .filter(|l| {
                    filter.is_empty()
                        || l.to_string()
                            .to_lowercase()
                            .contains(&filter.to_lowercase())
                })
                .collect();
            f.render_widget(
                Paragraph::new(lines)
                    .style(base())
                    .block(block(
                        if filtering {
                            format!(" 过滤 /{filter} ")
                        } else {
                            " 语音输入 ".into()
                        },
                        true,
                    ))
                    .wrap(Wrap { trim: false }),
                areas[2],
            );
            f.render_widget(
                Paragraph::new(" 空格 录音  1/2 切页  / 过滤  ? 帮助  q 退出")
                    .style(base().fg(MUTED)),
                areas[3],
            );
        })?;
        if event::poll(Duration::from_millis(100))? {
            match event::read()? {
                Event::Key(k) if k.kind == event::KeyEventKind::Press => {
                    if filtering {
                        match k.code {
                            KeyCode::Esc | KeyCode::Enter => filtering = false,
                            KeyCode::Backspace => {
                                filter.pop();
                            }
                            KeyCode::Char(c) => filter.push(c),
                            _ => {}
                        };
                        continue;
                    }
                    match k.code {
                        KeyCode::Char('q') | KeyCode::Esc => break,
                        KeyCode::Char('1') => page = 0,
                        KeyCode::Char('2') => page = 1,
                        KeyCode::Char('?') => help = !help,
                        KeyCode::Char('/') => {
                            filtering = true;
                            filter.clear();
                        }
                        KeyCode::Char(' ') => {
                            if let Ok(v) = client("toggle") {
                                status = v;
                            }
                            refreshed = Instant::now();
                        }
                        _ => {}
                    }
                }
                Event::Mouse(m) => match m.kind {
                    MouseEventKind::ScrollDown | MouseEventKind::ScrollUp => page = 1 - page,
                    MouseEventKind::Down(_) if m.row <= 2 => {
                        page = usize::from(m.column > 13);
                    }
                    _ => {}
                },
                _ => {}
            }
        }
    }
    Ok(())
}
