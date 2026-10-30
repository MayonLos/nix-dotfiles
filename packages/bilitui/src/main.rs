mod api;
mod app;
mod danmaku;
mod media;
mod model;
mod store;

use anyhow::{bail, Context, Result};
use api::Api;
use std::{path::PathBuf, time::Duration};

#[tokio::main]
async fn main() {
    if let Err(error) = run().await {
        eprintln!("bilitui: {error}");
        std::process::exit(1);
    }
}
async fn run() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let mut demo = false;
    let mut demo_cover = None;
    let mut fixture = None;
    let mut probe = None;
    let mut probe_play = None;
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--help" | "-h" => {
                println!("bilitui-mayon — 终端浏览 B 站、mpv 播放与下载\n\n无参数：交互界面（L 扫码登录，可游客浏览）\n--demo                     离线视觉样例，不读 cookie、不联网\n--demo-cover PATH          离线样例封面 PNG/JPEG\n--fixture PATH             离线载入公开热门 JSON（隐含 --demo）\n--probe-public DIR         少量匿名公开只读请求并录制 fixture；mpv --vo=null 验证\n\n配置：~/.config/bilitui/config.toml\n状态：~/.local/share/bilitui/（cookie 0600）\n下载：~/Videos/Bilibili/\n? 帮助 · 1–9 切页 · s 搜索 · / 过滤 · q 退出");
                return Ok(());
            }
            "--convert-danmaku" => {
                let input = PathBuf::from(args.next().context("缺少 XML 路径")?);
                let output = PathBuf::from(args.next().context("缺少 ASS 路径")?);
                let ass = danmaku::convert(
                    &std::fs::read_to_string(input)?,
                    &danmaku::Options::default(),
                )?;
                std::fs::write(output, ass)?;
                return Ok(());
            }
            "--demo" => demo = true,
            "--demo-cover" => {
                demo_cover = Some(PathBuf::from(args.next().context("缺少封面路径")?))
            }
            "--fixture" => {
                fixture = Some(PathBuf::from(args.next().context("缺少 fixture 路径")?));
                demo = true;
            }
            "--probe-playurl" => {
                probe_play = Some(PathBuf::from(args.next().context("缺少录制目录")?))
            }
            "--probe-public" => probe = Some(PathBuf::from(args.next().context("缺少输出目录")?)),
            _ => bail!("未知参数，使用 --help 查看用法"),
        }
    }
    if let Some(directory) = probe_play {
        let api = Api::new(String::new())?;
        let video = model::Video::parse(&serde_json::from_slice::<serde_json::Value>(
            &std::fs::read(directory.join("view.json"))?,
        )?);
        let config = store::Config {
            report_history: false,
            danmaku: false,
            ..Default::default()
        };
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
        let result = tokio::time::timeout(
            Duration::from_secs(45),
            media::play(api, video.clone(), video.cid, 16, config, true, tx),
        )
        .await;
        let outcome = match result {
            Ok(Ok(())) => "OK · 匿名 Q16 DASH 音视频 · mpv --vo=null --ao=null --frames=24".into(),
            Ok(Err(e)) => format!("失败：{e}"),
            Err(_) => "超时：45秒后已取消本次播放器".into(),
        };
        while rx.try_recv().is_ok() {}
        std::fs::write(
            directory.join("null-playback-rust.txt"),
            format!("{outcome}\n未读取cookie，未POST，未回报历史。\n"),
        )?;
        println!("{outcome}");
        return Ok(());
    }
    if let Some(directory) = probe {
        return public_probe(directory).await;
    }
    let mut api = Api::new(if demo {
        String::new()
    } else {
        store::read_cookie()?
    })?;
    if !demo {
        if let Err(e) = api.initialize().await {
            eprintln!("设备标识暂不可用：{e}");
        }
    }
    let cover = demo_cover.map(std::fs::read).transpose()?;
    let config = if demo {
        store::Config::default()
    } else {
        store::config()?
    };
    let mut app = app::App::new(api, config, demo, cover);
    if let Some(path) = fixture {
        app.fixture(serde_json::from_slice(&std::fs::read(path)?)?);
    }
    app.run().await
}
async fn record(directory: &std::path::Path, name: &str, value: &serde_json::Value) -> Result<()> {
    tokio::fs::write(directory.join(name), serde_json::to_vec_pretty(value)?).await?;
    Ok(())
}
async fn public_probe(directory: PathBuf) -> Result<()> {
    // Deliberately never read config, cookies, account state or inherited auth.
    tokio::fs::create_dir_all(&directory).await?;
    let mut api = Api::new(String::new())?;
    let mut report = Vec::new();
    match api.initialize().await {
        Ok(()) => report.push("buvid: OK（仅匿名内存，不保存）".into()),
        Err(e) => report.push(format!("buvid: {e}")),
    };
    tokio::time::sleep(Duration::from_secs(4)).await;
    let popular = api
        .get(
            "/x/web-interface/popular",
            &[("pn", "1".into()), ("ps", "5".into())],
        )
        .await;
    let mut selected = None;
    match popular {
        Ok(v) => {
            record(&directory, "popular.json", &v).await?;
            selected = model::videos(&v["list"]).into_iter().next();
            report.push("popular: OK".into());
        }
        Err(e) => report.push(format!("popular: {e}")),
    }
    tokio::time::sleep(Duration::from_secs(4)).await;
    // signed() also fetches nav keys once; no automatic API retries.
    match api
        .signed(
            "/x/web-interface/wbi/search/type",
            &[
                ("search_type", "video".into()),
                ("keyword", "Rust".into()),
                ("page", "1".into()),
                ("page_size", "5".into()),
            ],
        )
        .await
    {
        Ok(v) => {
            record(&directory, "search.json", &v).await?;
            report.push("search: OK".into());
        }
        Err(e) => report.push(format!("search: {e}")),
    }
    tokio::time::sleep(Duration::from_secs(4)).await;
    let bvid = selected
        .as_ref()
        .map(|v| v.bvid.clone())
        .unwrap_or_else(|| "BV1xx411c7mD".into());
    match api.get("/x/web-interface/view", &[("bvid", bvid)]).await {
        Ok(v) => {
            record(&directory, "view.json", &v).await?;
            let video = model::Video::parse(&v);
            report.push("view: OK".into());
            tokio::time::sleep(Duration::from_secs(4)).await;
            match media::resolve(&api, &video, video.cid, 16).await {
                Ok(stream) => {
                    record(&directory,"playurl-summary.json",&serde_json::json!({"quality":stream.quality,"audio":stream.audio.is_some(),"choices":stream.choices})).await?;
                    let mut command = tokio::process::Command::new("mpv");
                    command.kill_on_drop(true).args([
                        "--no-config",
                        "--scripts-clr",
                        "--vo=null",
                        "--ao=null",
                        "--frames=24",
                        "--no-terminal",
                        "--really-quiet",
                    ]);
                    command
                        .arg(format!("--referrer={}", video.link()))
                        .arg(format!("--user-agent={}", api::UA));
                    if let Some(audio) = &stream.audio {
                        command.arg(format!("--audio-file={audio}"));
                    }
                    command
                        .arg("--")
                        .arg(&stream.video)
                        .stdout(std::process::Stdio::null())
                        .stderr(std::process::Stdio::null());
                    match tokio::time::timeout(Duration::from_secs(60), command.status()).await {
                        Ok(Ok(status)) if status.success() => report
                            .push("playurl Q16 + mpv --vo=null --ao=null --frames=24: OK".into()),
                        _ => report.push("playurl OK，mpv 拉流失败或超时（未保存流 URL）".into()),
                    }
                }
                Err(e) => report.push(format!("playurl: {e}")),
            }
            if !video.cover.is_empty() {
                match media::cover(&video.cover).await {
                    Ok(bytes) => {
                        tokio::fs::write(directory.join("cover.jpg"), bytes).await?;
                        report.push("cover: OK".into());
                    }
                    Err(e) => report.push(format!("cover: {e}")),
                }
            }
        }
        Err(e) => report.push(format!("view: {e}")),
    }
    let text = report.join("\n") + "\n全程匿名；没有二维码请求、账号登录、POST 或历史回报。\n";
    tokio::fs::write(directory.join("public-report.txt"), &text).await?;
    print!("{text}");
    Ok(())
}
