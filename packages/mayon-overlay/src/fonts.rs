//! Font loading and glyph rasterisation.
//!
//! The overlay draws its own text: there is no GTK, Pango or Wayland text
//! protocol involved. Two fonts are loaded:
//!
//! * the UI font (`Inter` from the palette) for Latin text;
//! * a CJK fallback (`Noto Sans CJK SC`, or `Maple Mono NF CN` as a second
//!   choice) for codepoints the UI font does not cover, so Chinese clipboard
//!   text is not rendered as tofu.
//!
//! Paths can be forced with `--font`/`--font-fallback` (used by the headless
//! test, which knows exact store paths); otherwise fontconfig's `fc-match`
//! resolves the palette family names, which keeps the overlay consistent with
//! the rest of the desktop.

use fontdue::{Font, FontSettings};
use std::collections::HashMap;
use std::path::Path;
use std::process::Command;

const CACHE_LIMIT: usize = 4096;

pub struct Glyph {
    pub metrics: fontdue::Metrics,
    pub coverage: Vec<u8>,
    /// Which loaded font produced the glyph (0 = UI font, 1 = fallback).
    pub font: u8,
}

pub struct Fonts {
    primary: Font,
    fallback: Option<Font>,
    cache: HashMap<(u8, u32, u32), Glyph>,
    pub primary_path: String,
    pub fallback_path: Option<String>,
}

impl Fonts {
    /// Load the primary and fallback faces. `--font` wins over fontconfig.
    pub fn load(
        primary_override: Option<&str>,
        fallback_override: Option<&str>,
    ) -> Result<Fonts, String> {
        let (primary_path, primary_data) =
            resolve_font("Inter", primary_override).ok_or_else(|| {
                "cannot find UI font Inter (pass --font or install the palette font)".to_string()
            })?;
        let primary = Font::from_bytes(primary_data, FontSettings::default())
            .map_err(|err| format!("cannot parse font {}: {}", primary_path, err))?;

        // Fallbacks are best effort: without a CJK face the overlay still works
        // for Latin text, it just draws tofu for CJK graphemes.
        let mut fallback = None;
        let mut fallback_path = None;
        for name in ["Noto Sans CJK SC", "Maple Mono NF CN", "Noto Sans CJK JP"] {
            if let Some((path, data)) = resolve_font(name, fallback_override) {
                if let Ok(font) = Font::from_bytes(data, FontSettings::default()) {
                    fallback = Some(font);
                    fallback_path = Some(path);
                    break;
                }
            }
        }

        Ok(Fonts {
            primary,
            fallback,
            cache: HashMap::new(),
            primary_path,
            fallback_path,
        })
    }

    /// Rasterise one character, preferring the UI font and falling back per
    /// codepoint. Returns the glyph plus the advance width in logical pixels.
    pub fn glyph(&mut self, ch: char, px: f32) -> (Glyph, f32) {
        let px_key = (px * 64.0).round().max(1.0) as u32;
        // The UI font is used unless it has no glyph for the codepoint, except
        // for CJK where Inter's blank would win over a real fallback glyph.
        let mut font_id = 0u8;
        let mut font = &self.primary;
        if self.primary.lookup_glyph_index(ch) == 0 {
            if let Some(fallback) = &self.fallback {
                font_id = 1;
                font = fallback;
            }
        }

        if let Some(glyph) = self.cache.get(&(font_id, px_key, ch as u32)) {
            let advance = glyph.metrics.advance_width;
            return (
                Glyph {
                    metrics: glyph.metrics,
                    coverage: glyph.coverage.clone(),
                    font: font_id,
                },
                advance,
            );
        }

        let index = font.lookup_glyph_index(ch);
        let (metrics, coverage) = font.rasterize_indexed(index, px);
        if self.cache.len() >= CACHE_LIMIT {
            self.cache.clear();
        }
        self.cache.insert(
            (font_id, px_key, ch as u32),
            Glyph {
                metrics: metrics.clone(),
                coverage: coverage.clone(),
                font: font_id,
            },
        );
        let advance = metrics.advance_width;
        (
            Glyph {
                metrics,
                coverage,
                font: font_id,
            },
            advance,
        )
    }

    pub fn text_width(&mut self, text: &str, px: f32) -> f32 {
        let mut width = 0.0;
        for ch in text.chars() {
            let (glyph, _) = self.glyph(ch, px);
            width += glyph.metrics.advance_width;
        }
        width
    }

    /// Width including the single kerning-free advance; used to truncate text.
    pub fn truncate_with_ellipsis(&mut self, text: &str, px: f32, max_width: f32) -> String {
        if max_width <= 0.0 {
            return String::new();
        }
        if self.text_width(text, px) <= max_width {
            return text.to_string();
        }
        let ellipsis = "…";
        let ellipsis_width = self.text_width(ellipsis, px);
        let budget = (max_width - ellipsis_width).max(0.0);
        let mut out = String::new();
        let mut width = 0.0;
        for ch in text.chars() {
            let (glyph, _) = self.glyph(ch, px);
            if width + glyph.metrics.advance_width > budget {
                break;
            }
            width += glyph.metrics.advance_width;
            out.push(ch);
        }
        out.push_str(ellipsis);
        out
    }
}

fn resolve_font(family: &str, override_path: Option<&str>) -> Option<(String, Vec<u8>)> {
    let path = match override_path {
        Some(path) if !path.is_empty() => path.to_string(),
        _ => match_font(family)?,
    };
    if !Path::new(&path).is_file() {
        return None;
    }
    let data = std::fs::read(&path).ok()?;
    Some((path, data))
}

fn match_font(family: &str) -> Option<String> {
    let output = Command::new("fc-match")
        .args(["-f", "%{file}", family])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if path.is_empty() {
        None
    } else {
        Some(path)
    }
}
