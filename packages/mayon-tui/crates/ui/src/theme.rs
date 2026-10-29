use ratatui::style::Color;
use unicode_width::{UnicodeWidthChar, UnicodeWidthStr};
include!(concat!(env!("OUT_DIR"), "/palette.rs"));

pub fn delay_color(delay: Option<u64>) -> Color {
    match delay {
        Some(1..=149) => GREEN,
        Some(150..=399) => YELLOW,
        _ => RED,
    }
}

/// Clip by terminal cells, never by UTF-8 bytes (Chinese names occupy two).
pub fn clip(text: &str, width: usize) -> String {
    if text.width() <= width {
        return text.into();
    }
    if width == 0 {
        return String::new();
    }
    let mut used = 0;
    let mut out = String::new();
    for ch in text.chars() {
        let cells = ch.width().unwrap_or(0);
        if used + cells > width - 1 {
            break;
        }
        out.push(ch);
        used += cells;
    }
    out.push('…');
    out
}

pub fn bytes(value: u64) -> String {
    let mut size = value as f64;
    let mut unit = "B";
    for next in ["KiB", "MiB", "GiB", "TiB"] {
        if size < 1024.0 {
            break;
        }
        size /= 1024.0;
        unit = next;
    }
    format!("{size:.1} {unit}")
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn latency_boundaries() {
        assert_eq!(delay_color(Some(149)), GREEN);
        assert_eq!(delay_color(Some(150)), YELLOW);
        assert_eq!(delay_color(Some(399)), YELLOW);
        assert_eq!(delay_color(Some(400)), RED);
        assert_eq!(delay_color(None), RED);
        assert_eq!(delay_color(Some(0)), RED);
    }
    #[test]
    fn chinese_clipping() {
        assert_eq!(clip("香港 Tokyo", 6), "香港 …");
        assert_eq!(clip("上海", 1), "…");
        assert_eq!(clip("上海", 0), "");
        assert_eq!(clip("上海", 4), "上海");
    }
}
