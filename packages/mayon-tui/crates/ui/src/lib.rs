//! Shared One Dark widgets and terminal lifecycle for Mayon's small tools.
pub mod theme;
use crossterm::{
    event::{DisableMouseCapture, EnableMouseCapture},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    layout::{Constraint, Layout, Rect},
    style::{Modifier, Style},
    text::{Line, Span},
    widgets::{Block, BorderType, Borders, Cell, Clear, Paragraph, Row, Table, TableState, Wrap},
    Frame,
};
use std::io;
use theme::*;
pub fn base() -> Style {
    Style::default().fg(FG).bg(BG)
}
pub fn muted(text: impl Into<String>) -> Span<'static> {
    Span::styled(text.into(), Style::default().fg(MUTED))
}
pub fn blue(text: impl Into<String>) -> Span<'static> {
    Span::styled(text.into(), Style::default().fg(BLUE))
}
pub fn block(title: impl Into<String>, focused: bool) -> Block<'static> {
    Block::default()
        .borders(Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::default().fg(if focused { BLUE } else { BORDER }))
        .title(Span::styled(
            title.into(),
            Style::default().fg(if focused { BLUE } else { FG }),
        ))
}
pub fn marker(selected: bool) -> Span<'static> {
    blue(if selected { "▏" } else { " " })
}
pub fn status(frame: &mut Frame, area: Rect, text: &str) {
    frame.render_widget(
        Paragraph::new(clip(text, area.width as usize)).style(base().fg(BRIGHTFG)),
        area,
    );
}
pub fn tabs_line(tabs: &[&str], page: usize) -> Line<'static> {
    let mut spans = vec![Span::raw(" ")];
    for (i, t) in tabs.iter().enumerate() {
        spans.push(Span::styled(
            format!(" {} {t} ", i + 1),
            if i == page {
                Style::default().fg(BLUE).add_modifier(Modifier::UNDERLINED)
            } else {
                Style::default().fg(MUTED)
            },
        ));
        spans.push(Span::raw("  "));
    }
    Line::from(spans)
}
/// Keep complete key/action pairs; reserve the help action at narrow widths.
pub fn fit_hint(hint: &str, width: usize) -> String {
    use unicode_width::UnicodeWidthStr;
    if hint.width() <= width {
        return hint.into();
    }
    let more = "? 更多";
    let mut out = String::new();
    for part in hint.split("  ").map(str::trim).filter(|s| !s.is_empty()) {
        if part.starts_with('?') {
            break;
        }
        let next = if out.is_empty() {
            part.to_string()
        } else {
            format!("{out}  {part}")
        };
        if next.width() + 2 + more.width() > width {
            break;
        }
        out = next;
    }
    if out.is_empty() {
        clip(more, width)
    } else {
        format!("{out}  {more}")
    }
}

pub fn footer(frame: &mut Frame, area: Rect, hint: &str, message: &str) {
    frame.render_widget(
        Paragraph::new(vec![
            Line::from(muted(fit_hint(hint, area.width as usize))),
            Line::from(blue(clip(message, area.width as usize))),
        ]),
        area,
    );
}
/// Header, tabs, body, and two footer lines. All widths are terminal cells.
pub fn chrome(
    frame: &mut Frame,
    title: &str,
    tabs: &[&str],
    page: usize,
    hint: &str,
    message: &str,
) -> Rect {
    let a = frame.area();
    frame.render_widget(Block::default().style(base()), a);
    let c = Layout::vertical([
        Constraint::Length(1),
        Constraint::Length(2),
        Constraint::Min(1),
        Constraint::Length(2),
    ])
    .split(a);
    status(frame, c[0], title);
    frame.render_widget(Paragraph::new(tabs_line(tabs, page)), c[1]);
    footer(frame, c[3], hint, message);
    c[2]
}
pub fn centered(area: Rect, width: u16, height: u16) -> Rect {
    let w = width.min(area.width.saturating_sub(2));
    let h = height.min(area.height.saturating_sub(2));
    Rect::new(
        area.x + (area.width - w) / 2,
        area.y + (area.height - h) / 2,
        w,
        h,
    )
}
pub fn dialog(frame: &mut Frame, title: &str, body: &str) {
    use unicode_width::UnicodeWidthStr;
    let width = 76u16.min(frame.area().width.saturating_sub(2));
    let inner = width.saturating_sub(2).max(1) as usize;
    let lines = body
        .lines()
        .map(|line| line.width().max(1).div_ceil(inner))
        .sum::<usize>();
    let height = lines.saturating_add(4).min(u16::MAX as usize) as u16;
    let a = centered(frame.area(), width, height.max(7));
    frame.render_widget(Clear, a);
    frame.render_widget(
        Paragraph::new(body.to_owned())
            .style(base())
            .block(block(title, true))
            .wrap(Wrap { trim: false }),
        a,
    );
}
pub fn help(frame: &mut Frame, body: &str) {
    dialog(frame, " 帮助 · ? / Esc 关闭 ", body);
}
pub fn input(frame: &mut Frame, title: &str, value: &str) {
    dialog(frame, title, &format!("{value}▏\n\nEnter 确认 · Esc 取消"));
}
pub fn table(
    frame: &mut Frame,
    area: Rect,
    title: &str,
    headers: Vec<&str>,
    rows: Vec<Vec<String>>,
    widths: &[Constraint],
    selected: usize,
) {
    let usable = area.width.saturating_sub(2);
    let mut ws = vec![Constraint::Length(1)];
    ws.extend_from_slice(widths);
    let columns = Layout::horizontal(ws.clone())
        .spacing(1)
        .split(Rect::new(0, 0, usable, 1));
    let rows = rows.into_iter().enumerate().map(|(i, mut r)| {
        let mut cells: Vec<Cell<'static>> = r
            .drain(..)
            .enumerate()
            .map(|(j, value)| {
                Cell::from(clip(
                    &value,
                    columns.get(j + 1).map_or(0, |c| c.width as usize),
                ))
            })
            .collect();
        cells.insert(0, Cell::from(marker(i == selected)));
        Row::new(cells).style(if i == selected {
            base().bg(SELECTION)
        } else {
            base()
        })
    });
    let mut hs = vec![""];
    hs.extend(headers);
    let table = Table::new(rows, ws)
        .header(Row::new(hs).style(Style::default().fg(MUTED)))
        .column_spacing(1)
        .block(block(title, true));
    let mut state = TableState::default().with_selected(Some(selected));
    frame.render_stateful_widget(table, area, &mut state);
}
pub type Terminal = ratatui::Terminal<ratatui::backend::CrosstermBackend<io::Stdout>>;
pub struct TerminalGuard;
fn restore() {
    let _ = disable_raw_mode();
    let _ = execute!(io::stdout(), DisableMouseCapture, LeaveAlternateScreen);
}
impl Drop for TerminalGuard {
    fn drop(&mut self) {
        restore();
    }
}
pub fn terminal() -> io::Result<(Terminal, TerminalGuard)> {
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        restore();
        previous(info);
    }));
    enable_raw_mode()?;
    let guard = TerminalGuard;
    execute!(io::stdout(), EnterAlternateScreen, EnableMouseCapture)?;
    Ok((
        Terminal::new(ratatui::backend::CrosstermBackend::new(io::stdout()))?,
        guard,
    ))
}
/// One in-flight refresh; completions cross a channel, never drawing from workers.
pub struct Refresh<T: Send + 'static> {
    tx: tokio::sync::mpsc::UnboundedSender<T>,
    rx: tokio::sync::mpsc::UnboundedReceiver<T>,
    job: Option<tokio::task::JoinHandle<()>>,
}
impl<T: Send + 'static> Default for Refresh<T> {
    fn default() -> Self {
        let (tx, rx) = tokio::sync::mpsc::unbounded_channel();
        Self { tx, rx, job: None }
    }
}
impl<T: Send + 'static> Refresh<T> {
    pub fn start(&mut self, future: impl std::future::Future<Output = T> + Send + 'static) {
        if self.job.as_ref().is_some_and(|j| !j.is_finished()) {
            return;
        }
        let tx = self.tx.clone();
        self.job = Some(tokio::spawn(async move {
            let _ = tx.send(future.await);
        }));
    }
    pub fn take(&mut self) -> Option<T> {
        self.rx.try_recv().ok()
    }
}
impl<T: Send + 'static> Drop for Refresh<T> {
    fn drop(&mut self) {
        if let Some(j) = self.job.take() {
            j.abort();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn hints_preserve_complete_actions() {
        assert_eq!(
            fit_hint(" j/k 移动  d 删除容器  ? 帮助", 23),
            "j/k 移动  ? 更多"
        );
        assert!(!fit_hint(" j/k 移动  d 删除容器  ? 帮助", 23).contains("d …"));
    }
}
