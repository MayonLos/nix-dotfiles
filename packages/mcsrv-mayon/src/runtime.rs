use crate::{backup, model::*};
use anyhow::{bail, Context, Result};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    collections::VecDeque,
    fs::{self, OpenOptions},
    io::{BufRead, BufReader, Read, Write},
    net::{TcpStream, ToSocketAddrs},
    os::unix::{
        fs::OpenOptionsExt,
        net::{UnixListener, UnixStream},
    },
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    thread,
    time::{Duration, Instant},
};
static STOP: AtomicBool = AtomicBool::new(false);
extern "C" fn signal_stop(_: libc::c_int) {
    STOP.store(true, Ordering::SeqCst);
}
fn socket(root: &Path, name: &str) -> Result<PathBuf> {
    let runtime = PathBuf::from(
        std::env::var("XDG_RUNTIME_DIR").context("XDG_RUNTIME_DIR 未设置；需用户运行时目录")?,
    )
    .join("mcsrv");
    private_dir(&runtime)?;
    let hash = hex::encode(Sha256::digest(format!("{}/{name}", root.display())));
    Ok(runtime.join(format!("{}.sock", &hash[..24])))
}
fn system_status(c: &mut Command) -> Result<()> {
    if !c.status()?.success() {
        bail!("systemd 操作失败");
    }
    Ok(())
}
pub fn start(root: &Path, name: &str) -> Result<()> {
    let c = load(root, name)?;
    let dir = instance(root, name)?;
    if running(&dir) {
        bail!("实例已运行");
    }
    let exe = std::env::var_os("MCSRV_SELF")
        .map(PathBuf::from)
        .unwrap_or(std::env::current_exe()?);
    let mut cmd = Command::new("systemd-run");
    cmd.args([
        "--user",
        "--collect",
        "--quiet",
        "--service-type=exec",
        "--unit",
        &format!("mcsrv@{name}.service"),
        "--property=TimeoutStopSec=900",
        "--property=KillMode=mixed",
        "--property=UMask=0077",
        "--property=NoNewPrivileges=yes",
    ]);
    // The generated Nix launcher sets Java paths; passing this public map also supports cargo dev.
    if let Ok(map) = std::env::var("MCSRV_JAVA_MAP") {
        cmd.arg(format!("--setenv=MCSRV_JAVA_MAP={map}"));
    }
    cmd.arg(exe).arg("--root").arg(root).arg("run").arg(name);
    system_status(&mut cmd)?;
    println!(
        "已请求启动 {} · {}MiB；服务不随开机启动",
        c.name, c.memory_mb
    );
    Ok(())
}
pub fn stop(root: &Path, name: &str) -> Result<()> {
    load(root, name)?;
    println!("{}", command(root, name, "stop")?);
    Ok(())
}
pub fn command(root: &Path, name: &str, text: &str) -> Result<String> {
    valid_name(name)?;
    if text.is_empty() || text.len() > 4096 || text.contains(['\r', '\n', '\0']) {
        bail!("命令须为单行，最长4096字节");
    }
    let mut s = UnixStream::connect(socket(root, name)?).context("服务器未运行或控制台尚未就绪")?;
    s.set_read_timeout(Some(Duration::from_secs(65)))?;
    s.set_write_timeout(Some(Duration::from_secs(5)))?;
    writeln!(s, "{text}")?;
    s.shutdown(std::net::Shutdown::Write)?;
    let mut response = String::new();
    s.take(1024 * 1024).read_to_string(&mut response)?;
    if let Some(e) = response.strip_prefix("ERROR ") {
        bail!("{e}");
    }
    Ok(response)
}
pub fn logs(dir: &Path) -> Result<String> {
    let p = dir.join("console.log");
    no_symlinks(&p)?;
    if !p.exists() {
        return Ok("尚无日志".into());
    }
    use std::io::{Seek, SeekFrom};
    let mut f = fs::File::open(p)?;
    let len = f.metadata()?.len();
    f.seek(SeekFrom::Start(len.saturating_sub(24000)))?;
    let mut bytes = Vec::new();
    f.read_to_end(&mut bytes)?;
    let s = String::from_utf8_lossy(&bytes);
    Ok(s.lines()
        .rev()
        .take(120)
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .collect::<Vec<_>>()
        .join("\n"))
}
pub fn addresses() -> String {
    Command::new("ip")
        .args(["-brief", "address", "show", "scope", "global"])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).to_string())
        .unwrap_or_else(|| "无法查询地址（需 iproute2）".into())
}
pub fn status(root: &Path, name: &str) -> Result<Value> {
    let c = load(root, name)?;
    let d = instance(root, name)?;
    let up = running(&d);
    let ready = up
        && crate::protocol::status(c.port, c.version.starts_with("1.7."), &c.bind)
            .ok()
            .is_some_and(|v| v.get("version").is_some());
    let pid = fs::read_to_string(d.join("java.pid"))
        .ok()
        .and_then(|s| s.trim().parse::<u32>().ok());
    let mem = if up {
        pid.and_then(|p| fs::read_to_string(format!("/proc/{p}/status")).ok())
            .and_then(|s| {
                s.lines()
                    .find_map(|l| l.strip_prefix("VmRSS:").map(str::trim).map(str::to_owned))
            })
    } else {
        None
    };
    // Metrics are explicitly unavailable unless the server offers these commands.
    let loader = fs::read(d.join("installed.json"))
        .ok()
        .and_then(|bytes| serde_json::from_slice::<Value>(&bytes).ok())
        .and_then(|v| v["loader"].as_str().map(str::to_owned))
        .unwrap_or_else(|| c.kind.clone());
    let tps_text = if ready && loader == "paper" {
        command(root, name, "tps").ok()
    } else if ready && (loader == "forge" || c.kind == "gtnh") {
        command(root, name, "forge tps").ok()
    } else {
        None
    };
    let mspt_text = if ready && loader == "paper" {
        command(root, name, "mspt").ok()
    } else {
        tps_text.clone()
    };
    let player_text = if ready {
        command(root, name, "list").ok().unwrap_or_default()
    } else {
        String::new()
    };
    let players: Vec<String> = player_text
        .lines()
        .find(|l| {
            l.contains("players online")
                || l.contains("players:")
                || l.contains("players connected")
        })
        .and_then(|l| l.rsplit_once(':').map(|(_, s)| s))
        .unwrap_or("")
        .split(',')
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_owned)
        .collect();
    fn number(text: Option<&str>, marker: &str) -> Option<f64> {
        let text = text?.split_once(marker)?.1;
        text.split(|c: char| !c.is_ascii_digit() && c != '.')
            .find_map(|t| t.parse().ok())
    }
    let overall = tps_text
        .as_deref()
        .and_then(|s| s.lines().find(|l| l.contains("Overall :")));
    let tps = if loader == "paper" {
        number(tps_text.as_deref(), "15m:")
    } else {
        number(overall, "Mean TPS:")
    };
    let mspt = if loader == "paper" {
        mspt_text
            .as_deref()
            .and_then(|s| s.lines().find(|l| l.contains("◴")))
            .and_then(|l| l.split_once("◴"))
            .and_then(|(_, s)| s.split('/').next())
            .and_then(|s| s.trim().parse::<f64>().ok())
    } else {
        number(overall, "Mean tick time:")
    };
    Ok(
        json!({"state":if up {if ready{"运行中"}else{"启动中"}}else{"已停止"},"players":players,"players_text":player_text,"memory":mem.unwrap_or_else(||"—".into()),"tps":tps,"mspt":mspt,"tps_text":tps_text,"mspt_text":mspt_text,"addresses":addresses().lines().map(str::to_owned).collect::<Vec<_>>(),"port":c.port}),
    )
}

fn firewall(port: u16, action: &str) -> Result<()> {
    if !(25565..=25575).contains(&port) {
        bail!("临时防火墙端口范围25565..25575");
    }
    system_status(Command::new("systemctl").args([
        "--no-ask-password",
        action,
        &format!("mcsrv-firewall@{port}.service"),
    ]))
}
struct Cleanup {
    socket: PathBuf,
    port: Option<u16>,
    pidfile: PathBuf,
}
impl Drop for Cleanup {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.socket);
        let _ = fs::remove_file(&self.pidfile);
        if let Some(port) = self.port {
            let _ = firewall(port, "stop");
        }
    }
}
struct ChildGuard(std::process::Child);
impl std::ops::Deref for ChildGuard {
    type Target = std::process::Child;
    fn deref(&self) -> &Self::Target {
        &self.0
    }
}
impl std::ops::DerefMut for ChildGuard {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.0
    }
}
impl Drop for ChildGuard {
    fn drop(&mut self) {
        if self.0.try_wait().ok().flatten().is_none() {
            let _ = self.0.kill();
        }
        let _ = self.0.wait();
    }
}
type Lines = Arc<Mutex<VecDeque<String>>>;
fn reader(
    stream: impl Read + Send + 'static,
    lines: Lines,
    file: Arc<Mutex<fs::File>>,
    secret: String,
) {
    thread::spawn(move || {
        for line in BufReader::new(stream)
            .lines()
            .map_while(std::result::Result::ok)
        {
            let line = line.replace(&secret, "[redacted]");
            if let Ok(mut f) = file.lock() {
                let _ = writeln!(f, "{line}");
            }
            if let Ok(mut all) = lines.lock() {
                all.push_back(line);
                if all.len() > 500 {
                    all.pop_front();
                }
            }
        }
    });
}
fn acknowledged(recent: &str, patterns: &[&str]) -> bool {
    recent.lines().any(|line| {
        let payload = line
            .split_once("]: ")
            .map_or(line, |(_, s)| s)
            .trim()
            .to_lowercase();
        let payload = payload.strip_prefix("system chat: ").unwrap_or(&payload);
        patterns.iter().any(|pattern| payload.starts_with(pattern))
    })
}
fn send(child: &mut std::process::ChildStdin, text: &str, lines: &Lines) -> Result<String> {
    let (cmd, wait) = match text {
        "@save-off" => (
            "save-off",
            Some(vec![
                "saving is now disabled",
                "turned off world auto-saving",
                "automatic saving is now disabled",
                "saving is already turned off",
            ]),
        ),
        "@save-all" => (
            "save-all",
            Some(vec![
                "saved the game",
                "saved the world",
                "saved the level",
                "save complete",
            ]),
        ),
        "@save-all-flush" => (
            "save-all flush",
            Some(vec![
                "saved the game",
                "saved the world",
                "saved the level",
                "save complete",
            ]),
        ),
        "@save-on" => (
            "save-on",
            Some(vec![
                "saving is now enabled",
                "turned on world auto-saving",
                "automatic saving is now enabled",
                "saving is already turned on",
            ]),
        ),
        s if s.starts_with('@') => bail!("未知内部命令"),
        other => (other, None),
    };
    lines
        .lock()
        .map_err(|_| anyhow::anyhow!("日志锁错误"))?
        .clear();
    writeln!(child, "{cmd}")?;
    child.flush()?;
    let until = Instant::now() + Duration::from_secs(if wait.is_some() { 55 } else { 1 });
    loop {
        let recent = lines
            .lock()
            .map_err(|_| anyhow::anyhow!("日志锁错误"))?
            .iter()
            .cloned()
            .collect::<Vec<_>>()
            .join("\n");
        if let Some(ref patterns) = wait {
            if acknowledged(&recent, patterns) {
                return Ok(recent);
            }
            if Instant::now() > until {
                bail!("未收到保存确认，取消备份；请检查控制台");
            }
        } else if Instant::now() > until || !recent.is_empty() {
            return Ok(if recent.is_empty() {
                "已发送（服务器无响应文本）".into()
            } else {
                recent
            });
        }
        thread::sleep(Duration::from_millis(50));
    }
}
pub fn run(root: &Path, name: &str) -> Result<()> {
    let c = load(root, name)?;
    let dir = instance(root, name)?;
    let _lock = lock(&dir, "run.lock")?;
    backup::backup_stopped(root, name)?;
    let path = socket(root, name)?;
    no_symlinks(&path)?;
    if path.exists() {
        fs::remove_file(&path)?;
    }
    let listener = UnixListener::bind(&path)?;
    listener.set_nonblocking(true)?;
    let _cleanup = Cleanup {
        socket: path,
        port: if c.lan { Some(c.port) } else { None },
        pidfile: dir.join("java.pid"),
    };
    if c.lan {
        firewall(c.port, "restart").context("开服已取消：临时防火墙权限或模块未部署")?;
    }
    let secret = fs::read_to_string(dir.join("rcon.secret"))?;
    let mut process = Command::new(&c.java);
    parent_death_signal(&mut process);
    process
        .current_dir(&dir)
        .arg(format!("-Xms{}M", c.memory_mb.min(1024)))
        .arg(format!("-Xmx{}M", c.memory_mb));
    if c.aikar {
        process.args([
            "-XX:+UnlockExperimentalVMOptions",
            "-XX:+UseG1GC",
            "-XX:+ParallelRefProcEnabled",
            "-XX:MaxGCPauseMillis=200",
            "-XX:+DisableExplicitGC",
            "-XX:+AlwaysPreTouch",
            "-XX:G1NewSizePercent=30",
            "-XX:G1MaxNewSizePercent=40",
            "-XX:G1HeapRegionSize=8M",
            "-XX:G1ReservePercent=20",
            "-XX:InitiatingHeapOccupancyPercent=15",
        ]);
    }
    let argv = if c.argv.first().is_some_and(|s| s == &c.java) {
        &c.argv[1..]
    } else {
        &c.argv[..]
    };
    process
        .args(argv)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    no_symlinks(&dir.join("console.log"))?;
    if dir.join("console.log").exists() {
        let logs = dir.join("logs-manager");
        private_dir(&logs)?;
        fs::rename(
            dir.join("console.log"),
            logs.join(format!(
                "{}.log",
                chrono::Utc::now().format("%Y%m%dT%H%M%S%.9f")
            )),
        )?;
    }
    let mut child = ChildGuard(process.spawn().context("Java 启动失败")?);
    write_private(&dir.join("java.pid"), child.id().to_string().as_bytes())?;
    let lines = Arc::new(Mutex::new(VecDeque::new()));
    no_symlinks(&dir.join("console.log"))?;
    let file = Arc::new(Mutex::new(
        OpenOptions::new()
            .create(true)
            .append(true)
            .mode(0o600)
            .open(dir.join("console.log"))?,
    ));
    // Start each session's tail at the new boot, retaining older logs under timestamped names.
    reader(
        child.stdout.take().unwrap(),
        lines.clone(),
        file.clone(),
        secret.clone(),
    );
    reader(child.stderr.take().unwrap(), lines.clone(), file, secret);
    let mut stdin = child.stdin.take().context("stdin 未建立")?;
    unsafe {
        libc::signal(
            libc::SIGTERM,
            signal_stop as *const () as libc::sighandler_t,
        );
        libc::signal(libc::SIGINT, signal_stop as *const () as libc::sighandler_t);
    }
    let mut renewed = Instant::now();
    let mut backed = Instant::now();
    let mut backup_job = None::<thread::JoinHandle<()>>;
    let mut stopping = None;
    let mut saving = false;
    loop {
        if let Some(exit) = child.try_wait()? {
            if !exit.success() {
                bail!("Java 退出: {exit}");
            }
            break;
        }
        if saving && lock(&dir, "operation.lock").is_ok() {
            // A backup caller died: it no longer holds the operation lock. Re-enable saving.
            let _ = send(&mut stdin, "@save-on", &lines);
            saving = false;
        }
        if STOP.load(Ordering::SeqCst) && stopping.is_none() && !saving {
            let _ = writeln!(stdin, "stop");
            let _ = stdin.flush();
            stopping = Some(Instant::now());
        }
        if stopping.is_some_and(|t| t.elapsed() > Duration::from_secs(65)) {
            let _ = child.kill();
            let _ = child.wait();
            bail!("优雅停止超时，已结束 Java；请检查存档");
        }
        if c.lan && renewed.elapsed() > Duration::from_secs(30) {
            if firewall(c.port, "restart").is_err() {
                STOP.store(true, Ordering::SeqCst);
            }
            renewed = Instant::now();
        }
        if c.backup_minutes > 0
            && backed.elapsed() > Duration::from_secs(c.backup_minutes as u64 * 60)
            && backup_job.as_ref().is_none_or(|j| j.is_finished())
            && stopping.is_none()
        {
            let r = root.to_path_buf();
            let n = name.to_owned();
            backup_job = Some(thread::spawn(move || {
                if let Err(e) = backup::backup(&r, &n) {
                    eprintln!("定时备份失败: {e:#}");
                }
            }));
            backed = Instant::now();
        }
        match listener.accept() {
            Ok((mut connection, _)) => {
                connection.set_read_timeout(Some(Duration::from_secs(3)))?;
                let mut request = String::new();
                let read = BufReader::new(&connection)
                    .take(4097)
                    .read_line(&mut request);
                let text = request.trim_end();
                if text == "stop" && !saving {
                    stopping = Some(Instant::now());
                }
                let result = match read {
                    Ok(_) if request.len() <= 4096 => {
                        if text.starts_with("@save-")
                            && (stopping.is_some() || (STOP.load(Ordering::SeqCst) && !saving))
                        {
                            Err(anyhow::anyhow!("服务器正在停止，拒绝开始在线备份"))
                        } else if saving
                            && !matches!(text, "@save-all" | "@save-all-flush" | "@save-on")
                        {
                            Err(anyhow::anyhow!(
                                "一致性备份进行中，暂拒绝控制台操作；完成后重试"
                            ))
                        } else {
                            if text == "@save-off" {
                                saving = true;
                            }
                            let result = send(&mut stdin, text, &lines);
                            if text == "@save-on" && result.is_ok() {
                                saving = false;
                            }
                            result
                        }
                    }
                    _ => Err(anyhow::anyhow!("控制台请求无效")),
                };
                match result {
                    Ok(s) => {
                        let _ = writeln!(connection, "{s}");
                    }
                    Err(e) => {
                        let _ = writeln!(connection, "ERROR {e:#}");
                    }
                }
            }
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                thread::sleep(Duration::from_millis(100))
            }
            Err(e) => return Err(e.into()),
        }
    }
    Ok(())
}
// Source RCON framing. Passwords are read only from this instance's private file.
pub fn rcon(root: &Path, name: &str, command: &str) -> Result<String> {
    let _operation = lock(&instance(root, name)?, "operation.lock")
        .context("备份或文件操作进行中，拒绝 RCON 写命令")?;
    let c = load(root, name)?;
    if !c.rcon {
        bail!("RCON 未启用；默认使用私有 Unix 控制台。测试创建时可 --rcon --bind 127.0.0.1");
    }
    if command.contains(['\r', '\n', '\0']) || command.len() > 4096 {
        bail!("RCON 命令格式无效");
    }
    let secret_path = instance(root, name)?.join("rcon.secret");
    no_symlinks(&secret_path)?;
    let secret = fs::read_to_string(secret_path)?;
    let addr = (
        if c.bind == "::1" { "::1" } else { "127.0.0.1" },
        c.port + 10000,
    )
        .to_socket_addrs()?
        .next()
        .context("地址错误")?;
    let mut s = TcpStream::connect_timeout(&addr, Duration::from_secs(3))?;
    s.set_read_timeout(Some(Duration::from_secs(5)))?;
    fn packet(s: &mut TcpStream, id: i32, kind: i32, text: &str) -> Result<()> {
        let mut out = Vec::new();
        out.extend_from_slice(&(text.len() as i32 + 10).to_le_bytes());
        out.extend_from_slice(&id.to_le_bytes());
        out.extend_from_slice(&kind.to_le_bytes());
        out.extend_from_slice(text.as_bytes());
        out.extend_from_slice(&[0, 0]);
        s.write_all(&out)?;
        Ok(())
    }
    fn recv(s: &mut TcpStream) -> Result<(i32, i32, String)> {
        let mut len = [0; 4];
        s.read_exact(&mut len)?;
        let n = i32::from_le_bytes(len);
        if !(10..=1024 * 1024).contains(&n) {
            bail!("RCON 帧超限");
        }
        let mut buf = vec![0; n as usize];
        s.read_exact(&mut buf)?;
        let id = i32::from_le_bytes(buf[0..4].try_into()?);
        let kind = i32::from_le_bytes(buf[4..8].try_into()?);
        Ok((
            id,
            kind,
            String::from_utf8_lossy(&buf[8..buf.len() - 2]).into(),
        ))
    }
    packet(&mut s, 1, 3, &secret)?;
    loop {
        let (id, kind, _) = recv(&mut s)?;
        if id == -1 {
            bail!("RCON 认证失败");
        }
        if kind == 2 {
            break;
        }
    }
    packet(&mut s, 2, 2, command)?;
    let (id, _, response) = recv(&mut s)?;
    if id != 2 {
        bail!("RCON 响应ID不匹配");
    }
    Ok(response.replace(&secret, "[redacted]"))
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn save_ack_accepts_system_reply_but_rejects_player_chat() {
        let patterns = ["automatic saving is now disabled"];
        assert!(acknowledged(
            "[12:10:06 INFO]: System chat: Automatic saving is now disabled",
            &patterns
        ));
        assert!(!acknowledged(
            "[12:10:06 INFO]: <player> Automatic saving is now disabled",
            &patterns
        ));
        assert!(!acknowledged(
            "[12:10:06 INFO]: System chat: [Server] Automatic saving is now disabled",
            &patterns
        ));
        assert!(acknowledged(
            "[12:10:06] [Server thread/INFO]: Turned on world auto-saving",
            &["turned on world auto-saving"]
        ));
    }
    #[test]
    fn rejects_multiline_command() {
        assert!(command(Path::new("/tmp"), "safe", "say ok\nstop").is_err());
    }
}
