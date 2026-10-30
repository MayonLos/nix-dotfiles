mod notifications;
use notifications::notify;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{
    env, fs,
    io::{self, BufRead, BufReader, Read, Write},
    os::{
        fd::{AsRawFd, FromRawFd},
        unix::{
            fs::{OpenOptionsExt, PermissionsExt},
            net::UnixListener,
        },
    },
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::mpsc,
    thread,
    time::{Duration, Instant},
};
static STOP: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
extern "C" fn stop_signal(_: libc::c_int) {
    STOP.store(true, std::sync::atomic::Ordering::Relaxed);
}
use mayon_voice::{client, runtime, socket_path, Config, Result};

fn engine_script(name: &str) -> PathBuf {
    env::var_os("MAYON_VOICE_ENGINE_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("engine"))
        .join(name)
}
#[derive(Clone, Serialize, Deserialize)]
struct Status {
    phase: String,
    engine: String,
    device: String,
    delivery: String,
    error: Option<String>,
}
impl Status {
    fn new(c: &Config) -> Self {
        Self {
            phase: "idle".into(),
            engine: c.engine.clone(),
            device: c.device.clone(),
            delivery: c.delivery.clone(),
            error: None,
        }
    }
}
struct Engine {
    child: Child,
    input: std::process::ChildStdin,
    output: BufReader<std::process::ChildStdout>,
}
impl Engine {
    fn launch(config: &Config) -> Result<Self> {
        let mut command = Command::new("python3");
        command
            .arg(engine_script("worker.py"))
            .arg("--engine")
            .arg(&config.engine)
            .arg("--model-dir")
            .arg(&config.model_dir)
            .arg("--provider")
            .arg(&config.device)
            .arg("--threads")
            .arg(config.threads.to_string())
            .arg("--whisper-binary")
            .arg(&config.whisper_binary);
        if let Some(model) = &config.model_file {
            command.arg("--model").arg(model);
        }
        let mut child = command
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()?;
        let input = child.stdin.take().ok_or("worker stdin")?;
        let output = BufReader::new(child.stdout.take().ok_or("worker stdout")?);
        Ok(Self {
            child,
            input,
            output,
        })
    }
    fn transcribe(&mut self, wav: &Path, hotwords: &[String]) -> Result<String> {
        writeln!(self.input, "{}", json!({"wav": wav, "hotwords":hotwords}))?;
        self.input.flush()?;
        let mut readiness = libc::pollfd {
            fd: self.output.get_ref().as_raw_fd(),
            events: libc::POLLIN,
            revents: 0,
        };
        if unsafe { libc::poll(&mut readiness, 1, 120_000) } <= 0 {
            return Err("本地识别超过 120 秒或被中断".into());
        }
        let mut line = String::new();
        self.output
            .by_ref()
            .take(1024 * 1024)
            .read_line(&mut line)?;
        let value: Value = serde_json::from_str(&line)?;
        if value.get("error").is_some_and(|e| !e.is_null()) {
            return Err("识别引擎失败；请检查模型和配置".into());
        }
        Ok(value["text"].as_str().ok_or("worker 缺少 text")?.into())
    }
}
impl Drop for Engine {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}
fn polish(text: &str, config: &Config) -> String {
    if !config.polish || text.is_empty() {
        return text.into();
    }
    let result = (|| -> Result<String> {
        let mut child = Command::new("python3")
            .arg(engine_script("polish.py"))
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()?;
        if let Some(mut input) = child.stdin.take() {
            write!(
                input,
                "{}",
                json!({"text":text,"key_file":config.key_file,"hotwords":config.hotwords})
            )?;
        }
        let deadline = Instant::now() + Duration::from_secs(3);
        loop {
            if child.try_wait()?.is_some() {
                break;
            }
            if Instant::now() >= deadline {
                let _ = child.kill();
                let _ = child.wait();
                return Err("润色超时".into());
            }
            thread::sleep(Duration::from_millis(10));
        }
        let mut output = String::new();
        child
            .stdout
            .take()
            .ok_or("polish stdout")?
            .take(65536)
            .read_to_string(&mut output)?;
        let value: Value = serde_json::from_str(&output)?;
        Ok(value["text"]
            .as_str()
            .filter(|s| !s.is_empty())
            .unwrap_or(text)
            .into())
    })();
    result.unwrap_or_else(|_| text.into())
}
fn run_input(program: &str, args: &[&str], input: &str) -> Result<bool> {
    let mut child = Command::new(program)
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;
    if let Some(mut pipe) = child.stdin.take() {
        pipe.write_all(input.as_bytes())?;
    }
    Ok(child.wait()?.success())
}
fn focus_token() -> String {
    Command::new("busctl")
        .args([
            "--user",
            "--timeout=2",
            "call",
            "org.fcitx.Fcitx5",
            "/mayon/voice",
            "org.mayon.Voice1",
            "FocusToken",
        ])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .and_then(|s| {
            s.trim()
                .strip_prefix("s ")
                .and_then(|s| serde_json::from_str::<String>(s).ok())
        })
        .unwrap_or_default()
}
fn fcitx(text: &str, token: &str) -> bool {
    if token.is_empty() {
        return false;
    }
    Command::new("busctl")
        .args([
            "--user",
            "--timeout=2",
            "call",
            "org.fcitx.Fcitx5",
            "/mayon/voice",
            "org.mayon.Voice1",
            "CommitStringForFocus",
            "ss",
            token,
            text,
        ])
        .output()
        .is_ok_and(|o| {
            o.status.success() && String::from_utf8_lossy(&o.stdout).trim() == "s \"committed\""
        })
}
fn deliver(text: &str, method: &str, token: &str) -> Result<String> {
    if text.trim().is_empty() {
        return Ok("silence".into());
    }
    if matches!(method, "auto" | "fcitx") && fcitx(text, token) {
        return Ok("fcitx".into());
    }
    if method == "fcitx" {
        return Err("Fcitx 无可提交焦点；未上屏".into());
    }
    // Virtual keyboard success cannot prove a client received a string. It is opt-in.
    if method == "wtype" {
        if run_input("wtype", &["-s", "150", "-"], text)? {
            return Ok("wtype".into());
        }
        return Err("virtual-keyboard 不可用；未上屏".into());
    }
    // Clipboard fallback deliberately does not guess Ctrl+V versus terminal Shift+Ctrl+V.
    // It replaces the selection only after Fcitx positively reports failure.
    if run_input("wl-copy", &["--type", "text/plain;charset=utf-8"], text)? {
        notify("文本已复制，请在目标程序粘贴（终端 Ctrl+Shift+V）");
        return Ok("clipboard-manual-paste".into());
    }
    Err("上屏失败；请确认 Fcitx addon 或 Wayland 剪贴板".into())
}
fn start_recording(c: &Config, wav: &Path) -> Result<Child> {
    let mut file = fs::OpenOptions::new()
        .create_new(true)
        .write(true)
        .mode(0o600)
        .open(wav)?;
    file.flush()?;
    let mut command = Command::new("pw-record");
    command.args(["--rate", "16000", "--channels", "1", "--format", "s16"]);
    if c.input_device != "auto" {
        command.arg("--target").arg(&c.input_device);
    }
    Ok(command
        .arg(wav)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?)
}
fn stop_recording(child: &mut Child) -> Result<()> {
    unsafe {
        libc::kill(child.id() as i32, libc::SIGINT);
    }
    let deadline = Instant::now() + Duration::from_secs(2);
    while child.try_wait()?.is_none() {
        if Instant::now() > deadline {
            child.kill()?;
            let _ = child.wait();
            return Err("录音程序未及时退出".into());
        }
        thread::sleep(Duration::from_millis(10));
    }
    Ok(())
}
struct Capture {
    child: Child,
    wav: PathBuf,
    started: Instant,
    focus: String,
}
impl Drop for Capture {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
        let _ = fs::remove_file(&self.wav);
    }
}
struct SocketCleanup(Option<PathBuf>);
impl Drop for SocketCleanup {
    fn drop(&mut self) {
        if let Some(path) = &self.0 {
            let _ = fs::remove_file(path);
        }
    }
}
fn listener() -> Result<(UnixListener, SocketCleanup)> {
    // systemd hands the sole ListenStream descriptor to this process as fd 3.
    if env::var("LISTEN_PID")
        .ok()
        .and_then(|s| s.parse::<u32>().ok())
        == Some(std::process::id())
        && env::var("LISTEN_FDS").ok().as_deref() == Some("1")
    {
        let socket = unsafe { UnixListener::from_raw_fd(3) };
        // Keep the activation socket out of pw-record / worker children.
        unsafe {
            libc::fcntl(3, libc::F_SETFD, libc::FD_CLOEXEC);
        }
        return Ok((socket, SocketCleanup(None)));
    }
    let path = socket_path()?;
    if path.exists() {
        return Err("socket 已存在；请使用 systemd socket 或独立 runtime".into());
    }
    let socket = UnixListener::bind(&path)?;
    fs::set_permissions(&path, fs::Permissions::from_mode(0o600))?;
    Ok((socket, SocketCleanup(Some(path))))
}
#[derive(Default)]
struct ToggleDebounce {
    last: Option<Instant>,
    transcribing_notified: bool,
}
impl ToggleDebounce {
    fn accept(&mut self, now: Instant) -> bool {
        let accept = self
            .last
            .is_none_or(|last| now.saturating_duration_since(last) >= Duration::from_millis(500));
        self.last = Some(now);
        accept
    }
    fn notify_transcribing(&mut self) -> bool {
        if self.transcribing_notified {
            return false;
        }
        self.transcribing_notified = true;
        true
    }
    fn completed(&mut self) {
        self.transcribing_notified = false;
    }
}

fn daemon() -> Result<()> {
    unsafe {
        libc::umask(0o077);
        libc::signal(libc::SIGTERM, stop_signal as *const () as usize);
        libc::signal(libc::SIGINT, stop_signal as *const () as usize);
    }
    let config = Config::load()?;
    let (socket, _socket_cleanup) = listener()?;
    notifications::startup();
    for entry in fs::read_dir(runtime()?)? {
        let entry = entry?;
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if name.starts_with("capture-") && name.ends_with(".wav") {
            let _ = fs::remove_file(entry.path());
        } else if name.starts_with("whisper-") && entry.file_type()?.is_dir() {
            let _ = fs::remove_dir_all(entry.path());
        }
    }
    socket.set_nonblocking(true)?;
    let mut status = Status::new(&config);
    let mut capture: Option<Capture> = None;
    let (tasks, rx) = mpsc::channel::<(PathBuf, String)>();
    let (results, completed) = mpsc::channel::<std::result::Result<String, String>>();
    let c = config.clone();
    let worker = thread::spawn(move || {
        let mut engine: Option<Engine> = None;
        for (wav, focus) in rx {
            let result = (|| -> Result<String> {
                if engine.is_none() {
                    engine = Some(Engine::launch(&c)?);
                }
                let text = engine
                    .as_mut()
                    .ok_or("engine")?
                    .transcribe(&wav, &c.hotwords)?;
                let text = polish(&text, &c);
                deliver(&text, &c.delivery, &focus)
            })();
            let _ = fs::remove_file(wav);
            if result.is_err() {
                engine = None;
            }
            let _ = results.send(result.map_err(|e| e.to_string()));
        }
    });
    let mut last = Instant::now();
    let mut sequence = 0_u64;
    let mut toggle = ToggleDebounce::default();
    loop {
        if STOP.load(std::sync::atomic::Ordering::Relaxed) {
            break;
        }
        if let Ok(result) = completed.try_recv() {
            toggle.completed();
            status.phase = "idle".into();
            last = Instant::now();
            match result {
                Ok(route) => {
                    status.error = None;
                    status.delivery = route.clone();
                    if route != "clipboard-manual-paste" {
                        notify(if route == "silence" {
                            "没有检测到语音"
                        } else {
                            "语音输入完成"
                        });
                    }
                }
                Err(e) => {
                    status.error = Some(e);
                    notify("识别或上屏失败；查看 mayon-voice status");
                }
            }
        }
        if capture
            .as_ref()
            .is_some_and(|r| r.started.elapsed() >= Duration::from_secs(config.max_record_seconds))
        {
            finish(&mut capture, &mut status, &tasks)?;
        }
        if let Some(r) = capture.as_mut() {
            if r.child.try_wait()?.is_some() {
                capture = None;
                status.phase = "idle".into();
                status.error = Some("录音设备不可用".into());
                notify("录音设备不可用");
                last = Instant::now();
            }
        }
        match socket.accept() {
            Ok((mut stream, _)) => {
                stream.set_read_timeout(Some(Duration::from_millis(500)))?;
                let mut command = String::new();
                if BufReader::new(&stream)
                    .take(64)
                    .read_line(&mut command)
                    .is_err()
                {
                    continue;
                }
                let command = command.trim();
                let mut error = None;
                match command {
                    "status" => {}
                    "toggle" if !toggle.accept(Instant::now()) => {}
                    "toggle" | "start" | "stop" => {
                        last = Instant::now();
                        if status.phase == "transcribing" {
                            error = Some("正在识别，请稍候");
                            if toggle.notify_transcribing() {
                                notify("正在识别 · 请稍候");
                            }
                        } else if capture.is_some() && command != "start" {
                            finish(&mut capture, &mut status, &tasks)?;
                        } else if capture.is_none() && command != "stop" {
                            sequence += 1;
                            let wav = runtime()?
                                .join(format!("capture-{}-{sequence}.wav", std::process::id()));
                            match start_recording(&config, &wav) {
                                Ok(child) => {
                                    capture = Some(Capture {
                                        child,
                                        wav,
                                        started: Instant::now(),
                                        focus: focus_token(),
                                    });
                                    status.phase = "recording".into();
                                    status.error = None;
                                    notify("录音中 · 再按快捷键结束");
                                }
                                Err(_) => {
                                    let _ = fs::remove_file(wav);
                                    error = Some("无法启动 PipeWire 录音");
                                }
                            }
                        }
                    }
                    _ => {
                        error = Some("未知命令");
                    }
                }
                let value = if let Some(e) = error {
                    json!({"error":e,"status":status})
                } else {
                    json!(status)
                };
                let _ = writeln!(stream, "{value}");
            }
            Err(e) if e.kind() == io::ErrorKind::WouldBlock => {}
            Err(e) => return Err(e.into()),
        }
        // Only idle time counts; the worker bounds a hung recognition separately.
        if status.phase == "idle"
            && capture.is_none()
            && last.elapsed() >= Duration::from_secs(config.idle_seconds)
        {
            break;
        }
        thread::sleep(Duration::from_millis(20));
    }
    notifications::shutdown();
    drop(capture);
    drop(tasks);
    if status.phase != "transcribing" {
        let _ = worker.join();
    }
    Ok(())
}
fn finish(
    capture: &mut Option<Capture>,
    status: &mut Status,
    tasks: &mpsc::Sender<(PathBuf, String)>,
) -> Result<()> {
    if let Some(mut recording) = capture.take() {
        if stop_recording(&mut recording.child).is_err() {
            status.phase = "idle".into();
            status.error = Some("录音结束失败".into());
            notify("录音结束失败");
            return Ok(());
        }
        let wav = recording.wav.clone();
        // Transfer file ownership to the worker; Capture's drop removes only its empty marker.
        recording.wav = PathBuf::new();
        status.phase = "transcribing".into();
        notify("识别中 · 本地模型");
        tasks.send((wav, recording.focus.clone()))?;
    }
    Ok(())
}
fn main() -> Result<()> {
    match env::args().nth(1).as_deref() {
        Some("daemon") => daemon(),
        Some("toggle" | "start" | "stop") => {
            let command = env::args().nth(1).unwrap();
            let value = client(&command)?;
            println!("{value}");
            if value.get("error").is_some_and(|e| !e.is_null()) {
                std::process::exit(1);
            }
            Ok(())
        }
        Some("status") => {
            match client("status") {
                Ok(value) => println!("{value}"),
                Err(e)
                    if e.to_string().contains("No such file")
                        || e.to_string().contains("Connection refused") =>
                {
                    println!("{}", json!({"phase":"inactive"}))
                }
                Err(e) => return Err(e),
            };
            Ok(())
        }
        Some("models") => {
            let config = Config::load()?;
            if env::args().nth(2).as_deref() != Some("fetch") {
                return Err("用法：mayon-voice models fetch（显式联网下载固定哈希模型）".into());
            }
            let result = Command::new("python3")
                .arg(engine_script("models.py"))
                .arg("--engine")
                .arg(config.engine)
                .arg("--model-dir")
                .arg(config.model_dir)
                .status()?;
            if !result.success() {
                return Err("模型下载失败".into());
            }
            Ok(())
        }
        Some("config") => {
            println!("{}", toml::to_string_pretty(&Config::default())?);
            Ok(())
        }
        _ => {
            println!("mayon-voice toggle|start|stop|status|config|models fetch\n本地语音输入 · 默认 CPU · 配置 ~/.config/mayon-voice/config.toml");
            Ok(())
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn toggle_bursts_slide_the_debounce_window_without_flipping_recording() {
        let start = Instant::now();
        let mut toggle = ToggleDebounce::default();
        assert!(toggle.accept(start));
        for elapsed in (33..=990).step_by(33) {
            assert!(!toggle.accept(start + Duration::from_millis(elapsed)));
        }
        assert!(!toggle.accept(start + Duration::from_millis(1489)));
        assert!(toggle.accept(start + Duration::from_millis(1989)));
    }
    #[test]
    fn transcribing_notice_is_sent_once_until_completion() {
        let mut toggle = ToggleDebounce::default();
        assert!(toggle.notify_transcribing());
        assert!(!toggle.notify_transcribing());
        toggle.completed();
        assert!(toggle.notify_transcribing());
    }
    #[test]
    fn defaults_are_local_cpu() {
        let c = Config::default();
        assert_eq!(c.device, "cpu");
        assert!(!c.polish);
        assert_eq!(c.idle_seconds, 600);
    }
    #[test]
    fn config_rejects_unknown_keys() {
        assert!(toml::from_str::<Config>("api_key='secret'").is_err());
    }
    #[test]
    fn config_roundtrip() {
        let c = Config::default();
        let s = toml::to_string(&c).unwrap();
        let back: Config = toml::from_str(&s).unwrap();
        assert_eq!(back.delivery, "auto");
    }
    #[test]
    fn silence_is_not_delivered() {
        assert_eq!(deliver(" \n", "auto", "").unwrap(), "silence");
    }
}
