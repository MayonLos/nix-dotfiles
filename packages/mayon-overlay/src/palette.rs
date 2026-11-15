//! Colours for the overlay. Byte values are generated from the repository's
//! One Dark palette (`aspects/appearance/appearance/onedark.nix`) by build.rs.
//! The module intentionally exposes every palette entry, not only the ones the
//! current layout happens to use.
#![allow(dead_code)]

include!(concat!(env!("OUT_DIR"), "/palette.rs"));

/// Simple straight-alpha colour used by the rasteriser.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Rgba {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
}

impl Rgba {
    pub const fn rgb(c: (u8, u8, u8)) -> Rgba {
        Rgba {
            r: c.0,
            g: c.1,
            b: c.2,
            a: 255,
        }
    }

    pub const fn with_alpha(self, a: u8) -> Rgba {
        Rgba { a, ..self }
    }

    pub const fn hex(self) -> u32 {
        ((self.r as u32) << 16) | ((self.g as u32) << 8) | self.b as u32
    }
}

pub fn bg() -> Rgba {
    Rgba::rgb(BG)
}
pub fn surface() -> Rgba {
    Rgba::rgb(SURFACE)
}
pub fn selection() -> Rgba {
    Rgba::rgb(SELECTION)
}
pub fn border() -> Rgba {
    Rgba::rgb(BORDER)
}
pub fn deep() -> Rgba {
    Rgba::rgb(DEEP)
}
pub fn fg() -> Rgba {
    Rgba::rgb(FG)
}
pub fn muted() -> Rgba {
    Rgba::rgb(MUTED)
}
pub fn blue() -> Rgba {
    Rgba::rgb(BLUE)
}
pub fn green() -> Rgba {
    Rgba::rgb(GREEN)
}
pub fn orange() -> Rgba {
    Rgba::rgb(ORANGE)
}
pub fn red() -> Rgba {
    Rgba::rgb(RED)
}
pub fn bright_fg() -> Rgba {
    Rgba::rgb(BRIGHT_FG)
}

/// Full-screen backdrop: the palette background at slightly reduced opacity so
/// the focused application remains perceptible behind the overlay.
pub fn backdrop() -> Rgba {
    Rgba::rgb(BG).with_alpha(236)
}
