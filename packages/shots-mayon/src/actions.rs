use crate::library::{Entry, Library};
use anyhow::{bail, Context, Result};
use std::{
    io::Write,
    process::{Command, Stdio},
};

pub fn copy(bytes: &[u8], mime: &str) -> Result<()> {
    let mut c = Command::new("wl-copy")
        .args(["--type", mime])
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;
    c.stdin
        .take()
        .context("clipboard stdin")?
        .write_all(bytes)?;
    if !c.wait()?.success() {
        bail!("剪贴板失败");
    }
    Ok(())
}
pub fn action(entry: &Entry, key: char, lib: &Library) -> Result<String> {
    let p = &entry.path;
    match key {
        'o' => {
            crate::spawn_reaped(
                Command::new("xdg-open")
                    .arg(p)
                    .stdout(Stdio::null())
                    .stderr(Stdio::null()),
            )?;
        }
        'y' => copy(p.as_bytes(), "text/plain;charset=utf-8")?,
        'c' if entry.kind == "image" => {
            let out = Command::new("ffmpeg")
                .args([
                    "-v",
                    "error",
                    "-protocol_whitelist",
                    "file,pipe",
                    "-i",
                    p,
                    "-frames:v",
                    "1",
                    "-f",
                    "image2pipe",
                    "-vcodec",
                    "png",
                    "-",
                ])
                .output()?;
            if !out.status.success() {
                bail!("图片转换失败");
            }
            copy(&out.stdout, "image/png")?;
        }
        'c' => bail!("只能复制截图"),
        't' => copy(entry.text.as_bytes(), "text/plain;charset=utf-8")?,
        'e' if entry.kind == "image" => {
            crate::spawn_reaped(
                Command::new("mark-shot")
                    .arg(p)
                    .stdout(Stdio::null())
                    .stderr(Stdio::null()),
            )?;
        }
        'e' => bail!("标注仅用于图片"),
        'f' => {
            // D-Bus structured argv; filenames never become shell code.
            let uri = file_uri(p);
            let argument = format!("['{}']", uri);
            let status = Command::new("gdbus")
                .args([
                    "call",
                    "--session",
                    "--dest",
                    "org.freedesktop.FileManager1",
                    "--object-path",
                    "/org/freedesktop/FileManager1",
                    "--method",
                    "org.freedesktop.FileManager1.ShowItems",
                    &argument,
                    "",
                ])
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status()?;
            if !status.success() {
                crate::spawn_reaped(
                    Command::new("xdg-open")
                        .arg(std::path::Path::new(p).parent().context("无父目录")?)
                        .stdout(Stdio::null())
                        .stderr(Stdio::null()),
                )?;
            }
        }
        '*' => lib.favorite(p)?,
        _ => bail!("未知操作"),
    }
    Ok("操作完成".into())
}
fn file_uri(path: &str) -> String {
    let mut s = String::from("file://");
    for b in path.bytes() {
        if b.is_ascii_alphanumeric() || b"/-_.~".contains(&b) {
            s.push(b as char);
        } else {
            s.push_str(&format!("%{b:02X}"));
        }
    }
    s
}
/// Only invoked after the TUI's two separate confirmation steps.
pub fn trash(entry: &Entry, lib: &Library) -> Result<()> {
    if !Command::new("trash-put")
        .args(["--", &entry.path])
        .status()?
        .success()
    {
        bail!("回收失败，保留索引");
    }
    lib.forget(&entry.path)?;
    Ok(())
}
#[cfg(test)]
mod tests {
    #[test]
    fn uri_never_injects_gvariant() {
        assert_eq!(super::file_uri("/a/'你?#"), "file:///a/%27%E4%BD%A0%3F%23");
    }
}
