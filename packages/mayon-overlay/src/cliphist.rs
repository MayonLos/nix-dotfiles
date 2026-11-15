//! cliphist history reader and clipboard writer.
//!
//! cliphist owns the history database; this program never touches it directly.
//! `cliphist list` gives `id<TAB>preview` lines, `cliphist decode <id>` gives
//! the original bytes, and the selected bytes are handed back to the compositor
//! through `wl-copy` exactly like the previous fuzzel-based binding did.

use image::RgbaImage;
use std::io::Write;
use std::process::{Command, Stdio};

pub struct ClipEntry {
    pub id: i64,
    /// One-line preview produced by cliphist; for images it is the
    /// `[[ binary data N bytes png WxH ]]` marker.
    pub preview: String,
    pub is_image: bool,
    /// MIME type cliphist recorded for an image entry (defaults to image/png
    /// when the preview marker cannot be parsed).
    pub image_mime: Option<String>,
}

pub fn load_history() -> Result<Vec<ClipEntry>, String> {
    let output = Command::new("cliphist")
        .arg("list")
        .output()
        .map_err(|err| format!("cannot run cliphist: {}", err))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        return Err(if stderr.is_empty() {
            format!("cliphist list exited with {}", output.status)
        } else {
            format!("cliphist list failed: {}", stderr)
        });
    }
    let text = String::from_utf8_lossy(&output.stdout);
    let mut entries = Vec::new();
    for line in text.lines() {
        let Some((id_text, preview)) = line.split_once('\t') else {
            continue;
        };
        let Ok(id) = id_text.trim().parse::<i64>() else {
            continue;
        };
        let is_image = is_image_preview(preview);
        entries.push(ClipEntry {
            id,
            preview: preview.to_string(),
            is_image,
            image_mime: if is_image {
                Some(mime_from_preview(preview))
            } else {
                None
            },
        });
    }
    Ok(entries)
}

/// cliphist marks binary entries in the preview; PNG screenshots are the
/// common case on this host, and the preview also carries the recorded MIME
/// hint so JPEG/GIF copies are written back with the correct type.
fn is_image_preview(preview: &str) -> bool {
    preview.contains("[[ binary data")
}

fn mime_from_preview(preview: &str) -> String {
    for token in preview.split_whitespace() {
        let lowered = token.trim_end_matches(']').to_lowercase();
        let subtype = match lowered.as_str() {
            "png" => "png",
            "jpeg" | "jpg" => "jpeg",
            "gif" => "gif",
            "webp" => "webp",
            "bmp" => "bmp",
            "tiff" => "tiff",
            _ => continue,
        };
        return format!("image/{}", subtype);
    }
    "image/png".to_string()
}

pub fn decode(id: i64) -> Result<Vec<u8>, String> {
    let output = Command::new("cliphist")
        .args(["decode", &id.to_string()])
        .output()
        .map_err(|err| format!("cannot run cliphist decode: {}", err))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        return Err(format!("cliphist decode {} failed: {}", id, stderr));
    }
    Ok(output.stdout)
}

/// Decode the stored PNG and scale it down to a thumbnail no larger than the
/// requested box. The aspect ratio is preserved so thumbnails never stretch.
pub fn thumbnail(bytes: &[u8], max_width: u32, max_height: u32) -> Result<RgbaImage, String> {
    let image = image::load_from_memory(bytes).map_err(|err| format!("decode image: {}", err))?;
    let rgba = image.to_rgba8();
    let (width, height) = rgba.dimensions();
    if width <= max_width && height <= max_height {
        return Ok(rgba);
    }
    let scale_x = max_width as f32 / width as f32;
    let scale_y = max_height as f32 / height as f32;
    let scale = scale_x.min(scale_y).max(0.01);
    let target_width = ((width as f32 * scale).round() as u32).max(1);
    let target_height = ((height as f32 * scale).round() as u32).max(1);
    Ok(image::imageops::resize(
        &rgba,
        target_width,
        target_height,
        image::imageops::FilterType::Triangle,
    ))
}

/// Hand the decoded entry back to the Wayland clipboard. Text keeps wl-copy's
/// automatic text MIME choice; image entries are written with the MIME type
/// cliphist recorded so a JPEG copied earlier is not relabelled as PNG.
pub fn copy(bytes: &[u8], image_mime: Option<&str>) -> Result<(), String> {
    let mut command = Command::new("wl-copy");
    if let Some(mime) = image_mime {
        command.args(["--type", mime]);
    }
    // wl-copy forks a background owner process that serves the selection until
    // it is replaced. That child inherits every pipe not redirected to /dev/null,
    // so stdout/stderr must be null: otherwise waiting for the parent exit blocks
    // forever on pipe EOF that only the daemon could close.
    command.stdin(Stdio::piped());
    command.stdout(Stdio::null());
    command.stderr(Stdio::null());
    let mut child = command
        .spawn()
        .map_err(|err| format!("cannot run wl-copy: {}", err))?;
    {
        let mut stdin = child.stdin.take().ok_or("wl-copy stdin unavailable")?;
        stdin
            .write_all(bytes)
            .map_err(|err| format!("write to wl-copy failed: {}", err))?;
    }
    let status = child
        .wait()
        .map_err(|err| format!("wait for wl-copy failed: {}", err))?;
    if !status.success() {
        return Err(format!("wl-copy failed with {}", status));
    }
    Ok(())
}

/// First displayable line of a text entry, with control characters flattened.
pub fn preview_text(preview: &str) -> String {
    let mut out = String::new();
    for ch in preview.chars() {
        match ch {
            '\n' | '\r' | '\t' => out.push(' '),
            ch if (ch as u32) < 0x20 => out.push(' '),
            ch => out.push(ch),
        }
    }
    out.trim().to_string()
}
