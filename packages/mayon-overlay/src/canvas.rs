//! CPU rasteriser: rounded surfaces, text and image thumbnails on a tiny-skia
//! pixmap. Every public coordinate/size is in logical (surface local) pixels;
//! `scale` converts to buffer pixels so the overlay is crisp on HiDPI outputs.

use crate::fonts::Fonts;
use crate::palette::Rgba;
use image::RgbaImage;
use tiny_skia::{Color, FillRule, Paint, PathBuilder, Pixmap, Rect, Transform};

pub struct Canvas {
    pub width: u32,
    pub height: u32,
    pub scale: f32,
    pixmap: Pixmap,
    pub fonts: Fonts,
}

impl Canvas {
    pub fn new(width: u32, height: u32, scale: f32, fonts: Fonts) -> Canvas {
        let mut pixmap = Pixmap::new(width, height).expect("pixmap allocation");
        pixmap.fill(Color::TRANSPARENT);
        Canvas {
            width,
            height,
            scale,
            pixmap,
            fonts,
        }
    }

    fn sx(&self, value: f32) -> f32 {
        value * self.scale
    }

    fn skia(&self, color: Rgba) -> Color {
        Color::from_rgba8(color.r, color.g, color.b, color.a)
    }

    fn paint(&self, color: Rgba) -> Paint<'static> {
        let mut paint = Paint::default();
        paint.set_color(self.skia(color));
        paint.anti_alias = true;
        paint
    }

    pub fn clear(&mut self, color: Rgba) {
        self.pixmap.fill(self.skia(color));
    }

    pub fn fill_rect(&mut self, x: f32, y: f32, w: f32, h: f32, color: Rgba) {
        if w <= 0.0 || h <= 0.0 {
            return;
        }
        let x0 = self.sx(x);
        let y0 = self.sx(y);
        let x1 = self.sx(x + w);
        let y1 = self.sx(y + h);
        if let Some(rect) = Rect::from_ltrb(x0, y0, x1, y1) {
            let paint = self.paint(color);
            self.pixmap
                .fill_rect(rect, &paint, Transform::identity(), None);
        }
    }

    /// Rounded rectangle filled with one colour. Implemented as the union of a
    /// cross and four corner discs: correct for any radius that fits the box
    /// and avoids depending on path arc helpers.
    pub fn fill_round_rect(&mut self, x: f32, y: f32, w: f32, h: f32, radius: f32, color: Rgba) {
        if w <= 0.0 || h <= 0.0 {
            return;
        }
        let radius = radius.min(w / 2.0).min(h / 2.0).max(0.0);
        if radius <= 0.5 {
            self.fill_rect(x, y, w, h, color);
            return;
        }
        self.fill_rect(x + radius, y, w - radius * 2.0, h, color);
        self.fill_rect(x, y + radius, w, h - radius * 2.0, color);

        let mut builder = PathBuilder::new();
        let r = self.sx(radius);
        for (cx, cy) in [
            (x + radius, y + radius),
            (x + w - radius, y + radius),
            (x + radius, y + h - radius),
            (x + w - radius, y + h - radius),
        ] {
            builder.push_circle(self.sx(cx), self.sx(cy), r);
        }
        if let Some(path) = builder.finish() {
            let paint = self.paint(color);
            self.pixmap.fill_path(
                &path,
                &paint,
                FillRule::Winding,
                Transform::identity(),
                None,
            );
        }
    }

    /// Rounded panel with a border: fill the outer rounded rect with `border`
    /// and an inset rounded rect with `fill`. Keeps the interior a known,
    /// testable colour.
    #[allow(clippy::too_many_arguments)]
    pub fn fill_round_rect_bordered(
        &mut self,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        radius: f32,
        border: Rgba,
        fill: Rgba,
        thickness: f32,
    ) {
        let t = thickness.max(0.5);
        self.fill_round_rect(x, y, w, h, radius, border);
        self.fill_round_rect(
            x + t,
            y + t,
            w - t * 2.0,
            h - t * 2.0,
            (radius - t).max(0.0),
            fill,
        );
    }

    /// Draw a single line of text with the font size in logical pixels.
    /// `baseline` is the text baseline in logical pixels. Returns advance width.
    pub fn draw_text(&mut self, x: f32, baseline: f32, text: &str, size: f32, color: Rgba) -> f32 {
        let px = (size * self.scale).max(1.0);
        let baseline_px = self.sx(baseline);
        let mut pen = self.sx(x);
        for ch in text.chars() {
            if ch == ' ' {
                let (_, advance) = self.fonts.glyph(ch, px);
                pen += advance;
                continue;
            }
            let (glyph, _) = self.fonts.glyph(ch, px);
            let metrics = glyph.metrics;
            let canvas_width = self.pixmap.width() as i64;
            let canvas_height = self.pixmap.height() as i64;
            let gx = pen.round() as i64 + metrics.xmin as i64;
            let gy = baseline_px.round() as i64 - metrics.height as i64 - metrics.ymin as i64;
            self.blend_coverage(
                gx,
                gy,
                metrics.width as i64,
                metrics.height as i64,
                &glyph.coverage,
                color,
                canvas_width,
                canvas_height,
            );
            pen += metrics.advance_width;
        }
        (pen / self.scale) - x
    }

    /// Draw text clipped to `max_width` logical pixels, appending an ellipsis
    /// when it does not fit.
    pub fn draw_text_clipped(
        &mut self,
        x: f32,
        baseline: f32,
        text: &str,
        size: f32,
        color: Rgba,
        max_width: f32,
    ) -> f32 {
        let fitted =
            self.fonts
                .truncate_with_ellipsis(text, size * self.scale, max_width * self.scale);
        self.draw_text(x, baseline, &fitted, size, color)
    }

    /// Width of `text` in logical pixels.
    pub fn text_width(&mut self, text: &str, size: f32) -> f32 {
        self.fonts.text_width(text, size * self.scale) / self.scale
    }

    #[allow(clippy::too_many_arguments)]
    fn blend_coverage(
        &mut self,
        x: i64,
        y: i64,
        width: i64,
        height: i64,
        coverage: &[u8],
        color: Rgba,
        canvas_width: i64,
        canvas_height: i64,
    ) {
        if coverage.is_empty() || width <= 0 || height <= 0 {
            return;
        }
        let data = self.pixmap.data_mut();
        let bytes = data.as_mut_ptr();
        // tiny-skia stores premultiplied RGBA. Blend a premultiplied source:
        //   out = src + dst * (1 - alpha)
        let alpha = color.a as u32;
        for row in 0..height {
            let py = y + row;
            if py < 0 || py >= canvas_height {
                continue;
            }
            for col in 0..width {
                let gx = x + col;
                if gx < 0 || gx >= canvas_width {
                    continue;
                }
                let cov = coverage[(row * width + col) as usize] as u32;
                if cov == 0 {
                    continue;
                }
                let a = cov * alpha / 255;
                if a == 0 {
                    continue;
                }
                let index = ((py * canvas_width + gx) * 4) as usize;
                let inv = 255 - a;
                unsafe {
                    let dst = bytes.add(index);
                    *dst = ((color.r as u32 * a + *dst as u32 * inv) / 255) as u8;
                    *dst.add(1) = ((color.g as u32 * a + *dst.add(1) as u32 * inv) / 255) as u8;
                    *dst.add(2) = ((color.b as u32 * a + *dst.add(2) as u32 * inv) / 255) as u8;
                    *dst.add(3) = (a + *dst.add(3) as u32 * inv / 255).min(255) as u8;
                }
            }
        }
    }

    /// Draw an RGBA image scaled into a target rect, alpha-blended over the
    /// already painted background.
    pub fn draw_rgba_image(&mut self, x: f32, y: f32, w: f32, h: f32, image: &RgbaImage) {
        if w <= 0.0 || h <= 0.0 || image.width() == 0 || image.height() == 0 {
            return;
        }
        let target_w = (self.sx(w).round() as u32).max(1);
        let target_h = (self.sx(h).round() as u32).max(1);
        let scaled = image::imageops::resize(
            image,
            target_w,
            target_h,
            image::imageops::FilterType::Triangle,
        );
        let x0 = self.sx(x).round() as i64;
        let y0 = self.sx(y).round() as i64;
        let canvas_width = self.pixmap.width() as i64;
        let canvas_height = self.pixmap.height() as i64;
        let data = self.pixmap.data_mut();
        let bytes = data.as_mut_ptr();
        for row_index in 0..scaled.height() {
            let py = y0 + row_index as i64;
            if py < 0 || py >= canvas_height {
                continue;
            }
            for col_index in 0..scaled.width() {
                let px = x0 + col_index as i64;
                if px < 0 || px >= canvas_width {
                    continue;
                }
                let pixel = scaled.get_pixel(col_index, row_index);
                let a = pixel[3] as u32;
                if a == 0 {
                    continue;
                }
                let index = ((py * canvas_width + px) * 4) as usize;
                let inv = 255 - a;
                unsafe {
                    let dst = bytes.add(index);
                    *dst = ((pixel[0] as u32 * a + *dst as u32 * inv) / 255) as u8;
                    *dst.add(1) = ((pixel[1] as u32 * a + *dst.add(1) as u32 * inv) / 255) as u8;
                    *dst.add(2) = ((pixel[2] as u32 * a + *dst.add(2) as u32 * inv) / 255) as u8;
                    *dst.add(3) = (a + *dst.add(3) as u32 * inv / 255).min(255) as u8;
                }
            }
        }
    }

    /// Convert the premultiplied RGBA pixmap into the XRGB8888 buffer the
    /// compositor expects on a little-endian machine (byte order B, G, R, X).
    pub fn to_xrgb8888(&self) -> Vec<u8> {
        let source = self.pixmap.data();
        let mut out = Vec::with_capacity(source.len());
        for pixel in source.chunks_exact(4) {
            out.push(pixel[2]);
            out.push(pixel[1]);
            out.push(pixel[0]);
            out.push(255);
        }
        out
    }
}
