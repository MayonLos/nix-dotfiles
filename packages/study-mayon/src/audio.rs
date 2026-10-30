use anyhow::{bail, Context, Result};
use std::{
    fs,
    io::{Read, Write},
    path::Path,
    process::{Command, Stdio},
    time::Duration,
};

pub fn speak(word: &str, provider: &str, root: &Path) -> Result<()> {
    if provider == "none" {
        bail!("发音已关闭");
    }
    if word.len() > 100
        || !word
            .chars()
            .all(|c| c.is_ascii_alphabetic() || c == '-' || c == '\'' || c == ' ')
    {
        bail!("发音仅支持英文单词/短语");
    }
    if provider == "youdao" {
        let cache = root.join("audio");
        fs::create_dir_all(&cache)?;
        let name = word
            .as_bytes()
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect::<String>();
        let path = cache.join(format!("{name}.mp3"));
        if !path.is_file() {
            let client = reqwest::blocking::Client::builder()
                .timeout(Duration::from_secs(8))
                .build()?;
            let response = client
                .get("https://dict.youdao.com/dictvoice")
                .query(&[("audio", word), ("type", "2")])
                .send()?
                .error_for_status()?;
            let content_type = response
                .headers()
                .get("content-type")
                .and_then(|v| v.to_str().ok())
                .unwrap_or("");
            if !content_type.starts_with("audio/") {
                bail!("有道未返回音频；请改用 espeak");
            }
            let mut bytes = Vec::new();
            response.take(1_048_577).read_to_end(&mut bytes)?;
            if bytes.is_empty() || bytes.len() > 1_048_576 {
                bail!("音频为空或超过 1 MiB");
            }
            let mut file = fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&path)?;
            file.write_all(&bytes)?;
        }
        if Command::new("mpv")
            .args(["--no-video", "--really-quiet"])
            .arg(&path)
            .stdin(Stdio::null())
            .status()
            .is_ok_and(|s| s.success())
        {
            return Ok(());
        }
    }
    let ok = Command::new("espeak-ng")
        .args(["-v", "en-us", "--", word])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .context("需要 espeak-ng（离线发音）或 mpv（缓存音频）")?;
    if !ok.success() {
        bail!("发音进程失败");
    }
    Ok(())
}
