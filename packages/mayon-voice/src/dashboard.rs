use crate::{client, Config, Result};
use crossterm::event::{self, Event, KeyCode, MouseEventKind};
use mayon_ui::{
    base, block, blue,
    input::TextInput,
    muted,
    search::{Matcher, SearchCache},
    terminal,
    theme::*,
};
use ratatui::{
    layout::{Constraint, Layout},
    text::{Line, Span},
    widgets::{Paragraph, Wrap},
};
use std::time::{Duration, Instant};
fn filter_lines(
    lines: Vec<Line<'static>>,
    filter: &TextInput,
    cache: &SearchCache,
    help: bool,
) -> (Vec<usize>, Vec<Line<'static>>) {
    let matcher = Matcher::new(if help { "" } else { filter.as_str() });
    let mut ids = Vec::new();
    let mut visible = Vec::new();
    for (id, line) in lines.into_iter().enumerate() {
        let text = line.to_string();
        if let Some(hit) = cache.find(&matcher, &text) {
            ids.push(id);
            visible.push(if help || filter.is_empty() {
                line
            } else {
                mayon_ui::search::highlight(&text, &hit.ranges)
            });
        }
    }
    if visible.is_empty() {
        visible.push(Line::raw("没有匹配 · Esc 清除过滤"));
    }
    (ids, visible)
}
fn preserve_line(selected: usize, previous: &[usize], next: &[usize]) -> usize {
    previous
        .get(selected)
        .and_then(|id| next.iter().position(|value| value == id))
        .unwrap_or(0)
}
pub fn run() -> Result<()> {
    let (mut terminal, _guard) = terminal()?;
    let config = Config::load()?;
    let mut page = 0;
    let mut help = false;
    let mut filter = TextInput::default();
    let mut previous_filter = TextInput::default();
    let mut scroll = 0usize;
    let mut visible_ids = Vec::<usize>::new();
    let cache = SearchCache::default();
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
                    Line::from(" 鼠标滚轮滚动；点击顶部页签切页"),
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
            let total = lines.len();
            let (ids, lines) = filter_lines(lines, &filter, &cache, help);
            let count = ids.len();
            if !help {
                scroll = preserve_line(scroll, &visible_ids, &ids);
                visible_ids = ids;
            }
            f.render_widget(
                Paragraph::new(lines)
                    .style(base())
                    .block(block(
                        format!(" 语音输入 · {count}/{total} · /{filter} "),
                        true,
                    ))
                    .scroll((
                        if help {
                            0
                        } else {
                            scroll.min(u16::MAX as usize) as u16
                        },
                        0,
                    ))
                    .wrap(Wrap { trim: false }),
                areas[2],
            );
            if filtering {
                filter.render(f, areas[3], base().fg(BLUE));
            }
            if !filtering {
                f.render_widget(
                    Paragraph::new(" 空格 录音  1/2 切页  / 过滤  ? 帮助  q 退出")
                        .style(base().fg(MUTED)),
                    areas[3],
                );
            }
        })?;
        if event::poll(Duration::from_millis(100))? {
            match event::read()? {
                Event::Key(k) if k.kind == event::KeyEventKind::Press => {
                    if help {
                        if matches!(
                            k.code,
                            KeyCode::Esc | KeyCode::Char('?') | KeyCode::Char('q')
                        ) {
                            help = false;
                        }
                        continue;
                    }
                    if filtering {
                        match k.code {
                            KeyCode::Esc => {
                                filtering = false;
                                filter = previous_filter.clone();
                            }
                            KeyCode::Enter => filtering = false,
                            KeyCode::Down => {
                                scroll = (scroll + 1).min(visible_ids.len().saturating_sub(1))
                            }
                            KeyCode::Up => scroll = scroll.saturating_sub(1),
                            _ => {
                                filter.handle_key(k);
                            }
                        }
                        continue;
                    }
                    if k.modifiers
                        .intersects(event::KeyModifiers::CONTROL | event::KeyModifiers::ALT)
                    {
                        continue;
                    }
                    match k.code {
                        KeyCode::Char('q') => break,
                        KeyCode::Esc if help => help = false,
                        KeyCode::Esc if !filter.is_empty() => {
                            filter.clear();
                        }
                        KeyCode::Esc => break,
                        KeyCode::Down => {
                            scroll = (scroll + 1).min(visible_ids.len().saturating_sub(1))
                        }
                        KeyCode::Up => scroll = scroll.saturating_sub(1),
                        KeyCode::PageDown => {
                            scroll = (scroll + 8).min(visible_ids.len().saturating_sub(1))
                        }
                        KeyCode::PageUp => scroll = scroll.saturating_sub(8),
                        KeyCode::Home | KeyCode::Char('g') => scroll = 0,
                        KeyCode::End | KeyCode::Char('G') => {
                            scroll = visible_ids.len().saturating_sub(1)
                        }
                        KeyCode::Char('1') => {
                            page = 0;
                            scroll = 0;
                            visible_ids.clear();
                        }
                        KeyCode::Char('2') => {
                            page = 1;
                            scroll = 0;
                            visible_ids.clear();
                        }
                        KeyCode::Char('?') => help = !help,
                        KeyCode::Char('/') => {
                            previous_filter = filter.clone();
                            filtering = true;
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
                Event::Paste(text) if filtering && !help => {
                    filter.paste(&text);
                }
                Event::Mouse(m) => match m.kind {
                    MouseEventKind::ScrollDown => {
                        scroll = (scroll + 1).min(visible_ids.len().saturating_sub(1))
                    }
                    MouseEventKind::ScrollUp => scroll = scroll.saturating_sub(1),
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

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn help_stays_visible_without_changing_the_retained_query() {
        let cache = SearchCache::default();
        let filter = TextInput::from("无匹配内容");
        let (ids, lines) = filter_lines(
            vec![Line::raw("快捷键"), Line::raw("Esc 关闭帮助")],
            &filter,
            &cache,
            true,
        );
        assert_eq!(ids, vec![0, 1]);
        assert_eq!(lines[0].to_string(), "快捷键");
        assert_eq!(filter.as_str(), "无匹配内容");
    }
    #[test]
    fn dashboard_filter_is_incremental_keeps_line_and_renders_empty() {
        let cache = SearchCache::default();
        let original = || vec![Line::raw("模型 本地"), Line::raw("设备 CPU")];
        let mut filter = TextInput::default();
        let (before, _) = filter_lines(original(), &filter, &cache, false);
        filter.paste("shebei");
        let (after, visible) = filter_lines(original(), &filter, &cache, false);
        assert_eq!(after, vec![1]);
        assert_eq!(preserve_line(1, &before, &after), 0);
        assert!(visible[0].to_string().contains("设备"));
        filter.set("不存在");
        let (empty, lines) = filter_lines(original(), &filter, &cache, false);
        assert!(empty.is_empty());
        assert_eq!(preserve_line(0, &after, &empty), 0);
        let mut terminal =
            ratatui::Terminal::new(ratatui::backend::TestBackend::new(60, 8)).unwrap();
        terminal
            .draw(|f| f.render_widget(Paragraph::new(lines.clone()), f.area()))
            .unwrap();
        let text = terminal
            .backend()
            .buffer()
            .content
            .iter()
            .map(|c| c.symbol())
            .collect::<String>()
            .replace(' ', "");
        assert!(text.contains("没有匹配"));
        assert!(text.contains("Esc"));
    }
}
