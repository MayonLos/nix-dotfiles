use encoding_rs::GBK;
use ratatui::{
    style::{Color, Modifier, Style},
    text::{Line, Span},
};
use serde::{Deserialize, Serialize};

/// Text encoding used for complete received lines and outgoing commands.
#[derive(Clone, Copy, Debug, Default, Deserialize, PartialEq, Serialize)]
pub enum Encoding {
    #[default]
    Utf8,
    Gbk,
}

impl Encoding {
    pub fn decode(self, bytes: &[u8]) -> String {
        match self {
            Self::Utf8 => String::from_utf8_lossy(bytes).into_owned(),
            Self::Gbk => GBK.decode(bytes).0.into_owned(),
        }
    }

    pub fn encode(self, text: &str) -> Result<Vec<u8>, String> {
        match self {
            Self::Utf8 => Ok(text.as_bytes().to_vec()),
            Self::Gbk => {
                let (encoded, _, had_errors) = GBK.encode(text);
                if had_errors {
                    Err("文本包含 GBK 无法表示的字符".into())
                } else {
                    Ok(encoded.into_owned())
                }
            }
        }
    }
}

/// Parse hexadecimal bytes. Whitespace and commas separate groups; `0x` is
/// accepted at the start of each group, while adjacent hex digits form bytes.
pub fn parse_hex(input: &str) -> Result<Vec<u8>, String> {
    let mut bytes = Vec::new();
    let mut high = None;
    let mut at_group_start = true;
    let mut chars = input.chars().peekable();

    while let Some(ch) = chars.next() {
        if ch.is_whitespace() || ch == ',' {
            if high.is_some() {
                return Err("HEX 字节必须由偶数个十六进制数字组成".into());
            }
            at_group_start = true;
            continue;
        }
        if at_group_start && ch == '0' && matches!(chars.peek(), Some('x' | 'X')) {
            chars.next();
            at_group_start = false;
            continue;
        }
        let value = ch
            .to_digit(16)
            .ok_or_else(|| format!("非法 HEX 字符：{ch}"))? as u8;
        at_group_start = false;
        if let Some(upper) = high.take() {
            bytes.push((upper << 4) | value);
        } else {
            high = Some(value);
        }
    }

    if high.is_some() {
        return Err("HEX 字节必须由偶数个十六进制数字组成".into());
    }
    if bytes.is_empty() {
        return Err("HEX 数据不能为空".into());
    }
    Ok(bytes)
}

/// Parse `name=value` telemetry or a row of comma-separated numeric values.
/// Any malformed field rejects the whole row; at most 16 channels are kept.
pub fn parse_values(input: &str) -> Vec<(String, f64)> {
    let fields: Vec<_> = input.trim().split(',').map(str::trim).collect();
    if fields.is_empty() || fields.len() > 16 || fields.iter().any(|field| field.is_empty()) {
        return Vec::new();
    }

    let named = fields.iter().any(|field| field.contains('='));
    let mut parsed = Vec::with_capacity(fields.len());
    for (index, field) in fields.into_iter().enumerate() {
        let (name, value) = if named {
            let Some((name, value)) = field.split_once('=') else {
                return Vec::new();
            };
            let name = name.trim();
            if name.is_empty() || name.chars().any(char::is_control) {
                return Vec::new();
            }
            (name.to_string(), value.trim())
        } else {
            (format!("ch{}", index + 1), field)
        };
        let Ok(value) = value.parse::<f64>() else {
            return Vec::new();
        };
        if !value.is_finite() {
            return Vec::new();
        }
        parsed.push((name, value));
    }
    parsed
}

/// Splits a byte stream on LF, CRLF, or CR while tolerating chunk boundaries.
/// A line is capped at 16 KiB; excess bytes are discarded until its delimiter.
#[derive(Default, Debug)]
pub struct Framer {
    line: Vec<u8>,
    after_cr: bool,
    truncated: bool,
}

impl Framer {
    const MAX_LINE: usize = 16 * 1024;

    pub fn push(&mut self, bytes: &[u8]) -> Vec<Vec<u8>> {
        let mut lines = Vec::new();
        for &byte in bytes {
            if self.after_cr {
                self.after_cr = false;
                if byte == b'\n' {
                    continue;
                }
            }
            match byte {
                b'\r' => {
                    lines.push(std::mem::take(&mut self.line));
                    self.truncated = false;
                    self.after_cr = true;
                }
                b'\n' => {
                    lines.push(std::mem::take(&mut self.line));
                    self.truncated = false;
                }
                _ if self.line.len() < Self::MAX_LINE => self.line.push(byte),
                _ => self.truncated = true,
            }
        }
        lines
    }

    pub fn flush(&mut self) -> Option<Vec<u8>> {
        self.after_cr = false;
        if self.line.is_empty() {
            None
        } else {
            self.truncated = false;
            Some(std::mem::take(&mut self.line))
        }
    }

    /// Bytes buffered for the current, not yet terminated line.
    pub fn pending(&self) -> &[u8] {
        &self.line
    }

    /// Whether bytes beyond the 16 KiB current-line display cap were dropped.
    pub fn truncated(&self) -> bool {
        self.truncated
    }
}

/// Strip ANSI/control sequences for matching and parsing.
pub fn plain(text: &str) -> String {
    parse_ansi(text).into_iter().map(|(text, _)| text).collect()
}

/// Render a single safe terminal line. Only SGR color and emphasis survive;
/// OSC, cursor movement, and other controls are discarded before rendering.
pub fn ansi_line(text: &str) -> Line<'static> {
    let spans = parse_ansi(text)
        .into_iter()
        .filter(|(text, _)| !text.is_empty())
        .map(|(text, style)| Span::styled(text, style))
        .collect::<Vec<_>>();
    Line::from(spans)
}

fn parse_ansi(input: &str) -> Vec<(String, Style)> {
    let mut out = Vec::<(String, Style)>::new();
    let mut current = String::new();
    let mut style = Style::default();
    let mut chars = input.chars().peekable();

    let flush = |out: &mut Vec<(String, Style)>, current: &mut String, style: Style| {
        if !current.is_empty() {
            out.push((std::mem::take(current), style));
        }
    };

    while let Some(ch) = chars.next() {
        if ch == '\x1b' {
            flush(&mut out, &mut current, style);
            match chars.next() {
                Some('[') => {
                    let mut sequence = String::new();
                    let mut final_byte = None;
                    for next in chars.by_ref() {
                        if ('\x40'..='\x7e').contains(&next) {
                            final_byte = Some(next);
                            break;
                        }
                        if ('\x20'..='\x3f').contains(&next) {
                            sequence.push(next);
                        } else {
                            break;
                        }
                    }
                    if final_byte == Some('m') {
                        style = apply_sgr(style, &sequence);
                    }
                }
                Some(']') => {
                    // OSC ends at BEL or ST (ESC backslash).
                    while let Some(next) = chars.next() {
                        if next == '\x07' {
                            break;
                        }
                        if next == '\x1b' && chars.peek() == Some(&'\\') {
                            chars.next();
                            break;
                        }
                    }
                }
                Some(_) => {}
                None => {}
            }
        } else if !ch.is_control() {
            current.push(ch);
        }
    }
    flush(&mut out, &mut current, style);
    out
}

fn apply_sgr(mut style: Style, sequence: &str) -> Style {
    let params: Vec<u16> = if sequence.is_empty() {
        vec![0]
    } else {
        sequence
            .split(';')
            .map(|part| part.parse::<u16>().unwrap_or(0))
            .collect()
    };
    let mut index = 0;
    while index < params.len() {
        match params[index] {
            0 => style = Style::default(),
            1 => style = style.add_modifier(Modifier::BOLD),
            2 => style = style.add_modifier(Modifier::DIM),
            3 => style = style.add_modifier(Modifier::ITALIC),
            4 => style = style.add_modifier(Modifier::UNDERLINED),
            7 => style = style.add_modifier(Modifier::REVERSED),
            22 => style = style.remove_modifier(Modifier::BOLD | Modifier::DIM),
            23 => style = style.remove_modifier(Modifier::ITALIC),
            24 => style = style.remove_modifier(Modifier::UNDERLINED),
            27 => style = style.remove_modifier(Modifier::REVERSED),
            30..=37 => style = style.fg(ansi_color((params[index] - 30) as u8, false)),
            39 => style = style.fg(Color::Reset),
            40..=47 => style = style.bg(ansi_color((params[index] - 40) as u8, false)),
            49 => style = style.bg(Color::Reset),
            90..=97 => style = style.fg(ansi_color((params[index] - 90) as u8, true)),
            100..=107 => style = style.bg(ansi_color((params[index] - 100) as u8, true)),
            38 | 48 if index + 1 < params.len() => {
                let foreground = params[index] == 38;
                let color = match params[index + 1] {
                    5 if index + 2 < params.len() => {
                        index += 2;
                        Some(Color::Indexed(params[index] as u8))
                    }
                    2 if index + 4 < params.len() => {
                        let rgb = [
                            params[index + 2] as u8,
                            params[index + 3] as u8,
                            params[index + 4] as u8,
                        ];
                        index += 4;
                        Some(Color::Rgb(rgb[0], rgb[1], rgb[2]))
                    }
                    _ => None,
                };
                if let Some(color) = color {
                    style = if foreground {
                        style.fg(color)
                    } else {
                        style.bg(color)
                    };
                }
            }
            _ => {}
        }
        index += 1;
    }
    style
}

fn ansi_color(index: u8, bright: bool) -> Color {
    match (bright, index) {
        (false, 0) => Color::Black,
        (false, 1) => Color::Red,
        (false, 2) => Color::Green,
        (false, 3) => Color::Yellow,
        (false, 4) => Color::Blue,
        (false, 5) => Color::Magenta,
        (false, 6) => Color::Cyan,
        (false, _) => Color::Gray,
        (true, 0) => Color::DarkGray,
        (true, 1) => Color::LightRed,
        (true, 2) => Color::LightGreen,
        (true, 3) => Color::LightYellow,
        (true, 4) => Color::LightBlue,
        (true, 5) => Color::LightMagenta,
        (true, 6) => Color::LightCyan,
        (true, _) => Color::White,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn utf8_and_gbk_round_trip() {
        let chinese = "串口测试";
        for encoding in [Encoding::Utf8, Encoding::Gbk] {
            let encoded = encoding.encode(chinese).unwrap();
            assert_eq!(encoding.decode(&encoded), chinese);
        }
        assert!(Encoding::Gbk.encode("🦀").is_err());
    }

    #[test]
    fn hex_accepts_groups_and_contiguous_bytes() {
        assert_eq!(parse_hex("0x41 42, 0X43").unwrap(), b"ABC");
        assert_eq!(parse_hex("414243").unwrap(), b"ABC");
        assert!(parse_hex("abc").is_err());
        assert!(parse_hex("0xGG").is_err());
    }

    #[test]
    fn telemetry_requires_a_complete_finite_row() {
        assert_eq!(
            parse_values("a=1.2,b=3"),
            vec![("a".into(), 1.2), ("b".into(), 3.0)]
        );
        assert_eq!(
            parse_values("1.5,-2"),
            vec![("ch1".into(), 1.5), ("ch2".into(), -2.0)]
        );
        assert!(parse_values("a=1,nan").is_empty());
        assert!(parse_values("1,2,nope").is_empty());
        assert!(parse_values("1,2,3").len() == 3);
    }

    #[test]
    fn framing_handles_partial_crlf_and_caps_unterminated_lines() {
        let mut framer = Framer::default();
        assert!(framer.push("中文".as_bytes()).is_empty());
        assert_eq!(framer.push(b"\r"), vec!["中文".as_bytes().to_vec()]);
        assert!(framer.push(b"\nnext\n").contains(&b"next".to_vec()));
        assert_eq!(framer.flush(), None);
        assert_eq!(framer.push(b"tail\r"), vec![b"tail".to_vec()]);
        assert!(framer.push(&vec![b'x'; Framer::MAX_LINE + 100]).is_empty());
        assert_eq!(framer.line.len(), Framer::MAX_LINE);
    }

    #[test]
    fn ansi_keeps_sgr_and_drops_terminal_injection() {
        assert_eq!(plain("\x1b[31mERROR\x1b[0m\x1b]0;evil\x07\x1b[2J"), "ERROR");
        let line = ansi_line("\x1b[38;2;1;2;3mvalue\x1b[0m");
        assert_eq!(line.spans.len(), 1);
        assert_eq!(line.spans[0].style.fg, Some(Color::Rgb(1, 2, 3)));
    }
}
