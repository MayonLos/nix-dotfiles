//! Small, deterministic Bilibili XML-to-ASS renderer for mpv.
//!
//! Layout follows the conventional Danmaku2ASS/DanmakuFactory model: rolling
//! comments move right-to-left in collision-aware lanes, while fixed comments
//! occupy centered top/bottom lanes for a shorter interval.
use anyhow::{bail, Context, Result};
use quick_xml::{
    events::{BytesStart, Event},
    Reader,
};
use serde::{Deserialize, Serialize};
use unicode_width::UnicodeWidthStr;

const PLAY_RES_X: u32 = 1920;
const PLAY_RES_Y: u32 = 1080;
const MAX_XML_BYTES: usize = 10 * 1024 * 1024;
const MAX_ITEMS: usize = 20_000;
const SCROLL_SECONDS: f64 = 10.0;
const FIXED_SECONDS: f64 = 4.0;
const MAX_FONT_SIZE: u32 = 72;
const LANE_HEIGHT: u32 = MAX_FONT_SIZE + 8;
const TOP_REGION_HEIGHT: u32 = PLAY_RES_Y / 4;
const ROLLING_REGION_HEIGHT: u32 = PLAY_RES_Y / 2;
const BOTTOM_REGION_HEIGHT: u32 = PLAY_RES_Y / 4;
const FONT_NAME: &str = "Noto Sans CJK SC";

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(default)]
pub struct Options {
    /// ASS font size in script pixels. Clamped to 12..=72.
    pub font_size: u32,
    /// Maximum simultaneous lanes for each comment placement class.
    pub density: usize,
    /// Text opacity where 1.0 is opaque and 0.0 is transparent.
    pub opacity: f32,
    /// Case-insensitive substrings to suppress.
    pub blocked: Vec<String>,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            font_size: 36,
            density: 12,
            opacity: 0.85,
            blocked: Vec::new(),
        }
    }
}

#[derive(Clone, Debug)]
struct Item {
    time: f64,
    mode: u8,
    size: u32,
    color: u32,
    text: String,
}

#[derive(Clone, Copy, Debug)]
struct LaneEntry {
    start: f64,
    end: f64,
    width: f64,
    speed: f64,
}

/// Convert a Bilibili `danmaku.xml` document into ASS subtitle text.
pub fn convert(xml: &str, options: &Options) -> Result<String> {
    if xml.len() > MAX_XML_BYTES {
        bail!("弹幕 XML 超过 10 MiB 限制");
    }
    let mut items = parse_items(xml)?;
    items.sort_by(|a, b| a.time.total_cmp(&b.time));

    let font = options.font_size.clamp(12, MAX_FONT_SIZE);
    let density = options.density.clamp(1, 30);
    let lane_height = f64::from(LANE_HEIGHT);
    let rolling_lanes = density.min((ROLLING_REGION_HEIGHT / LANE_HEIGHT) as usize);
    let top_lanes = density.min((TOP_REGION_HEIGHT / LANE_HEIGHT) as usize);
    let bottom_lanes = density.min((BOTTOM_REGION_HEIGHT / LANE_HEIGHT) as usize);
    let opacity = if options.opacity.is_finite() {
        options.opacity.clamp(0.0, 1.0)
    } else {
        0.85
    };
    let alpha = ((1.0 - opacity) * 255.0).round() as u8;
    let blocked: Vec<String> = options
        .blocked
        .iter()
        .filter(|word| !word.is_empty())
        .map(|word| word.to_lowercase())
        .collect();

    let mut out = ass_header(font, alpha);
    // Reserve separate vertical bands: top/bottom fixed comments each get
    // one quarter, and rolling comments use the middle half of the frame.
    let mut rolling: Vec<Option<LaneEntry>> = vec![None; rolling_lanes];
    let mut top = vec![None; top_lanes];
    let mut bottom = vec![None; bottom_lanes];
    let mut emitted = 0usize;

    for item in items {
        if blocked
            .iter()
            .any(|word| item.text.to_lowercase().contains(word))
        {
            continue;
        }
        let text = ass_text(&item.text);
        if text.is_empty() {
            continue;
        }
        let color = ass_color(item.color);
        let item_font =
            ((u64::from(item.size) * u64::from(font) / 36) as u32).clamp(12, MAX_FONT_SIZE);
        let width = estimated_width(&text, item_font);

        match item.mode {
            1..=3 => {
                let duration = SCROLL_SECONDS;
                let speed = (f64::from(PLAY_RES_X) + width) / duration;
                let lane = rolling.iter_mut().position(|slot| {
                    let Some(last) = slot.as_ref() else {
                        return true;
                    };
                    if item.time >= last.end {
                        return true;
                    }
                    let elapsed = (item.time - last.start).max(0.0);
                    let old_right = f64::from(PLAY_RES_X) + last.width - last.speed * elapsed;
                    if old_right > f64::from(PLAY_RES_X) {
                        return false;
                    }
                    let gap = f64::from(PLAY_RES_X) - old_right;
                    let remaining = old_right.max(0.0) / last.speed;
                    // If the new comment is faster, the initial gap must last
                    // until the old comment's trailing edge leaves the frame.
                    gap >= (speed - last.speed).max(0.0) * remaining
                });
                let Some(lane) = lane else { continue };
                rolling[lane] = Some(LaneEntry {
                    start: item.time,
                    end: item.time + duration,
                    width,
                    speed,
                });
                let y = f64::from(TOP_REGION_HEIGHT) + lane_height * lane as f64;
                let x_start = -width;
                push_dialogue(
                    &mut out,
                    item.time,
                    duration,
                    &color,
                    item_font,
                    &format!("{{\\an7\\move({PLAY_RES_X},{y:.0},{x_start:.0},{y:.0})}}{text}"),
                );
            }
            4 | 5 => {
                let pool = if item.mode == 5 {
                    &mut top
                } else {
                    &mut bottom
                };
                let Some(lane) = pool.iter_mut().position(|slot| {
                    slot.as_ref()
                        .is_none_or(|last: &LaneEntry| item.time >= last.end)
                }) else {
                    continue;
                };
                let duration = FIXED_SECONDS;
                pool[lane] = Some(LaneEntry {
                    start: item.time,
                    end: item.time + duration,
                    width,
                    speed: 0.0,
                });
                let y = if item.mode == 5 {
                    lane_height * lane as f64 + 6.0
                } else {
                    f64::from(PLAY_RES_Y) - lane_height * (lane + 1) as f64
                };
                push_dialogue(
                    &mut out,
                    item.time,
                    duration,
                    &color,
                    item_font,
                    &format!("{{\\an8\\pos(960,{y:.0})}}{text}"),
                );
            }
            _ => continue,
        }
        emitted += 1;
        if emitted >= MAX_ITEMS {
            break;
        }
    }
    Ok(out)
}

fn parse_items(xml: &str) -> Result<Vec<Item>> {
    let mut reader = Reader::from_str(xml);
    reader.config_mut().trim_text(false);
    let mut items = Vec::new();
    let mut current: Option<(f64, u8, u32, u32)> = None;
    let mut text = String::new();
    loop {
        match reader.read_event().context("读取弹幕 XML")? {
            Event::Start(event) if event.name().as_ref() == b"d" => {
                if current.is_some() {
                    bail!("弹幕 XML 中出现嵌套 d 元素");
                }
                current = Some(parse_attrs(&event)?);
                text.clear();
            }
            Event::Empty(event) if event.name().as_ref() == b"d" => {
                if items.len() >= MAX_ITEMS {
                    bail!("弹幕条目超过 {MAX_ITEMS} 条限制");
                }
                let (time, mode, size, color) = parse_attrs(&event)?;
                items.push(Item {
                    time,
                    mode,
                    size,
                    color,
                    text: String::new(),
                });
            }
            Event::Text(event) if current.is_some() => {
                let decoded = event.decode().context("解码弹幕文字")?;
                let unescaped = quick_xml::escape::unescape(&decoded).context("解析弹幕实体")?;
                text.push_str(&unescaped);
            }
            Event::GeneralRef(event) if current.is_some() => {
                let name = event.decode().context("解码 XML 实体")?;
                let decoded = match name.as_ref() {
                    "amp" => '&',
                    "lt" => '<',
                    "gt" => '>',
                    "apos" => '\'',
                    "quot" => '"',
                    _ => event
                        .resolve_char_ref()
                        .context("解析 XML 字符引用")?
                        .context("不支持的 XML 实体")?,
                };
                text.push(decoded);
            }
            Event::CData(event) if current.is_some() => {
                text.push_str(&event.decode().context("解码弹幕 CDATA")?);
            }
            Event::End(event) if event.name().as_ref() == b"d" => {
                let Some((time, mode, size, color)) = current.take() else {
                    bail!("弹幕 XML 出现未配对的 d 结束标签");
                };
                if items.len() >= MAX_ITEMS {
                    bail!("弹幕条目超过 {MAX_ITEMS} 条限制");
                }
                items.push(Item {
                    time,
                    mode,
                    size,
                    color,
                    text: std::mem::take(&mut text),
                });
            }
            Event::Eof => break,
            _ => {}
        }
    }
    if current.is_some() {
        bail!("弹幕 XML 中 d 元素未闭合");
    }
    if items.len() > MAX_ITEMS {
        bail!("弹幕条目超过 {MAX_ITEMS} 条限制");
    }
    Ok(items)
}

fn parse_attrs(event: &BytesStart<'_>) -> Result<(f64, u8, u32, u32)> {
    let mut p = None;
    for attr in event.attributes().with_checks(true) {
        let attr = attr.context("解析弹幕属性")?;
        if attr.key.as_ref() == b"p" {
            p = Some(attr.unescape_value().context("解码弹幕属性")?.into_owned());
        }
    }
    let raw = p.context("弹幕 d 元素缺少 p 属性")?;
    let mut fields = raw.split(',');
    let time = fields.next().context("弹幕 p 缺少时间")?.parse::<f64>()?;
    let mode = fields.next().context("弹幕 p 缺少模式")?.parse::<u8>()?;
    let size = fields.next().context("弹幕 p 缺少字号")?.parse::<u32>()?;
    let color = fields.next().context("弹幕 p 缺少颜色")?.parse::<u32>()?;
    if !time.is_finite() || !(0.0..=31_536_000.0).contains(&time) {
        bail!("弹幕时间无效");
    }
    Ok((time, mode, size, color))
}

fn ass_text(input: &str) -> String {
    input
        .chars()
        .filter(|ch| !ch.is_control() || *ch == '\n' || *ch == '\t')
        .map(|ch| match ch {
            '{' | '}' => ' ', // Never allow user text to inject ASS override tags.
            '\\' => '／',     // ASS uses backslash for override commands.
            '\n' | '\r' | '\t' => ' ',
            ch => ch,
        })
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

fn estimated_width(text: &str, font_size: u32) -> f64 {
    let cells = text.width().max(1) as f64;
    (cells * f64::from(font_size) * 0.52 + 12.0).min(f64::from(PLAY_RES_X) * 3.0)
}

fn ass_color(rgb: u32) -> String {
    let r = (rgb >> 16) & 0xff;
    let g = (rgb >> 8) & 0xff;
    let b = rgb & 0xff;
    format!("&H00{b:02X}{g:02X}{r:02X}&")
}

fn ass_header(font_size: u32, alpha: u8) -> String {
    format!(
        "[Script Info]\nScriptType: v4.00+\nPlayResX: {PLAY_RES_X}\nPlayResY: {PLAY_RES_Y}\nWrapStyle: 2\nScaledBorderAndShadow: yes\n\n[V4+ Styles]\nFormat: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\nStyle: Default,{FONT_NAME},{font_size},&H{alpha:02X}FFFFFF,&H{alpha:02X}FFFFFF,&H80000000,&H80000000,0,0,0,0,100,100,0,0,1,1.5,0,7,24,24,24,1\n\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"
    )
}

fn push_dialogue(out: &mut String, start: f64, duration: f64, color: &str, size: u32, text: &str) {
    let end = ass_time(start + duration);
    let start = ass_time(start);
    out.push_str(&format!(
        "Dialogue: 0,{start},{end},Default,,0,0,0,,{{\\fs{size}\\c{color}}}{text}\n"
    ));
}

fn ass_time(seconds: f64) -> String {
    let centis = (seconds.max(0.0) * 100.0).round() as u64;
    let hours = centis / 360_000;
    let minutes = (centis / 6_000) % 60;
    let secs = (centis / 100) % 60;
    let fraction = centis % 100;
    format!("{hours}:{minutes:02}:{secs:02}.{fraction:02}")
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIXTURE: &str = include_str!("../fixtures/danmaku.xml");

    #[test]
    fn fixture_renders_each_supported_placement_and_decodes_entities() {
        let ass = convert(FIXTURE, &Options::default()).unwrap();
        assert!(ass.contains("PlayResX: 1920"));
        assert!(ass.contains("{\\an7\\move(1920,270,-"));
        assert!(ass.contains("\\an8\\pos("));
        assert!(ass.contains("hello & world"));
        assert!(ass.contains("{\\fs25\\c&H000000FF&}"));
        assert_eq!(
            ass.lines()
                .filter(|line| line.starts_with("Dialogue:"))
                .count(),
            4
        );
    }

    #[test]
    fn user_text_cannot_inject_override_commands() {
        let xml =
            r#"<i><d p="1,1,25,16777215,0,0,0,0">{\\alpha&amp;H00&amp;} safe&#10;line</d></i>"#;
        let ass = convert(xml, &Options::default()).unwrap();
        assert!(!ass.contains("{\\alpha"));
        assert!(ass.contains("／／alpha&H00& safe line"));
        assert!(ass.contains("safe line"));
    }

    #[test]
    fn blocked_words_and_collision_lanes_drop_events() {
        let blocked = convert(
            FIXTURE,
            &Options {
                blocked: vec!["spam".into()],
                ..Options::default()
            },
        )
        .unwrap();
        assert!(!blocked.contains("spam"));
        let dense = r#"<i><d p="0,1,25,16777215">first</d><d p="0,1,25,16777215">second</d></i>"#;
        let rendered = convert(
            dense,
            &Options {
                density: 1,
                ..Options::default()
            },
        )
        .unwrap();
        assert_eq!(
            rendered
                .lines()
                .filter(|line| line.starts_with("Dialogue:"))
                .count(),
            1
        );
    }

    #[test]
    fn malformed_danmaku_is_reported() {
        assert!(convert(r#"<i><d>no p attribute</d></i>"#, &Options::default()).is_err());
        assert!(convert(
            r#"<i><d p="nan,1,25,16777215">bad time</d></i>"#,
            &Options::default()
        )
        .is_err());
        assert!(convert("<i><d", &Options::default()).is_err());
    }
}
