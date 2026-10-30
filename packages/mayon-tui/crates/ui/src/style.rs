use crate::{base, block, centered, fit_hint, theme::*};
use ratatui::{
    layout::{Margin, Rect},
    style::Style,
    text::{Line, Span},
    widgets::{Clear, Paragraph, Wrap},
    Frame,
};
use std::time::{Duration, Instant};

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Tone {
    #[default]
    Info,
    Action,
    Success,
    Warning,
    Error,
}
impl Tone {
    pub fn color(self) -> ratatui::style::Color {
        match self {
            Self::Info => MUTED,
            Self::Action => BLUE,
            Self::Success => GREEN,
            Self::Warning => YELLOW,
            Self::Error => RED,
        }
    }
    pub fn symbol(self) -> &'static str {
        match self {
            Self::Info => "·",
            Self::Action => "›",
            Self::Success => "✓",
            Self::Warning => "!",
            Self::Error => "×",
        }
    }
}
pub fn message(text: impl Into<String>, tone: Tone) -> Line<'static> {
    Line::from(vec![
        Span::styled(
            format!("{} ", tone.symbol()),
            Style::default().fg(tone.color()),
        ),
        Span::styled(text.into(), Style::default().fg(tone.color())),
    ])
}
pub fn hint_line(hint: &str, width: usize) -> Line<'static> {
    let fitted = fit_hint(hint, width);
    let mut spans = Vec::new();
    for part in fitted.split("  ").filter(|s| !s.is_empty()) {
        if !spans.is_empty() {
            spans.push(Span::raw("  "));
        }
        let (key, description) = part.trim().split_once(' ').unwrap_or((part, ""));
        spans.push(Span::styled(key.to_owned(), Style::default().fg(BLUE)));
        if !description.is_empty() {
            spans.push(Span::styled(
                format!(" {description}"),
                Style::default().fg(MUTED),
            ));
        }
    }
    Line::from(spans)
}
pub fn numeric(text: impl Into<String>) -> Line<'static> {
    Line::raw(text.into()).right_aligned()
}
pub fn modal(frame: &mut Frame, title: &str, width: u16, height: u16, tone: Tone) -> Rect {
    let area = centered(frame.area(), width, height);
    frame.render_widget(Clear, area);
    frame.render_widget(
        block("", true)
            .style(base().bg(SURFACE))
            .title(Span::styled(
                format!(" {} {title} ", tone.symbol()),
                Style::default().fg(tone.color()),
            )),
        area,
    );
    area.inner(Margin {
        horizontal: 2,
        vertical: 1,
    })
}
pub fn dialog_tone(frame: &mut Frame, title: &str, body: &str, tone: Tone) {
    use unicode_width::UnicodeWidthStr;
    let width = 80u16.min(frame.area().width.saturating_sub(2));
    let usable = width.saturating_sub(4).max(1) as usize;
    let lines: usize = body
        .lines()
        .map(|s| s.width().max(1).div_ceil(usable))
        .sum();
    let height = lines.saturating_add(4).clamp(5, u16::MAX as usize) as u16;
    let inner = modal(frame, title, width, height, tone);
    frame.render_widget(
        Paragraph::new(body.to_owned())
            .style(base().bg(SURFACE))
            .wrap(Wrap { trim: false }),
        inner,
    );
}
pub fn error_dialog(frame: &mut Frame, title: &str, body: &str) {
    dialog_tone(frame, title, body, Tone::Error);
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ListState {
    Empty,
    Loading,
    Error,
}
pub fn list_state(frame: &mut Frame, area: Rect, state: ListState, detail: &str) {
    let (label, tone) = match state {
        ListState::Empty => ("没有匹配项", Tone::Info),
        ListState::Loading => ("正在加载…", Tone::Info),
        ListState::Error => ("加载失败", Tone::Error),
    };
    frame.render_widget(
        Paragraph::new(vec![
            message(label, tone),
            Line::raw(""),
            Line::from(crate::muted(detail)),
        ])
        .style(base())
        .wrap(Wrap { trim: false }),
        area.inner(Margin {
            horizontal: 1,
            vertical: 1,
        }),
    );
}
#[derive(Debug, Default)]
pub struct Notice {
    text: String,
    tone: Tone,
    until: Option<Instant>,
}
impl Notice {
    pub fn set(&mut self, text: impl Into<String>, tone: Tone) {
        self.text = text.into();
        self.tone = tone;
        self.until = Some(Instant::now() + Duration::from_secs(5));
    }
    pub fn visible(&self) -> Option<(&str, Tone)> {
        self.until
            .filter(|t| *t > Instant::now())
            .map(|_| (self.text.as_str(), self.tone))
    }
    pub fn deadline(&self) -> Option<Instant> {
        self.until
    }
    pub fn expire(&mut self) -> bool {
        if self.until.is_some_and(|t| t <= Instant::now()) {
            self.text.clear();
            self.until = None;
            return true;
        }
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn notices_expire_without_a_periodic_redraw() {
        let mut notice = Notice::default();
        notice.set("完成", Tone::Success);
        assert_eq!(notice.visible(), Some(("完成", Tone::Success)));
        notice.until = Some(Instant::now() - Duration::from_secs(1));
        assert!(notice.expire());
        assert!(notice.visible().is_none());
        assert!(notice.deadline().is_none());
    }
    #[test]
    fn modal_padding_and_empty_states_fit_narrow_frames() {
        let mut terminal =
            ratatui::Terminal::new(ratatui::backend::TestBackend::new(80, 24)).unwrap();
        terminal
            .draw(|frame| {
                let area = modal(frame, "Failure", 80, 7, Tone::Error);
                assert!(area.x >= 3 && area.width <= 74);
                list_state(frame, area, ListState::Error, "r 重试 · Esc 返回");
            })
            .unwrap();
        let screen = terminal
            .backend()
            .buffer()
            .content
            .iter()
            .map(|cell| cell.symbol())
            .collect::<String>();
        assert_eq!(screen.matches("Failure").count(), 1);
        for (width, height) in [(1, 1), (12, 3)] {
            let mut terminal =
                ratatui::Terminal::new(ratatui::backend::TestBackend::new(width, height)).unwrap();
            terminal
                .draw(|frame| dialog_tone(frame, "错误", "中文很长的错误原因", Tone::Error))
                .unwrap();
        }
    }
    #[test]
    fn hints_style_keys_and_preserve_complete_pairs() {
        let line = hint_line("j/k 移动  Enter 打开  ? 帮助", 16);
        assert_eq!(line.spans[0].style.fg, Some(BLUE));
        assert!(line.to_string().contains("? 更多"));
        assert!(!line.to_string().contains("Ent…"));
    }
}
