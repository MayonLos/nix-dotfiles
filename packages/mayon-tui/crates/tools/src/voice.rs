use crossterm::event::{self, Event, KeyCode, MouseEventKind};
use mayon_ui::{
    base, block, blue,
    input::TextInput,
    muted,
    search::{Matcher, SearchCache},
    theme::*,
};
use mayon_voice::{client_with_timeout, Config, Result};
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
pub struct Screen {
    config: Config,
    page: usize,
    help: bool,
    filter: TextInput,
    previous_filter: TextInput,
    scroll: usize,
    visible_ids: Vec<usize>,
    cache: SearchCache,
    filtering: bool,
    status: serde_json::Value,
    refreshed: Instant,
    error_until: Option<Instant>,
    tx: tokio::sync::mpsc::Sender<serde_json::Value>,
    rx: tokio::sync::mpsc::Receiver<serde_json::Value>,
    job: Option<tokio::task::JoinHandle<()>>,
}
impl Screen {
    pub fn new() -> Result<Self> {
        let (tx, rx) = tokio::sync::mpsc::channel(4);
        Ok(Self {
            config: Config::load()?,
            page: 0,
            help: false,
            filter: TextInput::default(),
            previous_filter: TextInput::default(),
            scroll: 0,
            visible_ids: Vec::new(),
            cache: SearchCache::default(),
            filtering: false,
            status: serde_json::json!({"phase":"inactive"}),
            refreshed: Instant::now() - Duration::from_secs(1),
            error_until: None,
            tx,
            rx,
            job: None,
        })
    }
    fn request(&mut self, command: &'static str) {
        if let Some(job) = self.job.take() {
            job.abort();
        }
        let tx = self.tx.clone();
        self.refreshed = Instant::now();
        self.job = Some(tokio::spawn(async move {
            let status = match tokio::task::spawn_blocking(move || {
                client_with_timeout(command, Duration::from_millis(500))
            })
            .await
            {
                Ok(Ok(status)) => status,
                Ok(Err(error)) if command != "status" => {
                    serde_json::json!({"phase":"error","error":format!("语音操作失败：{error}")})
                }
                Err(error) => {
                    serde_json::json!({"phase":"error","error":format!("语音请求失败：{error}")})
                }
                _ => serde_json::json!({"phase":"inactive"}),
            };
            let _ = tx.send(status).await;
        }));
    }
    pub fn tick(&mut self) {
        if self.job.as_ref().is_some_and(|j| j.is_finished()) {
            self.job = None;
        }
        if self.refreshed.elapsed() >= Duration::from_millis(500) && self.job.is_none() {
            self.request("status");
        }
    }
    pub fn deadline(&self) -> Instant {
        if self.job.is_some() {
            Instant::now() + Duration::from_secs(3600)
        } else {
            self.refreshed + Duration::from_millis(500)
        }
    }
    pub async fn changed(&mut self) -> bool {
        if let Some(mut status) = self.rx.recv().await {
            if status["phase"] == "error" {
                self.error_until = Some(Instant::now() + Duration::from_secs(5));
            } else if self.error_until.is_some_and(|until| Instant::now() < until) {
                status["error"] = self.status["error"].clone();
            }
            let changed = self.status != status;
            self.status = status;
            self.job = None;
            changed
        } else {
            false
        }
    }
    pub fn suspend(&mut self) {
        if let Some(job) = self.job.take() {
            job.abort();
        }
    }
    pub fn resume(&mut self) {
        self.refreshed = Instant::now() - Duration::from_secs(1);
    }
    pub fn editing(&self) -> bool {
        self.filtering
    }
    pub fn draw(&mut self, f: &mut ratatui::Frame, area: ratatui::layout::Rect) {
        let areas = Layout::vertical([
            Constraint::Length(1),
            Constraint::Length(2),
            Constraint::Min(4),
            Constraint::Length(2),
        ])
        .split(area);
        f.render_widget(
            Paragraph::new(" 语音输入 · 本地中文识别").style(base().fg(BRIGHTFG)),
            areas[0],
        );
        f.render_widget(
            Paragraph::new(mayon_ui::tabs_line(&["状态", "配置"], self.page)).style(base()),
            areas[1],
        );
        let (phase, color) = match self.status["phase"].as_str().unwrap_or("inactive") {
            "recording" => ("● 录音中", GREEN),
            "transcribing" => ("◌ 识别中", YELLOW),
            "idle" => ("○ 就绪", GREEN),
            "error" => ("! 操作失败", RED),
            _ => ("○ 按需待命", MUTED),
        };
        let lines = if self.help {
            vec![
                Line::from(blue(" 快捷键")),
                Line::from(" 空格 开始/结束录音    1/2 切页"),
                Line::from(" / 过滤信息            ? 关闭帮助"),
                Line::from(" q 退出界面（录音与服务独立运行）"),
                Line::from(" 鼠标滚轮滚动；点击顶部页签切页"),
            ]
        } else if self.page == 0 {
            vec![
                Line::from(vec![blue("▏ "), Span::styled(phase, base().fg(color))]),
                Line::from(""),
                Line::from(format!(
                    " 引擎       {} / {}",
                    self.config.engine, self.config.device
                )),
                Line::from(format!(
                    " 上屏       {}",
                    self.status["delivery"]
                        .as_str()
                        .unwrap_or(&self.config.delivery)
                )),
                Line::from(""),
                Line::from(muted(" 按空格说话，再按一次结束。")),
                Line::from(muted(" 录音只暂存在私有 runtime；不保留转写历史。")),
                Line::from(format!(
                    " 提示       {}",
                    self.status["error"]
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
                        &self
                            .config
                            .model_dir
                            .strip_prefix(mayon_voice::home())
                            .map(|p| format!("~/{}", p.display()))
                            .unwrap_or_else(|_| self.config.model_dir.display().to_string()),
                        areas[2].width.saturating_sub(15) as usize
                    )
                )),
                Line::from(format!(
                    " 设备       {} / {} threads",
                    self.config.device, self.config.threads
                )),
                Line::from(format!(" 麦克风     {}", self.config.input_device)),
                Line::from(format!(" 热词       {}", self.config.hotwords.join("、"))),
                Line::from(format!(
                    " AI 润色    {}",
                    if self.config.polish {
                        "开启 · 最多 3s，失败回退"
                    } else {
                        "关闭"
                    }
                )),
                Line::from(format!(" 空闲退出   {}s", self.config.idle_seconds)),
                Line::from(muted(" 配置由用户维护；下次守护进程启动读取。")),
            ]
        };
        let total = lines.len();
        let (ids, lines) = filter_lines(lines, &self.filter, &self.cache, self.help);
        let count = ids.len();
        if !self.help {
            self.scroll = preserve_line(self.scroll, &self.visible_ids, &ids);
            self.visible_ids = ids;
        }
        f.render_widget(
            Paragraph::new(lines)
                .style(base())
                .block(block(
                    if self.filter.is_empty() {
                        format!(" 语音输入 · {count}/{total} ")
                    } else {
                        format!(" 语音输入 · {count}/{total} · /{} ", self.filter)
                    },
                    true,
                ))
                .scroll((
                    if self.help {
                        0
                    } else {
                        self.scroll.min(u16::MAX as usize) as u16
                    },
                    0,
                ))
                .wrap(Wrap { trim: false }),
            areas[2],
        );
        if self.filtering {
            self.filter.render(f, areas[3], base().fg(BLUE));
        }
        if !self.filtering {
            f.render_widget(
                Paragraph::new(mayon_ui::hint_line(
                    if self.help {
                        "? 关闭帮助  ↑/↓ 滚动"
                    } else {
                        "空格 录音  1/2 切页  / 过滤  ? 帮助  q 退出"
                    },
                    areas[3].width as usize,
                ))
                .style(base()),
                areas[3],
            );
        }
    }
    pub fn event(&mut self, event: Event) -> bool {
        match event {
            Event::Key(k) if k.kind == event::KeyEventKind::Press => {
                if self.help {
                    if matches!(
                        k.code,
                        KeyCode::Esc | KeyCode::Char('?') | KeyCode::Char('q')
                    ) {
                        self.help = false;
                    }
                    return false;
                }
                if self.filtering {
                    match k.code {
                        KeyCode::Esc => {
                            self.filtering = false;
                            self.filter = self.previous_filter.clone();
                        }
                        KeyCode::Enter => self.filtering = false,
                        KeyCode::Down => {
                            self.scroll =
                                (self.scroll + 1).min(self.visible_ids.len().saturating_sub(1))
                        }
                        KeyCode::Up => self.scroll = self.scroll.saturating_sub(1),
                        _ => {
                            self.filter.handle_key(k);
                        }
                    }
                    return false;
                }
                if k.modifiers
                    .intersects(event::KeyModifiers::CONTROL | event::KeyModifiers::ALT)
                {
                    return false;
                }
                match k.code {
                    KeyCode::Char('q') => return true,
                    KeyCode::Esc if self.help => self.help = false,
                    KeyCode::Esc if !self.filter.is_empty() => {
                        self.filter.clear();
                    }
                    KeyCode::Esc => return true,
                    KeyCode::Down => {
                        self.scroll =
                            (self.scroll + 1).min(self.visible_ids.len().saturating_sub(1))
                    }
                    KeyCode::Up => self.scroll = self.scroll.saturating_sub(1),
                    KeyCode::PageDown => {
                        self.scroll =
                            (self.scroll + 8).min(self.visible_ids.len().saturating_sub(1))
                    }
                    KeyCode::PageUp => self.scroll = self.scroll.saturating_sub(8),
                    KeyCode::Home | KeyCode::Char('g') => self.scroll = 0,
                    KeyCode::End | KeyCode::Char('G') => {
                        self.scroll = self.visible_ids.len().saturating_sub(1)
                    }
                    KeyCode::Char('1') => {
                        self.page = 0;
                        self.scroll = 0;
                        self.visible_ids.clear();
                    }
                    KeyCode::Char('2') => {
                        self.page = 1;
                        self.scroll = 0;
                        self.visible_ids.clear();
                    }
                    KeyCode::Char('?') => self.help = !self.help,
                    KeyCode::Char('/') => {
                        self.previous_filter = self.filter.clone();
                        self.filtering = true;
                    }
                    KeyCode::Char(' ') => {
                        self.request("toggle");
                    }
                    _ => {}
                }
            }
            Event::Paste(text) if self.filtering && !self.help => {
                self.filter.paste(&text);
            }
            Event::Mouse(m) => match m.kind {
                MouseEventKind::ScrollDown => {
                    self.scroll = (self.scroll + 1).min(self.visible_ids.len().saturating_sub(1))
                }
                MouseEventKind::ScrollUp => self.scroll = self.scroll.saturating_sub(1),
                MouseEventKind::Down(_) if m.row <= 2 => {
                    self.page = usize::from(m.column > 13);
                }
                _ => {}
            },
            _ => {}
        };
        false
    }
}
impl Drop for Screen {
    fn drop(&mut self) {
        self.suspend();
    }
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
