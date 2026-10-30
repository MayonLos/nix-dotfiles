use ratatui::style::Color;
use unicode_segmentation::UnicodeSegmentation;
use unicode_width::UnicodeWidthStr;
include!(concat!(env!("OUT_DIR"), "/palette.rs"));

pub fn delay_color(delay: Option<u64>) -> Color {
    match delay {
        Some(1..=249) => GREEN,
        Some(250..=399) => BLUE,
        Some(400..=9999) => YELLOW,
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
    for ch in text.graphemes(true) {
        let cells = ch.width();
        if used + cells > width - 1 {
            break;
        }
        out.push_str(ch);
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
        assert_eq!(delay_color(Some(249)), GREEN);
        assert_eq!(delay_color(Some(250)), BLUE);
        assert_eq!(delay_color(Some(399)), BLUE);
        assert_eq!(delay_color(Some(400)), YELLOW);
        assert_eq!(delay_color(Some(9999)), YELLOW);
        assert_eq!(delay_color(Some(10000)), RED);
        assert_eq!(delay_color(None), RED);
        assert_eq!(delay_color(Some(0)), RED);
    }
    #[test]
    fn emoji_clusters_are_never_split() {
        for text in ["🇭🇰 香港", "👩‍💻工程师", "e\u{301}xyz", "🏳️‍🌈节点"]
        {
            for width in 0..12 {
                let clipped = clip(text, width);
                assert!(clipped.width() <= width);
                if let Some(prefix) = clipped.strip_suffix('…') {
                    assert!(text.grapheme_indices(true).any(|(i, _)| i == prefix.len()));
                }
            }
        }
    }
    #[test]
    fn chinese_clipping() {
        assert_eq!(clip("香港 Tokyo", 6), "香港 …");
        assert_eq!(clip("上海", 1), "…");
        assert_eq!(clip("上海", 0), "");
        assert_eq!(clip("上海", 4), "上海");
    }
}
