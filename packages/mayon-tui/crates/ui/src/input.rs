use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use ratatui::{
    layout::Rect,
    style::Style,
    text::Line,
    widgets::{Block, Clear},
    Frame,
};
use std::{fmt, ops::Deref};
use unicode_width::UnicodeWidthChar;

pub const MAX_INPUT_CHARS: usize = 4096;

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct TextInput {
    value: String,
    cursor: usize,
}

impl TextInput {
    pub fn new(value: impl Into<String>) -> Self {
        let mut input = Self::default();
        input.set(value);
        input
    }

    pub fn as_str(&self) -> &str {
        &self.value
    }
    pub fn is_empty(&self) -> bool {
        self.value.is_empty()
    }
    pub fn len(&self) -> usize {
        self.value.chars().count()
    }
    pub fn cursor(&self) -> usize {
        self.cursor
    }

    pub fn clear(&mut self) {
        self.value.clear();
        self.cursor = 0;
    }

    pub fn set(&mut self, value: impl Into<String>) {
        self.value = sanitize(value.into());
        self.cursor = self.len();
    }

    pub fn push(&mut self, ch: char) {
        if self.len() >= MAX_INPUT_CHARS || ch.is_control() {
            return;
        }
        let byte = byte_at(&self.value, self.cursor);
        self.value.insert(byte, ch);
        self.cursor += 1;
    }

    pub fn pop(&mut self) -> Option<char> {
        if self.cursor == 0 {
            return None;
        }
        let start = byte_at(&self.value, self.cursor - 1);
        let end = byte_at(&self.value, self.cursor);
        let removed = self.value[start..end].chars().next();
        self.value.replace_range(start..end, "");
        self.cursor -= 1;
        removed
    }

    /// Insert a paste as one line. Newlines become spaces and other controls are dropped.
    pub fn paste(&mut self, text: &str) -> bool {
        let mut changed = false;
        let mut chars = text.chars().peekable();
        while let Some(ch) = chars.next() {
            let ch = if ch == '\r' {
                if chars.peek() == Some(&'\n') {
                    chars.next();
                }
                ' '
            } else if ch == '\n' {
                ' '
            } else {
                ch
            };
            if ch.is_control() || self.len() >= MAX_INPUT_CHARS {
                continue;
            }
            let byte = byte_at(&self.value, self.cursor);
            self.value.insert(byte, ch);
            self.cursor += 1;
            changed = true;
        }
        changed
    }

    /// Handle editing keys; return true only when the text content changed.
    pub fn handle_key(&mut self, key: KeyEvent) -> bool {
        let ctrl = key.modifiers.contains(KeyModifiers::CONTROL);
        let alt = key.modifiers.contains(KeyModifiers::ALT);
        if ctrl && !alt {
            match key.code {
                KeyCode::Char('a' | 'A') => {
                    self.cursor = 0;
                    return false;
                }
                KeyCode::Char('e' | 'E') => {
                    self.cursor = self.len();
                    return false;
                }
                KeyCode::Char('u' | 'U') => return self.remove_to_cursor(),
                KeyCode::Char('k' | 'K') => return self.remove_to_end(),
                KeyCode::Char('w' | 'W') => return self.remove_previous_word(),
                _ => return false,
            }
        }
        if alt {
            if key.code == KeyCode::Backspace {
                return self.remove_previous_word();
            }
            return false;
        }
        match key.code {
            KeyCode::Left => {
                self.cursor = self.cursor.saturating_sub(1);
                false
            }
            KeyCode::Right => {
                self.cursor = (self.cursor + 1).min(self.len());
                false
            }
            KeyCode::Home => {
                self.cursor = 0;
                false
            }
            KeyCode::End => {
                self.cursor = self.len();
                false
            }
            KeyCode::Backspace => self.pop().is_some(),
            KeyCode::Delete => self.remove_after_cursor(),
            KeyCode::Char(ch)
                if !key.modifiers.intersects(
                    KeyModifiers::CONTROL | KeyModifiers::ALT | KeyModifiers::SUPER,
                ) =>
            {
                let before = self.value.len();
                self.push(ch);
                self.value.len() != before
            }
            _ => false,
        }
    }

    /// Draw a one-line input, scrolling horizontally as needed and setting the real terminal cursor.
    pub fn render(&self, frame: &mut Frame, area: Rect, style: Style) {
        self.render_text(&self.value, frame, area, style);
    }

    /// Draw one mask character per input character while preserving the real cursor location.
    pub fn render_masked(&self, frame: &mut Frame, area: Rect, style: Style) {
        let masked = "*".repeat(self.len());
        self.render_text(&masked, frame, area, style);
    }

    fn render_text(&self, text: &str, frame: &mut Frame, area: Rect, style: Style) {
        let area = area.intersection(frame.area());
        if area.width == 0 || area.height == 0 {
            return;
        }
        let cursor_width = text
            .chars()
            .take(self.cursor)
            .map(|ch| ch.width().unwrap_or(0))
            .sum::<usize>();
        let mut start_width = 0usize;
        let mut start_char = 0usize;
        if cursor_width >= area.width as usize {
            let target = cursor_width.saturating_sub(area.width as usize - 1);
            for ch in text.chars().take(self.cursor) {
                if start_width >= target {
                    break;
                }
                start_width += ch.width().unwrap_or(0);
                start_char += 1;
            }
        }
        let mut visible = String::new();
        let mut used = 0usize;
        for ch in text.chars().skip(start_char) {
            let width = ch.width().unwrap_or(0);
            if used + width > area.width as usize {
                break;
            }
            visible.push(ch);
            used += width;
        }
        frame.render_widget(Clear, area);
        frame.render_widget(Block::default().style(style), area);
        frame.render_widget(Line::styled(visible, style), area);
        let x_offset = cursor_width
            .saturating_sub(start_width)
            .min(area.width.saturating_sub(1) as usize) as u16;
        frame.set_cursor_position((area.x + x_offset, area.y));
    }

    fn remove_to_cursor(&mut self) -> bool {
        if self.cursor == 0 {
            return false;
        }
        let end = byte_at(&self.value, self.cursor);
        self.value.replace_range(..end, "");
        self.cursor = 0;
        true
    }

    fn remove_to_end(&mut self) -> bool {
        if self.cursor >= self.len() {
            return false;
        }
        let start = byte_at(&self.value, self.cursor);
        self.value.replace_range(start.., "");
        true
    }

    fn remove_after_cursor(&mut self) -> bool {
        if self.cursor >= self.len() {
            return false;
        }
        let start = byte_at(&self.value, self.cursor);
        let end = byte_at(&self.value, self.cursor + 1);
        self.value.replace_range(start..end, "");
        true
    }

    fn remove_previous_word(&mut self) -> bool {
        if self.cursor == 0 {
            return false;
        }
        let chars: Vec<char> = self.value.chars().collect();
        let mut start = self.cursor;
        while start > 0 && chars[start - 1].is_whitespace() {
            start -= 1;
        }
        while start > 0 && !chars[start - 1].is_whitespace() {
            start -= 1;
        }
        let from = byte_at(&self.value, start);
        let to = byte_at(&self.value, self.cursor);
        self.value.replace_range(from..to, "");
        self.cursor = start;
        true
    }
}

impl From<&str> for TextInput {
    fn from(value: &str) -> Self {
        Self::new(value)
    }
}
impl From<String> for TextInput {
    fn from(value: String) -> Self {
        Self::new(value)
    }
}
impl Deref for TextInput {
    type Target = str;
    fn deref(&self) -> &Self::Target {
        self.as_str()
    }
}
impl fmt::Display for TextInput {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.value)
    }
}

fn byte_at(text: &str, char_index: usize) -> usize {
    text.char_indices()
        .nth(char_index)
        .map_or(text.len(), |(byte, _)| byte)
}

fn sanitize(text: String) -> String {
    text.chars()
        .filter(|ch| !ch.is_control())
        .take(MAX_INPUT_CHARS)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    fn key(code: KeyCode, modifiers: KeyModifiers) -> KeyEvent {
        KeyEvent::new(code, modifiers)
    }

    #[test]
    fn cursor_editing_respects_cjk_character_boundaries() {
        let mut input = TextInput::from("香港A");
        input.handle_key(key(KeyCode::Left, KeyModifiers::NONE));
        input.handle_key(key(KeyCode::Char('中'), KeyModifiers::NONE));
        assert_eq!(input.as_str(), "香港中A");
        assert_eq!(input.cursor(), 3);
        input.handle_key(key(KeyCode::Backspace, KeyModifiers::NONE));
        assert_eq!(input.as_str(), "香港A");
        input.handle_key(key(KeyCode::Home, KeyModifiers::NONE));
        input.handle_key(key(KeyCode::Delete, KeyModifiers::NONE));
        assert_eq!(input.as_str(), "港A");
        input.handle_key(key(KeyCode::End, KeyModifiers::NONE));
        input.handle_key(key(KeyCode::Left, KeyModifiers::NONE));
        input.handle_key(key(KeyCode::Char('u'), KeyModifiers::CONTROL));
        assert_eq!(input.as_str(), "A");
        input.handle_key(key(KeyCode::Char('k'), KeyModifiers::CONTROL));
        assert_eq!(input.as_str(), "");
    }

    #[test]
    fn control_edit_keys_operate_on_cursor() {
        let mut input = TextInput::from("one two three");
        input.handle_key(key(KeyCode::Char('a'), KeyModifiers::CONTROL));
        assert_eq!(input.cursor(), 0);
        input.handle_key(key(KeyCode::Char('e'), KeyModifiers::CONTROL));
        input.handle_key(key(KeyCode::Char('w'), KeyModifiers::CONTROL));
        assert_eq!(input.as_str(), "one two ");
        input.handle_key(key(KeyCode::Char('u'), KeyModifiers::CONTROL));
        assert_eq!(input.as_str(), "");
    }

    #[test]
    fn ctrl_k_alt_backspace_and_ctrl_unknown() {
        let mut input = TextInput::from("alpha beta");
        input.handle_key(key(KeyCode::Home, KeyModifiers::NONE));
        input.handle_key(key(KeyCode::Char('x'), KeyModifiers::CONTROL));
        assert_eq!(input.as_str(), "alpha beta");
        input.handle_key(key(KeyCode::Char('k'), KeyModifiers::CONTROL));
        assert_eq!(input.as_str(), "");
        input.set("alpha beta");
        input.handle_key(key(KeyCode::Backspace, KeyModifiers::ALT));
        assert_eq!(input.as_str(), "alpha ");
    }

    #[test]
    fn render_scrolls_cjk_and_masked_text_to_real_cursor() {
        use ratatui::{backend::TestBackend, layout::Rect, Terminal};
        let input = TextInput::from("香港A");
        let backend = TestBackend::new(8, 3);
        let mut terminal = Terminal::new(backend).unwrap();
        terminal
            .draw(|frame| input.render(frame, Rect::new(2, 1, 3, 1), Style::default()))
            .unwrap();
        terminal.backend_mut().assert_cursor_position((3, 1));
        terminal
            .draw(|frame| input.render_masked(frame, Rect::new(2, 1, 3, 1), Style::default()))
            .unwrap();
        terminal.backend_mut().assert_cursor_position((4, 1));
        assert_eq!(terminal.backend().buffer()[(2, 1)].symbol(), "*");
    }

    #[test]
    fn input_clears_the_replaced_hint_before_drawing() {
        use ratatui::{backend::TestBackend, Terminal};
        let mut terminal = Terminal::new(TestBackend::new(12, 2)).unwrap();
        terminal
            .draw(|frame| {
                frame.render_widget(Line::raw("old hint text"), frame.area());
                TextInput::from("甲").render(frame, Rect::new(0, 0, 10, 1), Style::default());
            })
            .unwrap();
        for x in 2..10 {
            assert_eq!(terminal.backend().buffer()[(x, 0)].symbol(), " ");
        }
        terminal.backend_mut().assert_cursor_position((2, 0));
    }

    #[test]
    fn editing_keys_report_changes_and_keep_cjk_cursor_boundaries() {
        let mut input = TextInput::from("甲乙 丙丁");
        assert!(!input.handle_key(key(KeyCode::Home, KeyModifiers::NONE)));
        assert!(!input.handle_key(key(KeyCode::Right, KeyModifiers::NONE)));
        assert_eq!(input.cursor(), 1);
        assert!(input.handle_key(key(KeyCode::Delete, KeyModifiers::NONE)));
        assert_eq!(input.as_str(), "甲 丙丁");
        assert!(!input.handle_key(key(KeyCode::End, KeyModifiers::NONE)));
        assert!(!input.handle_key(key(KeyCode::Char('a'), KeyModifiers::CONTROL)));
        assert_eq!(input.cursor(), 0);
        assert!(!input.handle_key(key(KeyCode::Char('e'), KeyModifiers::CONTROL)));
        assert_eq!(input.cursor(), 4);
        input.handle_key(key(KeyCode::Left, KeyModifiers::NONE));
        assert!(input.handle_key(key(KeyCode::Char('k'), KeyModifiers::CONTROL)));
        assert_eq!(input.as_str(), "甲 丙");
        assert!(input.handle_key(key(KeyCode::Char('w'), KeyModifiers::CONTROL)));
        assert_eq!(input.as_str(), "甲 ");
        assert!(input.handle_key(key(KeyCode::Backspace, KeyModifiers::ALT)));
        assert!(input.is_empty());
        input.paste("中文 English");
        input.handle_key(key(KeyCode::Home, KeyModifiers::NONE));
        input.handle_key(key(KeyCode::Right, KeyModifiers::NONE));
        assert!(input.handle_key(key(KeyCode::Char('u'), KeyModifiers::CONTROL)));
        assert_eq!(input.as_str(), "文 English");
        assert!(!input.handle_key(key(KeyCode::Backspace, KeyModifiers::NONE)));
        input.handle_key(key(KeyCode::End, KeyModifiers::NONE));
        assert!(input.handle_key(key(KeyCode::Backspace, KeyModifiers::NONE)));
        assert_eq!(input.as_str(), "文 Englis");
        for modifiers in [KeyModifiers::CONTROL, KeyModifiers::ALT] {
            assert!(!input.handle_key(key(KeyCode::Char('z'), modifiers)));
        }
        assert_eq!(input.as_str(), "文 Englis");
    }

    #[test]
    fn paste_normalizes_lines_and_filters_controls_with_limit() {
        let mut input = TextInput::default();
        assert!(input.paste("第一行\r\n第二行\t\u{1b}!"));
        assert_eq!(input.as_str(), "第一行 第二行!");
        input.clear();
        assert!(input.paste(&"x".repeat(MAX_INPUT_CHARS + 10)));
        assert_eq!(input.len(), MAX_INPUT_CHARS);
    }
}
