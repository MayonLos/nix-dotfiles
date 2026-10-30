use crate::{library::Library, self_command};
use anyhow::{bail, Context, Result};
use clap::{Args, Subcommand};
use fs2::FileExt;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    fs::{self, OpenOptions},
    io::{Read, Write},
    os::unix::{
        fs::{OpenOptionsExt, PermissionsExt},
        net::{UnixListener, UnixStream},
        process::CommandExt,
    },
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
    thread,
    time::{Duration, Instant},
};

#[derive(Subcommand)]
pub enum RecordCommand {
    /// 再次运行停止；无选项录制当前输出、无声音
    Toggle(Options),
    Status,
}
#[derive(Args, Clone, Serialize, Deserialize, Default)]
pub struct Options {
    #[arg(long, conflicts_with_all = ["window", "output"])]
    region: bool,
    #[arg(long, conflicts_with_all = ["region", "output"])]
    window: bool,
    /// 输出名，例如 eDP-1；省略则取光标所在输出
    #[arg(long)]
    output: Option<String>,
    /// 录制系统声音（默认关闭）
    #[arg(long)]
    system_audio: bool,
    /// 录制麦克风（默认关闭）
    #[arg(long)]
    mic: bool,
    /// 软件默认 libx264；硬件需显式选用并验证
    #[arg(long, default_value = "libx264", value_parser = ["libx264", "h264_nvenc", "h264_vaapi"])]
    encoder: String,
    /// VAAPI render node；仅与 h264_vaapi 一起使用
    #[arg(long, requires = "encoder")]
    device: Option<String>,
}
#[derive(Serialize, Deserialize)]
pub struct Spec {
    dir: PathBuf,
    file: PathBuf,
    options: Options,
    geometry: Option<String>,
    output: Option<String>,
    source: String,
}
fn output(cmd: &mut Command) -> Result<String> {
    let o = cmd.output()?;
    if !o.status.success() {
        bail!("命令失败: {}", String::from_utf8_lossy(&o.stderr).trim());
    }
    Ok(String::from_utf8(o.stdout)?.trim().to_owned())
}
fn mango(query: &str) -> Result<Value> {
    Ok(serde_json::from_str(&output(
        Command::new("mmsg").args(["get", query]),
    )?)?)
}
fn items(v: &Value) -> &[Value] {
    v.as_array()
        .or_else(|| v.get("clients").and_then(Value::as_array))
        .map(Vec::as_slice)
        .unwrap_or(&[])
}
fn rect(v: &Value) -> Option<String> {
    let n = |k| v.get(k).and_then(Value::as_f64).map(|x| x.round() as i64);
    let (x, y, w, h) = (n("x")?, n("y")?, n("width")?, n("height")?);
    if w < 2 || h < 2 {
        return None;
    }
    Some(format!("{x},{y} {w}x{h}"))
}
fn select(options: Options, dir: PathBuf) -> Result<Spec> {
    let mut source = String::from("output");
    let mut geometry = None;
    let mut monitor = options.output.clone();
    if options.region {
        geometry = Some(output(&mut Command::new("slurp"))?);
        source = "region".into();
    } else if options.window {
        let clients = mango("all-clients").context("窗口捕获需要 Mango IPC")?;
        let candidates: Vec<_> = items(&clients)
            .iter()
            .filter(|c| c["is_visible"] == true && c["is_minimized"] != true)
            .filter_map(|c| rect(c).map(|r| (r, c)))
            .collect();
        if candidates.is_empty() {
            bail!("没有可录制窗口");
        }
        let mut slurp = Command::new("slurp")
            .args(["-r", "-f", "%g"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()?;
        {
            let mut stdin = slurp.stdin.take().context("slurp stdin")?;
            for (r, _) in &candidates {
                writeln!(stdin, "{r}")?;
            }
        }
        let out = slurp.wait_with_output()?;
        if !out.status.success() {
            bail!("已取消选择");
        }
        let selected = String::from_utf8(out.stdout)?.trim().to_owned();
        let (_, c) = candidates
            .iter()
            .find(|(r, _)| r == &selected)
            .context("选择不属于可见窗口")?;
        source = format!(
            "{} · {}",
            c["appid"]
                .as_str()
                .or_else(|| c["app_id"].as_str())
                .unwrap_or("window"),
            c["title"].as_str().unwrap_or("")
        );
        geometry = Some(selected);
        monitor = c["monitor"].as_str().map(str::to_owned);
    }
    if geometry.is_none() && monitor.is_none() {
        monitor = mango("cursorpos")
            .ok()
            .and_then(|v| v["monitor"].as_str().map(str::to_owned));
        if monitor.is_none() {
            monitor = Some(output(Command::new("slurp").args(["-o", "-f", "%o"]))?);
        }
    }
    if let Some(o) = &monitor {
        if !options.window {
            source = format!("output:{o}");
        }
    }
    let home = std::env::var_os("HOME").context("HOME")?;
    let recordings = PathBuf::from(home).join("Videos/Recordings");
    fs::create_dir_all(&recordings)?;
    let file = recordings.join(format!(
        "Recording-{}-{}.mkv",
        chrono::Local::now().format("%Y-%m-%d_%H-%M-%S-%3f"),
        std::process::id()
    ));
    Ok(Spec {
        dir,
        file,
        options,
        geometry,
        output: monitor,
        source,
    })
}
fn socket(dir: &Path) -> PathBuf {
    dir.join("record.sock")
}
pub fn notify(body: &str, ongoing: bool) {
    let mut c = Command::new("timeout");
    c.args(["2s", "notify-send"]);
    c.args([
        "-a",
        "shots-mayon",
        "-h",
        "string:x-canonical-private-synchronous:shots-mayon-record",
        "-t",
        if ongoing { "0" } else { "7000" },
    ]);
    if ongoing {
        c.args(["-u", "critical"]);
    }
    let _ = c
        .args([
            if ongoing {
                "● 正在录屏"
            } else {
                "录屏"
            },
            body,
        ])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}
pub fn run(lib: &Library, command: RecordCommand) -> Result<()> {
    let lock = OpenOptions::new()
        .create(true)
        .truncate(false)
        .read(true)
        .write(true)
        .mode(0o600)
        .open(lib.dir.join("toggle.lock"))?;
    lock.lock_exclusive()?;
    let path = socket(&lib.dir);
    match command {
        RecordCommand::Status => {
            if let Ok(mut s) = UnixStream::connect(&path) {
                s.write_all(b"STATUS\n")?;
                s.set_read_timeout(Some(Duration::from_secs(2)))?;
                let mut info = String::new();
                s.read_to_string(&mut info)?;
                println!("{info}");
            } else {
                println!("未在录制");
            }
            Ok(())
        }
        RecordCommand::Toggle(options) => {
            if let Ok(mut s) = UnixStream::connect(&path) {
                s.set_read_timeout(Some(Duration::from_secs(35)))?;
                s.write_all(b"STOP\n")?;
                let mut info = String::new();
                s.read_to_string(&mut info)?;
                if !info.starts_with("已保存") {
                    bail!("{info}");
                }
                println!("{info}");
                return Ok(());
            }
            let spec = select(options, lib.dir.clone())?;
            let log = OpenOptions::new()
                .create(true)
                .append(true)
                .mode(0o600)
                .open(lib.dir.join("record.log"))?;
            let mut cmd = self_command()?;
            cmd.args(["record-worker", &serde_json::to_string(&spec)?])
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(log);
            unsafe {
                cmd.pre_exec(|| {
                    if libc::setsid() < 0 {
                        return Err(std::io::Error::last_os_error());
                    }
                    Ok(())
                });
            }
            let mut startup = StartGuard {
                child: cmd.spawn()?,
                ready: false,
            };
            for _ in 0..150 {
                if let Some(code) = startup.child.try_wait()? {
                    bail!(
                        "录制启动失败 ({code})，查看 {}/record.log",
                        lib.dir.display()
                    );
                }
                if let Ok(mut s) = UnixStream::connect(&path) {
                    s.set_read_timeout(Some(Duration::from_secs(3)))?;
                    s.write_all(b"STATUS\n")?;
                    let mut response = String::new();
                    s.read_to_string(&mut response)?;
                    anyhow::ensure!(response.starts_with("正在录制"), "录制握手无效");
                    startup.ready = true;
                    println!("{response}");
                    return Ok(());
                }
                thread::sleep(Duration::from_millis(100));
            }
            bail!("录制启动超时，查看 record.log")
        }
    }
}
/// Every failure after spawning must stop the private worker and its encoder.
struct StartGuard {
    child: Child,
    ready: bool,
}
impl Drop for StartGuard {
    fn drop(&mut self) {
        if self.ready || self.child.try_wait().ok().flatten().is_some() {
            return;
        }
        unsafe {
            libc::kill(self.child.id() as i32, libc::SIGTERM);
        }
        let deadline = Instant::now() + Duration::from_secs(30);
        while Instant::now() < deadline {
            if self.child.try_wait().ok().flatten().is_some() {
                return;
            }
            thread::sleep(Duration::from_millis(100));
        }
        // setsid() confined the worker and its children to this process group.
        unsafe {
            libc::kill(-(self.child.id() as i32), libc::SIGKILL);
        }
        let _ = self.child.wait();
    }
}
struct Mix(Vec<String>);
impl Drop for Mix {
    fn drop(&mut self) {
        for id in self.0.iter().rev() {
            let _ = Command::new("pactl")
                .args(["unload-module", id])
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status();
        }
    }
}
fn audio(options: &Options) -> Result<(Mix, Option<String>)> {
    let mut mix = Mix(vec![]);
    if !options.system_audio && !options.mic {
        return Ok((mix, None));
    }
    let mic = if options.mic {
        Some(output(Command::new("pactl").arg("get-default-source"))?)
    } else {
        None
    };
    let system = if options.system_audio {
        Some(format!(
            "{}.monitor",
            output(Command::new("pactl").arg("get-default-sink"))?
        ))
    } else {
        None
    };
    if mic.is_none() {
        return Ok((mix, system));
    }
    if system.is_none() {
        return Ok((mix, mic));
    }
    let name = format!("shots_mayon_{}", std::process::id());
    mix.0.push(output(Command::new("pactl").args([
        "load-module",
        "module-null-sink",
        &format!("sink_name={name}"),
        "channels=2",
        "sink_properties=device.description=ShotsMayon",
    ]))?);
    for src in [system, mic].into_iter().flatten() {
        mix.0.push(output(Command::new("pactl").args([
            "load-module",
            "module-loopback",
            &format!("source={src}"),
            &format!("sink={name}"),
            "latency_msec=30",
            "source_dont_move=true",
            "sink_dont_move=true",
        ]))?);
    }
    Ok((mix, Some(format!("{name}.monitor"))))
}
fn recorder_args(spec: &Spec, audio: Option<&str>) -> Vec<String> {
    let mut a = vec![
        "--no-dmabuf".into(),
        "-r".into(),
        "30".into(),
        "-c".into(),
        spec.options.encoder.clone(),
        "-f".into(),
        spec.file.to_string_lossy().into_owned(),
    ];
    if spec.options.encoder == "libx264" {
        a.extend([
            "-p".into(),
            "preset=ultrafast".into(),
            "-p".into(),
            "crf=23".into(),
            "-x".into(),
            "yuv420p".into(),
        ]);
    }
    if let Some(d) = &spec.options.device {
        a.extend(["-d".into(), d.clone()]);
    }
    if let Some(g) = &spec.geometry {
        a.extend(["-g".into(), g.clone()]);
    }
    if let Some(o) = &spec.output {
        a.extend(["-o".into(), o.clone()]);
    }
    if let Some(src) = audio {
        a.push(format!("--audio={src}"));
    }
    a
}
struct Recording(Child);
impl Recording {
    fn stop(&mut self) -> Result<bool> {
        if self.0.try_wait()?.is_some() {
            return Ok(false);
        }
        unsafe {
            libc::kill(self.0.id() as i32, libc::SIGINT);
        }
        let start = Instant::now();
        loop {
            if let Some(s) = self.0.try_wait()? {
                return Ok(s.success());
            }
            if start.elapsed() > Duration::from_secs(25) {
                self.0.kill()?;
                let _ = self.0.wait();
                bail!("编码器停止超时，文件可能不完整");
            }
            thread::sleep(Duration::from_millis(100));
        }
    }
}
impl Drop for Recording {
    fn drop(&mut self) {
        let _ = self.stop();
    }
}
struct SocketGuard(PathBuf);
impl Drop for SocketGuard {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.0);
    }
}
pub fn worker(spec: Spec) -> Result<()> {
    let lock = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .open(spec.dir.join("recording.lock"))?;
    lock.try_lock_exclusive().context("已有录屏进程")?;
    let terminate = Arc::new(AtomicBool::new(false));
    for sig in [libc::SIGTERM, libc::SIGINT, libc::SIGHUP] {
        signal_hook::flag::register(sig, terminate.clone())?;
    }
    let (mix, src) = audio(&spec.options)?;
    let mut recording = Recording(
        Command::new("wf-recorder")
            .args(recorder_args(&spec, src.as_deref()))
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .spawn()?,
    );
    thread::sleep(Duration::from_millis(700));
    if recording.0.try_wait()?.is_some() {
        bail!("wf-recorder 启动失败，请检查协议/编码器；见 record.log");
    }
    let path = socket(&spec.dir);
    if path.exists() {
        fs::remove_file(&path)?;
    }
    let listener = UnixListener::bind(&path)?;
    fs::set_permissions(&path, fs::Permissions::from_mode(0o600))?;
    let _guard = SocketGuard(path);
    listener.set_nonblocking(true)?;
    notify(
        &format!(
            "{}\n{}\n再次运行 shots-mayon record toggle 停止",
            spec.source,
            spec.file.display()
        ),
        true,
    );
    let mut stop_client = None;
    loop {
        if terminate.load(Ordering::Relaxed) {
            break;
        }
        if recording.0.try_wait()?.is_some() {
            notify("录制意外结束，请查看 record.log 和输出文件", false);
            bail!("编码器意外退出");
        }
        match listener.accept() {
            Ok((mut stream, _)) => {
                stream.set_read_timeout(Some(Duration::from_secs(1)))?;
                let mut buf = [0u8; 32];
                let n = stream.read(&mut buf).unwrap_or(0);
                if &buf[..n] == b"STOP\n" {
                    stop_client = Some(stream);
                    break;
                }
                let _ = writeln!(stream, "正在录制 {} · {}", spec.source, spec.file.display());
            }
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                thread::sleep(Duration::from_millis(100))
            }
            Err(e) => return Err(e.into()),
        }
    }
    let saved = recording.stop()?;
    let message = if saved {
        let sidecar = PathBuf::from(format!("{}.shots.json", spec.file.display()));
        fs::write(
            sidecar,
            serde_json::to_vec(&serde_json::json!({"source":spec.source}))?,
        )?;
        if let Ok(lib) = Library::open() {
            let _ = lib.index();
        }
        format!("已保存 {}", spec.file.display())
    } else {
        "录制失败，请检查 record.log".into()
    };
    drop(mix);
    notify(&message, false);
    if let Some(mut stream) = stop_client {
        let _ = writeln!(stream, "{message}");
    }
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn audio_is_opt_in_and_argv_is_literal() {
        let spec = Spec {
            dir: "/private".into(),
            file: "/private/a $(x).mkv".into(),
            options: Options {
                encoder: "libx264".into(),
                ..Default::default()
            },
            geometry: Some("0,0 100x100".into()),
            output: None,
            source: "test".into(),
        };
        let a = recorder_args(&spec, None);
        assert!(!a.iter().any(|a| a.starts_with("--audio")));
        assert!(a.contains(&"/private/a $(x).mkv".into()));
        assert!(a.contains(&"--no-dmabuf".into()));
        assert!(recorder_args(&spec, Some("sink.monitor")).contains(&"--audio=sink.monitor".into()));
    }
    #[test]
    fn mango_rectangles_use_global_logical_coordinates() {
        assert_eq!(
            rect(&serde_json::json!({"x":-1920,"y":24,"width":900,"height":600})),
            Some("-1920,24 900x600".into())
        );
        assert!(rect(&serde_json::json!({"x":0,"y":0,"width":0,"height":1})).is_none());
    }
}
