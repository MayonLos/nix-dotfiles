use crate::{
    api::{Api, UA},
    danmaku,
    model::{number, Video},
    store::{self, Config},
};
use anyhow::{bail, Context, Result};
use futures_util::StreamExt;
use serde_json::Value;
use std::{
    path::{Path, PathBuf},
    process::Stdio,
    sync::atomic::{AtomicU64, Ordering},
    time::Duration,
};
use tokio::{
    io::{AsyncBufReadExt, AsyncWriteExt, BufReader},
    process::Command,
    sync::mpsc,
};

#[derive(Clone, Debug)]
pub struct Stream {
    pub video: String,
    pub audio: Option<String>,
    pub quality: u64,
    pub choices: Vec<(u64, String)>,
}
pub fn trusted_url(raw: &str) -> Result<url::Url> {
    let raw = if raw.starts_with("//") {
        format!("https:{raw}")
    } else {
        raw.to_string()
    };
    let mut url = url::Url::parse(&raw).context("媒体地址格式无效")?;
    if url.scheme() == "http" {
        let _ = url.set_scheme("https");
    }
    let host = url.host_str().unwrap_or("");
    if url.scheme() != "https"
        || !["bilivideo.com", "bilivideo.cn", "hdslb.com", "bilibili.com"]
            .iter()
            .any(|d| host == *d || host.ends_with(&format!(".{d}")))
        || !url.username().is_empty()
        || url.password().is_some()
        || url
            .port()
            .is_some_and(|port| ![443, 4483, 8082].contains(&port))
    {
        bail!("拒绝非 B 站媒体地址");
    }
    Ok(url)
}
pub fn parse_stream(data: &Value, quality: u64) -> Result<Stream> {
    let choices = data["accept_quality"]
        .as_array()
        .into_iter()
        .flatten()
        .enumerate()
        .map(|(i, q)| {
            (
                number(q),
                data["accept_description"][i]
                    .as_str()
                    .unwrap_or("DASH")
                    .into(),
            )
        })
        .collect();
    if let Some(videos) = data["dash"]["video"].as_array() {
        let video = videos
            .iter()
            .filter(|v| quality == 0 || number(&v["id"]) <= quality)
            .max_by_key(|v| {
                (
                    number(&v["id"]),
                    v["codecid"].as_u64() == Some(7),
                    number(&v["bandwidth"]),
                )
            })
            .context("所选清晰度不可用")?;
        let address = |v: &Value| {
            let base = v["baseUrl"].as_str().or_else(|| v["base_url"].as_str());
            let backups = v
                .get("backupUrl")
                .or_else(|| v.get("backup_url"))
                .and_then(Value::as_array);
            let mut addresses = base
                .into_iter()
                .chain(backups.into_iter().flatten().filter_map(Value::as_str))
                .filter_map(|raw| trusted_url(raw).ok())
                .collect::<Vec<_>>();
            // Prefer the ordinary HTTPS CDN over peer/edge ports; never forward credentials to arbitrary edge hosts.
            addresses.sort_by_key(|url| {
                (
                    url.port().is_some(),
                    !url.host_str().unwrap_or("").starts_with("upos-"),
                )
            });
            addresses.first().map(|url| url.as_str().to_string())
        };
        let video_url = address(video).context("视频流缺失")?;
        trusted_url(&video_url)?;
        let audio = data["dash"]["audio"]
            .as_array()
            .and_then(|a| a.iter().max_by_key(|a| number(&a["bandwidth"])))
            .and_then(address);
        if let Some(a) = &audio {
            trusted_url(a)?;
        }
        Ok(Stream {
            video: video_url,
            audio,
            quality: number(&video["id"]),
            choices,
        })
    } else {
        let url = data["durl"][0]["url"]
            .as_str()
            .context("没有可用流，可能需登录或会员")?;
        if data["durl"].as_array().is_some_and(|a| a.len() > 1) {
            bail!("此视频使用旧式多段流，暂不支持");
        }
        let url = trusted_url(url)?;
        Ok(Stream {
            video: url.to_string(),
            audio: None,
            quality: number(&data["quality"]),
            choices,
        })
    }
}
pub async fn resolve(api: &Api, video: &Video, cid: u64, quality: u64) -> Result<Stream> {
    let data = api
        .signed(
            "/x/player/wbi/playurl",
            &[
                ("bvid", video.bvid.clone()),
                ("cid", cid.to_string()),
                (
                    "qn",
                    if quality == 0 {
                        "127".into()
                    } else {
                        quality.to_string()
                    },
                ),
                ("fnval", "4048".into()),
                ("fnver", "0".into()),
                ("fourk", "1".into()),
            ],
        )
        .await?;
    parse_stream(&data, quality)
}
fn client() -> Result<reqwest::Client> {
    Ok(reqwest::Client::builder()
        .user_agent(UA)
        .redirect(reqwest::redirect::Policy::none())
        .connect_timeout(Duration::from_secs(20))
        .read_timeout(Duration::from_secs(45))
        .build()?)
}
pub async fn cover(url: &str) -> Result<Vec<u8>> {
    let response = client()?
        .get(trusted_url(url)?)
        .send()
        .await
        .map_err(|_| anyhow::anyhow!("封面请求失败"))?;
    if !response.status().is_success() {
        bail!("封面暂不可用");
    }
    let mut bytes = Vec::new();
    let mut stream = response.bytes_stream();
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|_| anyhow::anyhow!("封面读取失败"))?;
        if bytes.len() + chunk.len() > 8 * 1024 * 1024 {
            bail!("封面超过8MiB");
        }
        bytes.extend_from_slice(&chunk);
    }
    Ok(bytes)
}
static SEQUENCE: AtomicU64 = AtomicU64::new(0);
struct Temp(PathBuf);
impl Temp {
    fn new(label: &str) -> Result<Self> {
        let path = store::cache().join(format!(
            "{label}-{}-{}",
            std::process::id(),
            SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        store::private_dir(&path)?;
        Ok(Self(path))
    }
}
impl Drop for Temp {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}
fn mpv_config(cookie: &str) -> Result<Temp> {
    let temp = Temp::new("player")?;
    if cookie.contains(['\r', '\n', '"', '\\']) {
        bail!("cookie 含不支持的字符");
    }
    let value = if cookie.is_empty() {
        String::new()
    } else {
        format!("http-header-fields=\"Cookie: {cookie}\"\n")
    };
    store::write_private(&temp.0.join("http.conf"), value.as_bytes())?;
    Ok(temp)
}
pub async fn play(
    api: Api,
    video: Video,
    cid: u64,
    quality: u64,
    config: Config,
    null: bool,
    messages: mpsc::UnboundedSender<String>,
) -> Result<()> {
    let stream = resolve(&api, &video, cid, quality).await?;
    let runtime = mpv_config(api.cookie())?;
    let socket = runtime.0.join("mpv.sock");
    let mut command = Command::new("mpv");
    command
        .kill_on_drop(true)
        .arg(format!(
            "--include={}",
            runtime.0.join("http.conf").display()
        ))
        .args(["--no-terminal", "--really-quiet", "--hwdec=auto-safe"])
        .arg(format!("--force-media-title={}", video.title))
        .arg(format!("--referrer={}", video.link()))
        .arg(format!("--user-agent={UA}"))
        .arg(format!("--input-ipc-server={}", socket.display()));
    if let Some(audio) = &stream.audio {
        command.arg(format!("--audio-file={audio}"));
    }
    if config.danmaku && !null {
        let url = format!("https://comment.bilibili.com/{cid}.xml");
        let subtitle = async {
            let response = client()?
                .get(&url)
                .send()
                .await
                .map_err(|_| anyhow::anyhow!("弹幕下载失败"))?;
            if !response.status().is_success() {
                bail!("弹幕服务暂不可用");
            }
            let mut bytes = Vec::new();
            let mut chunks = response.bytes_stream();
            while let Some(chunk) = chunks.next().await {
                let chunk = chunk.map_err(|_| anyhow::anyhow!("弹幕读取失败"))?;
                if bytes.len() + chunk.len() > 16 * 1024 * 1024 {
                    bail!("弹幕超过16MiB");
                }
                bytes.extend_from_slice(&chunk);
            }
            let ass = danmaku::convert(std::str::from_utf8(&bytes)?, &config.danmaku_options)?;
            store::write_private(&runtime.0.join("danmaku.ass"), ass.as_bytes())?;
            Ok::<_, anyhow::Error>(())
        }
        .await;
        if subtitle.is_ok() {
            command.arg(format!(
                "--sub-file={}",
                runtime.0.join("danmaku.ass").display()
            ));
        } else {
            let _ = messages.send("弹幕不可用，继续播放；d 可切换弹幕".into());
        }
    }
    if null {
        command.args([
            "--no-config",
            "--scripts-clr",
            "--vo=null",
            "--ao=null",
            "--frames=24",
            "--network-timeout=15",
        ]);
    }
    command
        .arg("--")
        .arg(&stream.video)
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    let mut child = command.spawn().context("无法启动 mpv")?;
    let _ = messages.send(format!(
        "mpv 播放中 · Q{} · P{} · mpv 的 j 切换字幕",
        stream.quality, cid
    ));
    let mut tick = tokio::time::interval(Duration::from_secs(15));
    loop {
        tokio::select! {
            result=child.wait()=>{ if !result?.success(){bail!("mpv 播放失败，请检查网络、地区限制或流有效期");} break; }
            _=tick.tick(), if api.logged_in() && config.report_history && !null => {
                if let Ok(seconds)=position(&socket).await {
                    let result=api.post("/x/click-interface/web/heartbeat",&[("aid",video.aid.to_string()),("cid",cid.to_string()),("played_time",seconds.to_string()),("realtime","15".into()),("type","3".into()),("dt","2".into())]).await;
                    if result.is_err(){let _=messages.send("播放正常，历史回报失败（可在配置关闭）".into());}
                }
            }
        }
    }
    let _ = messages.send("mpv 已结束".into());
    Ok(())
}
async fn position(socket: &Path) -> Result<u64> {
    tokio::time::timeout(Duration::from_secs(2), async {
        let mut stream = tokio::net::UnixStream::connect(socket).await?;
        stream
            .write_all(b"{\"command\":[\"get_property\",\"time-pos\"],\"request_id\":7}\n")
            .await?;
        let mut lines = BufReader::new(stream).lines();
        while let Some(line) = lines.next_line().await? {
            let value: Value = serde_json::from_str(&line)?;
            if value["request_id"] == 7 {
                return Ok::<_, anyhow::Error>(value["data"].as_f64().unwrap_or(0.) as u64);
            }
        }
        bail!("播放器未返回位置")
    })
    .await?
}
#[derive(Clone)]
pub struct Download {
    pub id: usize,
    pub video: Video,
    pub cid: u64,
    pub quality: u64,
    pub audio_only: bool,
    pub directory: PathBuf,
}
#[derive(Clone, Debug)]
pub struct Progress {
    pub id: usize,
    pub state: String,
    pub bytes: u64,
}
pub async fn download_worker(
    api: Api,
    mut jobs: mpsc::UnboundedReceiver<Download>,
    updates: mpsc::UnboundedSender<Progress>,
) {
    while let Some(job) = jobs.recv().await {
        let result = download(&api, &job, &updates).await;
        let state = match result {
            Ok(()) => "已完成".into(),
            Err(e) => format!("失败：{e}"),
        };
        let _ = updates.send(Progress {
            id: job.id,
            state,
            bytes: 0,
        });
    }
}
fn filename(title: &str) -> String {
    let out: String = title
        .chars()
        .filter(|c| !c.is_control())
        .map(|c| if "/\\:*?\"<>|".contains(c) { '_' } else { c })
        .take(70)
        .collect();
    if out.trim_matches(['.', ' ']).is_empty() {
        "video".into()
    } else {
        out.trim_matches(['.', ' ']).into()
    }
}
async fn fetch(
    api: &Api,
    url: &str,
    path: &Path,
    job: &Download,
    updates: &mpsc::UnboundedSender<Progress>,
) -> Result<()> {
    let mut request = client()?
        .get(trusted_url(url)?)
        .header("Referer", job.video.link());
    if !api.cookie().is_empty() {
        request = request.header("Cookie", api.cookie());
    }
    let response = request
        .send()
        .await
        .map_err(|_| anyhow::anyhow!("下载连接失败"))?;
    if !response.status().is_success() {
        bail!("下载 HTTP {}", response.status().as_u16());
    }
    let mut file = tokio::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .await?;
    let mut stream = response.bytes_stream();
    let mut bytes = 0;
    let mut last = std::time::Instant::now();
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|_| anyhow::anyhow!("下载中断"))?;
        file.write_all(&chunk).await?;
        bytes += chunk.len() as u64;
        if last.elapsed() > Duration::from_millis(500) {
            let _ = updates.send(Progress {
                id: job.id,
                state: "下载中".into(),
                bytes,
            });
            last = std::time::Instant::now();
        }
    }
    file.sync_all().await?;
    Ok(())
}
async fn download(
    api: &Api,
    job: &Download,
    updates: &mpsc::UnboundedSender<Progress>,
) -> Result<()> {
    let stream = resolve(api, &job.video, job.cid, job.quality).await?;
    tokio::fs::create_dir_all(&job.directory).await?;
    let target = job.directory.join(format!(
        "{}-{}-{}.{}",
        filename(&job.video.title),
        job.video.bvid,
        job.cid,
        if job.audio_only { "m4a" } else { "mkv" }
    ));
    if target.exists() {
        bail!("目标已存在，未覆盖");
    }
    // Staging in the destination filesystem makes the final hard link atomic and non-clobbering.
    let temp = job.directory.join(format!(
        ".bilitui-{}-{}",
        std::process::id(),
        SEQUENCE.fetch_add(1, Ordering::Relaxed)
    ));
    store::private_dir(&temp)?;
    let owned = Temp(temp);
    let video = owned.0.join("video");
    let audio = owned.0.join("audio");
    let output = owned.0.join("output");
    if !job.audio_only || stream.audio.is_none() {
        fetch(api, &stream.video, &video, job, updates).await?;
    }
    if let Some(url) = &stream.audio {
        fetch(api, url, &audio, job, updates).await?;
    }
    let _ = updates.send(Progress {
        id: job.id,
        state: "FFmpeg 合并中".into(),
        bytes: 0,
    });
    let mut ffmpeg = Command::new("ffmpeg");
    ffmpeg
        .kill_on_drop(true)
        .args(["-nostdin", "-v", "error", "-n"]);
    if job.audio_only {
        ffmpeg
            .arg("-i")
            .arg(if stream.audio.is_some() {
                &audio
            } else {
                &video
            })
            .args(["-vn", "-c:a", "copy", "-f", "ipod"]);
    } else {
        ffmpeg.arg("-i").arg(&video);
        if stream.audio.is_some() {
            ffmpeg
                .arg("-i")
                .arg(&audio)
                .args(["-map", "0:v:0", "-map", "1:a:0"]);
        }
        ffmpeg.args(["-c", "copy", "-f", "matroska"]);
    }
    let status = ffmpeg
        .arg(&output)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .await
        .context("无法启动 ffmpeg")?;
    if !status.success() {
        bail!("FFmpeg 合并失败");
    }
    tokio::fs::hard_link(output, &target)
        .await
        .context("保存失败，目标可能已存在")?;
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn hosts_are_bounded() {
        assert!(trusted_url("https://a.bilivideo.com/a").is_ok());
        for u in [
            "https://bilivideo.com.attacker.org/a",
            "file:///etc/passwd",
            "https://u:p@a.bilivideo.com/x",
        ] {
            assert!(trusted_url(u).is_err());
        }
    }
    #[test]
    fn stream_quality_and_audio() {
        let v = serde_json::json!({"dash":{"video":[{"id":16,"baseUrl":"https://a.bilivideo.com/360","codecid":7},{"id":80,"baseUrl":"https://a.bilivideo.com/1080"}],"audio":[{"baseUrl":"https://a.bilivideo.com/a","bandwidth":10}]}});
        assert_eq!(parse_stream(&v, 0).unwrap().quality, 80);
        assert_eq!(parse_stream(&v, 16).unwrap().quality, 16);
        assert!(parse_stream(&v, 16).unwrap().audio.is_some());
    }
    #[test]
    fn rejects_edge_host_and_uses_bilibili_backup() {
        let data = serde_json::json!({"dash":{"video":[{"id":16,"baseUrl":"https://untrusted.example:4483/video","backupUrl":["https://upos-test.bilivideo.com/v"]}],"audio":[{"bandwidth":10,"baseUrl":"https://p.bilivideo.cn:8082/a","backupUrl":["https://upos-test.bilivideo.com/a"]}]}});
        let stream = parse_stream(&data, 16).unwrap();
        assert_eq!(stream.video, "https://upos-test.bilivideo.com/v");
        assert_eq!(
            stream.audio.as_deref(),
            Some("https://upos-test.bilivideo.com/a")
        );
    }
    #[test]
    fn safe_names() {
        assert_eq!(filename("../a\u{1b}/b:*"), "_a_b__");
    }
}
