//! Minecraft LAN discovery. UDP advertisements are hints, never authorization.
use anyhow::{bail, Context, Result};
use serde::{Deserialize, Serialize};
use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    net::{Ipv4Addr, SocketAddrV4, UdpSocket},
    os::{fd::FromRawFd, unix::fs::MetadataExt},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::atomic::{AtomicBool, Ordering},
    thread,
    time::{Duration, Instant},
};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct LanWorld {
    pub uid: u32,
    pub pid: u32,
    pub start_time: u64,
    pub port: u16,
    pub motd: Option<String>,
}
impl LanWorld {
    pub fn id(&self) -> String {
        format!(
            "{}_{}_{}_{}",
            self.uid, self.pid, self.start_time, self.port
        )
    }
    pub fn unit(&self) -> String {
        format!("mcsrv-lan@{}.service", self.id())
    }
}

fn parse_id(id: &str) -> Result<LanWorld> {
    let n: Vec<&str> = id.split('_').collect();
    if n.len() != 4
        || n.iter()
            .any(|s| s.is_empty() || !s.bytes().all(|b| b.is_ascii_digit()))
    {
        bail!("LAN 租约标识无效");
    }
    let world = LanWorld {
        uid: n[0].parse()?,
        pid: n[1].parse()?,
        start_time: n[2].parse()?,
        port: n[3].parse()?,
        motd: None,
    };
    if world.id() != id
        || world.uid == 0
        || world.pid == 0
        || world.start_time == 0
        || world.port < 1024
    {
        bail!("LAN 仅允许非 root 用户的 TCP 1024–65535 监听端口");
    }
    Ok(world)
}

fn start_time(stat: &str) -> Result<u64> {
    // comm may itself contain spaces and parentheses. Fields after the final ')' start at 3.
    stat.rsplit_once(')')
        .context("进程 stat 无效")?
        .1
        .split_whitespace()
        .nth(19)
        .context("进程启动时间缺失")?
        .parse()
        .context("进程启动时间无效")
}
fn process_uid(status: &str) -> Result<u32> {
    let ids: Vec<u32> = status
        .lines()
        .find_map(|s| s.strip_prefix("Uid:"))
        .context("进程 UID 缺失")?
        .split_whitespace()
        .map(str::parse)
        .collect::<std::result::Result<_, _>>()?;
    if ids.len() != 4 || ids.iter().any(|id| *id != ids[0]) {
        bail!("进程身份不一致");
    }
    Ok(ids[0])
}
fn is_client(cmdline: &[u8]) -> bool {
    let args: Vec<&str> = cmdline
        .split(|b| *b == 0)
        .filter_map(|a| std::str::from_utf8(a).ok())
        .collect();
    args.iter().any(|a| {
        matches!(
            *a,
            "org.prismlauncher.EntryPoint" | "net.minecraft.client.main.Main"
        )
    }) && !args
        .iter()
        .any(|a| *a == "nogui" || a.starts_with("net.minecraft.server."))
}
fn trusted_java(exe: &Path) -> bool {
    // The Nix wrapper fixes this map to its packaged Temurin derivations. Merely
    // naming a user-created Nix store file "java" is insufficient authorization.
    // Nix wraps Temurin's launcher; /proc/exe names its .java-wrapped sibling.
    // Accept only that exact sibling in the same pinned derivation, never a prefix.
    let allowed = std::env::var("MCSRV_JAVA_MAP")
        .ok()
        .and_then(|text| serde_json::from_str::<BTreeMap<String, String>>(&text).ok());
    allowed.is_some_and(|map| {
        map.values().any(|path| {
            fs::canonicalize(path)
                .is_ok_and(|path| path == exe || path.with_file_name(".java-wrapped") == exe)
        })
    }) && fs::metadata(exe).is_ok_and(|m| m.is_file() && m.uid() == 0 && m.mode() & 0o022 == 0)
}

fn home(uid: u32) -> Result<PathBuf> {
    let mut entry = std::mem::MaybeUninit::<libc::passwd>::uninit();
    let mut buffer = vec![0u8; 65536];
    let mut result = std::ptr::null_mut();
    // getpwuid_r keeps all returned strings in our buffer; copy before dropping it.
    let rc = unsafe {
        libc::getpwuid_r(
            uid,
            entry.as_mut_ptr(),
            buffer.as_mut_ptr().cast(),
            buffer.len(),
            &mut result,
        )
    };
    if rc != 0 || result.is_null() {
        bail!("无法查询用户主目录");
    }
    let dir = unsafe { std::ffi::CStr::from_ptr((*result).pw_dir) };
    Ok(PathBuf::from(dir.to_str()?))
}
fn prism_cwd(cwd: &Path, user_home: &Path) -> bool {
    let prefix = user_home.join(".local/share/PrismLauncher/instances");
    let Ok(relative) = cwd.strip_prefix(prefix) else {
        return false;
    };
    let components: Vec<_> = relative.components().collect();
    components.len() >= 2
        && matches!(
            components[1].as_os_str().to_str(),
            Some(".minecraft" | "minecraft")
        )
}
// Maps LISTEN socket inode to port, only for the requested UID and non-loopback bindings.
fn listeners(text: &str, uid: u32) -> BTreeMap<u64, u16> {
    text.lines()
        .skip(1)
        .filter_map(|line| {
            let f: Vec<_> = line.split_whitespace().collect();
            if f.len() < 10 || f[3] != "0A" || f[7].parse::<u32>().ok()? != uid {
                return None;
            }
            let (addr, p) = f[1].split_once(':')?;
            // 127/8 and ::1 cannot be reached by friends. Wildcard/real interface binds are accepted.
            if (addr.len() == 8 && addr.ends_with("7F"))
                || addr == "00000000000000000000000001000000"
            {
                return None;
            }
            let port = u16::from_str_radix(p, 16).ok()?;
            if port < 1024 {
                return None;
            }
            Some((f[9].parse().ok()?, port))
        })
        .collect()
}
fn sockets(proc_root: &Path, uid: u32) -> BTreeMap<u64, u16> {
    ["net/tcp", "net/tcp6"]
        .iter()
        .filter_map(|name| fs::read_to_string(proc_root.join(name)).ok())
        .flat_map(|text| listeners(&text, uid))
        .collect()
}
fn pid_ports(proc_root: &Path, pid: u32, sockets: &BTreeMap<u64, u16>) -> Result<BTreeSet<u16>> {
    let mut ports = BTreeSet::new();
    for entry in fs::read_dir(proc_root.join(pid.to_string()).join("fd"))? {
        let Ok(link) = fs::read_link(entry?.path()) else {
            continue;
        };
        if let Some(inode) = link
            .to_str()
            .and_then(|s| s.strip_prefix("socket:["))
            .and_then(|s| s.strip_suffix(']'))
            .and_then(|s| s.parse::<u64>().ok())
        {
            if let Some(port) = sockets.get(&inode) {
                ports.insert(*port);
            }
        }
    }
    Ok(ports)
}
fn validate_at(
    proc_root: &Path,
    world: &LanWorld,
    user_home: &Path,
    trusted: impl Fn(&Path) -> bool,
) -> Result<()> {
    parse_id(&world.id())?;
    let dir = proc_root.join(world.pid.to_string());
    let before = fs::read_to_string(dir.join("stat"))?;
    if start_time(&before)? != world.start_time {
        bail!("游戏进程已退出或 PID 已复用");
    }
    if process_uid(&fs::read_to_string(dir.join("status"))?)? != world.uid {
        bail!("监听进程不属于申请用户");
    }
    if !trusted(&fs::read_link(dir.join("exe"))?) {
        bail!("监听进程不是可信 Nix Java");
    }
    if !is_client(&fs::read(dir.join("cmdline"))?)
        || !prism_cwd(&fs::read_link(dir.join("cwd"))?, user_home)
    {
        bail!("未确认 Prism Minecraft 客户端");
    }
    if fs::read_link(dir.join("ns/net"))? != fs::read_link(proc_root.join("self/ns/net"))? {
        bail!("网络命名空间不一致");
    }
    if !pid_ports(proc_root, world.pid, &sockets(proc_root, world.uid))?.contains(&world.port) {
        bail!("游戏已不再监听该端口");
    }
    if start_time(&fs::read_to_string(dir.join("stat"))?)? != world.start_time {
        bail!("游戏进程发生变化");
    }
    Ok(())
}
/// Root uses this entry point with a fixed /proc; callers cannot substitute fixture roots.
pub fn validate_id(id: &str) -> Result<()> {
    let world = parse_id(id)?;
    validate_at(Path::new("/proc"), &world, &home(world.uid)?, trusted_java)
}
pub fn validate(world: &LanWorld) -> Result<()> {
    validate_id(&world.id())
}

pub fn discover() -> Result<Vec<LanWorld>> {
    let uid = unsafe { libc::getuid() };
    let user_home = home(uid)?;
    let proc_root = Path::new("/proc");
    let listening = sockets(proc_root, uid);
    let mut worlds = Vec::new();
    for entry in fs::read_dir(proc_root)? {
        let entry = entry?;
        let Some(pid) = entry
            .file_name()
            .to_str()
            .and_then(|s| s.parse::<u32>().ok())
        else {
            continue;
        };
        let Ok(status) = fs::read_to_string(entry.path().join("status")) else {
            continue;
        };
        if process_uid(&status).ok() != Some(uid) {
            continue;
        }
        let Ok(start_time) = fs::read_to_string(entry.path().join("stat"))
            .and_then(|s| start_time(&s).map_err(std::io::Error::other))
        else {
            continue;
        };
        for port in pid_ports(proc_root, pid, &listening).unwrap_or_default() {
            let world = LanWorld {
                uid,
                pid,
                start_time,
                port,
                motd: None,
            };
            if validate_at(proc_root, &world, &user_home, trusted_java).is_ok() {
                worlds.push(world);
            }
        }
    }
    if !worlds.is_empty() {
        if let Ok(hints) = announcements(Duration::from_millis(1100)) {
            for world in &mut worlds {
                world.motd = hints.get(&world.port).cloned();
            }
        }
    }
    worlds.sort_by_key(|w| (w.pid, w.port));
    Ok(worlds)
}

pub fn parse_announcement(packet: &[u8]) -> Option<(u16, String)> {
    if packet.len() > 2048 {
        return None;
    }
    let s = std::str::from_utf8(packet).ok()?;
    let (motd, port) = s.strip_prefix("[MOTD]")?.split_once("[/MOTD][AD]")?;
    let port = port.strip_suffix("[/AD]")?.parse::<u16>().ok()?;
    if port < 1024 || motd.chars().any(char::is_control) {
        return None;
    }
    Some((port, motd.chars().take(160).collect()))
}
fn announcements(timeout: Duration) -> Result<BTreeMap<u16, String>> {
    // REUSEADDR permits discovery alongside another multicast listener. No packet grants a lease.
    let fd = unsafe { libc::socket(libc::AF_INET, libc::SOCK_DGRAM | libc::SOCK_CLOEXEC, 0) };
    if fd < 0 {
        return Err(std::io::Error::last_os_error().into());
    }
    let socket = unsafe { UdpSocket::from_raw_fd(fd) };
    let reuse: libc::c_int = 1;
    if unsafe {
        libc::setsockopt(
            fd,
            libc::SOL_SOCKET,
            libc::SO_REUSEADDR,
            (&reuse as *const libc::c_int).cast(),
            std::mem::size_of_val(&reuse) as _,
        )
    } != 0
    {
        return Err(std::io::Error::last_os_error().into());
    }
    let addr = SocketAddrV4::new(Ipv4Addr::UNSPECIFIED, 4445);
    let raw = libc::sockaddr_in {
        sin_family: libc::AF_INET as _,
        sin_port: addr.port().to_be(),
        sin_addr: libc::in_addr { s_addr: 0 },
        sin_zero: [0; 8],
    };
    if unsafe {
        libc::bind(
            fd,
            (&raw as *const libc::sockaddr_in).cast(),
            std::mem::size_of_val(&raw) as _,
        )
    } != 0
    {
        return Err(std::io::Error::last_os_error().into());
    }
    socket.join_multicast_v4(&Ipv4Addr::new(224, 0, 2, 60), &Ipv4Addr::UNSPECIFIED)?;
    socket.set_read_timeout(Some(Duration::from_millis(100)))?;
    let deadline = Instant::now() + timeout;
    let mut hints = BTreeMap::new();
    let mut buffer = [0; 2049];
    while Instant::now() < deadline {
        if let Ok((n, _)) = socket.recv_from(&mut buffer) {
            if let Some((port, motd)) = parse_announcement(&buffer[..n]) {
                hints.insert(port, motd);
            }
        }
    }
    Ok(hints)
}

fn decode_binding(address: &str) -> Result<String> {
    let ip = match address.len() {
        8 => std::net::IpAddr::V4(std::net::Ipv4Addr::from(
            u32::from_str_radix(address, 16)?.to_ne_bytes(),
        )),
        32 => {
            let mut bytes = [0u8; 16];
            for (i, chunk) in address.as_bytes().chunks_exact(8).enumerate() {
                bytes[i * 4..i * 4 + 4].copy_from_slice(
                    &u32::from_str_radix(std::str::from_utf8(chunk)?, 16)?.to_ne_bytes(),
                );
            }
            std::net::IpAddr::V6(std::net::Ipv6Addr::from(bytes))
        }
        _ => bail!("监听地址格式无效"),
    };
    Ok(ip.to_string())
}
fn bind_address(world: &LanWorld) -> Result<String> {
    validate(world)?;
    let mut inodes = BTreeSet::new();
    for fd in fs::read_dir(format!("/proc/{}/fd", world.pid))? {
        if let Ok(link) = fs::read_link(fd?.path()) {
            if let Some(n) = link
                .to_str()
                .and_then(|s| s.strip_prefix("socket:["))
                .and_then(|s| s.strip_suffix(']'))
                .and_then(|s| s.parse::<u64>().ok())
            {
                inodes.insert(n);
            }
        }
    }
    for name in ["/proc/net/tcp", "/proc/net/tcp6"] {
        for line in fs::read_to_string(name)?.lines().skip(1) {
            let f: Vec<_> = line.split_whitespace().collect();
            if f.len() < 10
                || f[3] != "0A"
                || f[7].parse::<u32>().ok() != Some(world.uid)
                || !f[9]
                    .parse::<u64>()
                    .ok()
                    .is_some_and(|n| inodes.contains(&n))
            {
                continue;
            }
            if let Some((address, port)) = f[1].split_once(':') {
                if u16::from_str_radix(port, 16).ok() == Some(world.port) {
                    return decode_binding(address);
                }
            }
        }
    }
    bail!("LAN监听已变化")
}

pub fn lease(world: &LanWorld, verb: &str) -> Result<()> {
    if !matches!(verb, "start" | "restart" | "stop") {
        bail!("租约操作无效");
    }
    if verb != "stop" {
        validate(world)?;
    }
    if unsafe { libc::getuid() } != world.uid {
        bail!("不能管理其他用户的 LAN 租约");
    }
    if !Command::new("systemctl")
        .args(["--no-ask-password", verb, &world.unit()])
        .stdout(Stdio::null())
        .status()?
        .success()
    {
        bail!("LAN 临时防火墙申请失败；请确认宿主配置已重建并有 mcsrv-firewall 组权限");
    }
    Ok(())
}
static STOP: AtomicBool = AtomicBool::new(false);
extern "C" fn stop_signal(_: libc::c_int) {
    STOP.store(true, Ordering::SeqCst);
}
/// Foreground session: signals/game exit release the rule; root enforces the 90-second cap.
pub fn watch(root: &Path, world: &LanWorld, seconds: u64) -> Result<()> {
    if seconds == 0 || seconds > 86400 {
        bail!("共享时长须为 1–86400 秒");
    }
    STOP.store(false, Ordering::SeqCst);
    unsafe {
        libc::signal(
            libc::SIGTERM,
            stop_signal as *const () as libc::sighandler_t,
        );
        libc::signal(libc::SIGINT, stop_signal as *const () as libc::sighandler_t);
    }
    lease(world, "restart")?;
    struct Guard<'a>(&'a LanWorld);
    impl Drop for Guard<'_> {
        fn drop(&mut self) {
            let _ = lease(self.0, "stop");
        }
    }
    let _guard = Guard(world);
    println!(
        "LAN 已共享 TCP {}，最长 {} 秒；Ctrl+C 或游戏退出撤销。\n{}",
        world.port,
        seconds,
        crate::runtime::addresses()
    );
    let mut tunnel = crate::frp::start(root, "lan", world.port, &bind_address(world)?)?;
    let deadline = Instant::now() + Duration::from_secs(seconds);
    let mut renewed = Instant::now();
    while Instant::now() < deadline && !STOP.load(Ordering::SeqCst) {
        if validate(world).is_err() {
            break;
        }
        if let Some(tunnel) = &mut tunnel {
            tunnel.check()?;
        }
        if renewed.elapsed() >= Duration::from_secs(30) {
            lease(world, "restart")?;
            renewed = Instant::now();
        }
        thread::sleep(Duration::from_secs(1));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::symlink;
    fn fixture() -> (tempfile::TempDir, LanWorld) {
        let tmp = tempfile::tempdir().unwrap();
        for dir in ["77/fd", "77/ns", "self/ns", "net"] {
            fs::create_dir_all(tmp.path().join(dir)).unwrap();
        }
        let world = LanWorld {
            uid: 1000,
            pid: 77,
            start_time: 909,
            port: 50000,
            motd: None,
        };
        let mut fields = vec!["0"; 20];
        fields[19] = "909";
        fs::write(
            tmp.path().join("77/stat"),
            format!("77 (java (client)) {}", fields.join(" ")),
        )
        .unwrap();
        fs::write(tmp.path().join("77/status"), "Uid:\t1000 1000 1000 1000\n").unwrap();
        fs::write(
            tmp.path().join("77/cmdline"),
            b"java\0org.prismlauncher.EntryPoint\0",
        )
        .unwrap();
        symlink(
            "/nix/store/fixture-temurin/bin/java",
            tmp.path().join("77/exe"),
        )
        .unwrap();
        symlink(
            "/home/test/.local/share/PrismLauncher/instances/pack/.minecraft",
            tmp.path().join("77/cwd"),
        )
        .unwrap();
        for dir in ["77", "self"] {
            symlink("net:[1]", tmp.path().join(format!("{dir}/ns/net"))).unwrap();
        }
        symlink("socket:[1234]", tmp.path().join("77/fd/3")).unwrap();
        fs::write(
            tmp.path().join("net/tcp"),
            "header\n0: 00000000:C350 00000000:0000 0A 0:0 0:0 0 1000 0 1234\n",
        )
        .unwrap();
        (tmp, world)
    }
    fn check(tmp: &tempfile::TempDir, world: &LanWorld) -> bool {
        validate_at(tmp.path(), world, Path::new("/home/test"), |_| true).is_ok()
    }
    #[test]
    fn confirmed_client_socket_and_process_identity() {
        let (tmp, mut world) = fixture();
        assert!(check(&tmp, &world));
        assert!(validate_at(tmp.path(), &world, Path::new("/home/test"), |_| false).is_err());
        assert!(validate_at(tmp.path(), &world, Path::new("/home/other"), |_| true).is_err());
        world.port += 1;
        assert!(!check(&tmp, &world));
        world.port -= 1;
        world.uid += 1;
        assert!(!check(&tmp, &world));
        world.uid -= 1;
        world.start_time += 1;
        assert!(!check(&tmp, &world));
        world.start_time -= 1;
        fs::write(
            tmp.path().join("77/cmdline"),
            b"java\0-jar\0unrelated.jar\0",
        )
        .unwrap();
        assert!(!check(&tmp, &world));
    }
    #[test]
    fn exit_removed_listener_and_namespace_are_rejected() {
        let (tmp, world) = fixture();
        fs::remove_file(tmp.path().join("77/fd/3")).unwrap();
        assert!(!check(&tmp, &world));
        let (tmp, world) = fixture();
        fs::remove_file(tmp.path().join("77/ns/net")).unwrap();
        assert!(!check(&tmp, &world));
        let (tmp, world) = fixture();
        fs::remove_dir_all(tmp.path().join("77")).unwrap();
        assert!(!check(&tmp, &world));
    }
    #[test]
    fn strict_ids_and_advertisements() {
        assert_eq!(decode_binding("0100007F").unwrap(), "127.0.0.1");
        assert_eq!(
            decode_binding("00000000000000000000000001000000").unwrap(),
            "::1"
        );
        assert!(parse_id("1000_77_909_50000").is_ok());
        for id in [
            "0_77_909_50000",
            "1000_77_909_22",
            "01000_77_909_50000",
            "1000_77_909_65536",
            "1000_77_909_50000;touch",
        ] {
            assert!(parse_id(id).is_err());
        }
        assert_eq!(
            parse_announcement(b"[MOTD]Friends[/MOTD][AD]50000[/AD]"),
            Some((50000, "Friends".into()))
        );
        assert!(parse_announcement(b"[MOTD]x\n[/MOTD][AD]50000[/AD]").is_none());
        assert!(parse_announcement(b"[MOTD]x[/MOTD][AD]22[/AD]").is_none());
    }
    #[test]
    fn listener_uid_loopback_and_state_validation() {
        let text = "header\n0: 0100007F:C350 0:0 0A 0:0 0:0 0 1000 0 1\n1: 00000000:C351 0:0 01 0:0 0:0 0 1000 0 2\n2: 00000000:C352 0:0 0A 0:0 0:0 0 1001 0 3\n3: 00000000:C353 0:0 0A 0:0 0:0 0 1000 0 4\n";
        assert_eq!(listeners(text, 1000), BTreeMap::from([(4, 50003)]));
        assert!(!is_client(b"java\0net.minecraft.server.Main\0"));
        assert!(!is_client(b"java\0org.prismlauncher.EntryPoint\0nogui\0"));
        assert!(!trusted_java(Path::new("/tmp/java")));
    }
}
