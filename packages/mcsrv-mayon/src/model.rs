use anyhow::{bail, Context, Result};
use fs2::FileExt;
use rand::RngCore;
use serde::{Deserialize, Serialize};
use std::{
    fs::{self, File, OpenOptions},
    os::unix::fs::{OpenOptionsExt, PermissionsExt},
    path::{Component, Path, PathBuf},
};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub name: String,
    pub kind: String,
    pub version: String,
    pub memory_mb: u32,
    pub port: u16,
    pub online_mode: bool,
    pub whitelist: bool,
    pub java: String,
    pub argv: Vec<String>,
    pub backup_minutes: u32,
    pub keep_last: u32,
    pub lan: bool,
    pub aikar: bool,
    pub rcon: bool,
    pub bind: String,
}
pub fn valid_name(name: &str) -> Result<()> {
    if name.is_empty()
        || name.len() > 32
        || !name
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
    {
        bail!("名字须为 1–32 个 ASCII 字母、数字、- 或 _");
    }
    Ok(())
}
#[allow(dead_code)]
pub fn safe_relative(name: &str) -> Result<()> {
    if name.is_empty()
        || !Path::new(name)
            .components()
            .all(|x| matches!(x, Component::Normal(_)))
    {
        bail!("拒绝不安全的相对路径");
    }
    Ok(())
}
pub fn no_symlinks(path: &Path) -> Result<()> {
    let mut current = PathBuf::new();
    for part in path.components() {
        current.push(part);
        match fs::symlink_metadata(&current) {
            Ok(m) if m.file_type().is_symlink() => bail!("拒绝符号链接路径: {}", current.display()),
            Ok(_) => (),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => (),
            Err(e) => return Err(e.into()),
        }
    }
    Ok(())
}
pub fn private_dir(path: &Path) -> Result<()> {
    no_symlinks(path)?;
    fs::create_dir_all(path)?;
    fs::set_permissions(path, fs::Permissions::from_mode(0o700))?;
    Ok(())
}
pub fn write_private(path: &Path, content: &[u8]) -> Result<()> {
    no_symlinks(path)?;
    let mut tmp = tempfile::NamedTempFile::new_in(path.parent().context("无父目录")?)?;
    use std::io::Write;
    tmp.as_file()
        .set_permissions(fs::Permissions::from_mode(0o600))?;
    tmp.write_all(content)?;
    tmp.as_file().sync_all()?;
    tmp.persist(path)?;
    Ok(())
}
pub fn instance(root: &Path, name: &str) -> Result<PathBuf> {
    valid_name(name)?;
    let p = root.join(name);
    no_symlinks(&p)?;
    Ok(p)
}
pub fn load(root: &Path, name: &str) -> Result<Config> {
    let p = instance(root, name)?.join("instance.json");
    no_symlinks(&p)?;
    let mut c: Config = serde_json::from_slice(&fs::read(p)?)?;
    if c.name != name {
        bail!("实例名字与目录不一致");
    }
    // Minecraft itself persists commands such as `whitelist on` to this file.
    // Report effective settings, keeping instance.json as the creation/scheduling record.
    let properties = instance(root, name)?.join("server.properties");
    no_symlinks(&properties)?;
    if properties.exists() {
        let text = fs::read_to_string(properties)?;
        for line in text.lines() {
            let Some((key, value)) = line.split_once('=') else {
                continue;
            };
            let decoded = value.replace("\\:", ":");
            let value = decoded.trim();
            match key.trim() {
                "server-port" => c.port = value.parse().context("server-port 无效")?,
                "server-ip" => {
                    if !value.is_empty() {
                        value
                            .parse::<std::net::IpAddr>()
                            .context("server-ip 必须是IP地址")?;
                    }
                    c.bind = value.into();
                }
                "online-mode" => {
                    c.online_mode = value.parse().context("online-mode 必须true/false")?
                }
                "white-list" => c.whitelist = value.parse().context("white-list 必须true/false")?,
                _ => (),
            }
        }
    }
    if c.port == 0 || c.port > 55535 || !(512..=24576).contains(&c.memory_mb) {
        bail!("实例内存/端口超出支持范围");
    }
    Ok(c)
}
pub fn save(dir: &Path, c: &Config) -> Result<()> {
    write_private(&dir.join("instance.json"), &serde_json::to_vec_pretty(c)?)
}
pub fn lock(dir: &Path, name: &str) -> Result<File> {
    let path = dir.join(name);
    no_symlinks(&path)?;
    let f = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .open(path)?;
    f.try_lock_exclusive()
        .context("实例正在运行或执行其它操作")?;
    Ok(f)
}
pub fn running(dir: &Path) -> bool {
    lock(dir, "run.lock").is_err()
}
pub fn random_secret() -> String {
    let mut b = [0; 32];
    rand::thread_rng().fill_bytes(&mut b);
    hex::encode(b)
}
pub fn java_version(kind: &str, version: &str) -> &'static str {
    if kind == "gtnh" {
        return "21";
    }
    if kind == "paper" && (version.starts_with("1.20") || version.starts_with("1.21")) {
        return "21";
    }
    let parts: Vec<_> = version
        .split('.')
        .filter_map(|s| s.parse::<u32>().ok())
        .collect();
    match parts.as_slice() {
        [1, minor, patch, ..] if *minor == 20 && *patch >= 5 => "21",
        [1, minor, ..] if *minor >= 21 => "21",
        [1, minor, ..] if *minor >= 17 => "17",
        [1, ..] => "8",
        _ => "25",
    }
}
pub fn java_path(version: &str) -> Result<String> {
    let map = std::env::var("MCSRV_JAVA_MAP")
        .context("未找到 Temurin 映射；请使用 Nix 包，开发时设 MCSRV_JAVA_MAP")?;
    let map: std::collections::BTreeMap<String, String> = serde_json::from_str(&map)?;
    let p = map
        .get(version)
        .context("此 Temurin 版本未提供（可选8/17/21/25/26）")?;
    if !Path::new(p).is_absolute() || !Path::new(p).is_file() {
        bail!("Temurin 路径不可用");
    }
    Ok(p.clone())
}
pub fn worlds(dir: &Path) -> Result<Vec<String>> {
    let props = fs::read_to_string(dir.join("server.properties"))?;
    let level = props
        .lines()
        .find_map(|l| l.strip_prefix("level-name="))
        .unwrap_or("world");
    // Keep worlds at one directory level so rename-based rollback cannot cross trees.
    valid_name(level)?;
    let mut out = Vec::new();
    for name in [
        level.to_string(),
        format!("{level}_nether"),
        format!("{level}_the_end"),
    ] {
        no_symlinks(&dir.join(&name))?;
        if dir.join(&name).is_dir() {
            out.push(name);
        }
    }
    Ok(out)
}
/// Preserve pack-provided tuning while owning only the selected instance settings.
pub fn merge_properties(existing: &str, managed: &str, defaults: &str) -> String {
    fn key(line: &str) -> &str {
        line.split_once(['=', ':'])
            .map_or("", |(key, _)| key.trim())
    }
    let owned: Vec<_> = managed.lines().map(key).collect();
    let mut output = existing
        .lines()
        .filter(|line| !owned.contains(&key(line)))
        .collect::<Vec<_>>()
        .join("\n");
    output.push('\n');
    for line in defaults.lines() {
        if !existing.lines().any(|old| key(old) == key(line)) {
            output.push_str(line);
            output.push('\n');
        }
    }
    output.push_str("# mcsrv-mayon managed instance settings\n");
    output.push_str(managed);
    output
}
/// Ensure direct child work cannot outlive a crashed supervisor/backup caller.
/// Only async-signal-safe syscalls run after fork and before exec.
pub fn parent_death_signal(command: &mut std::process::Command) {
    use std::os::unix::process::CommandExt;
    let parent = std::process::id() as libc::pid_t;
    unsafe {
        command.pre_exec(move || {
            if libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGKILL) < 0 {
                return Err(std::io::Error::last_os_error());
            }
            if libc::getppid() != parent {
                libc::_exit(127);
            }
            Ok(())
        });
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn properties_preserve_pack_tuning() {
        let merged = merge_properties(
            "allow-flight=true\nlevel-type=RTG\nserver-port=1\n",
            "server-port=25565\n",
            "allow-flight=false\nview-distance=6\n",
        );
        assert!(merged.contains("allow-flight=true"));
        assert!(merged.contains("level-type=RTG"));
        assert!(!merged.contains("server-port=1\n"));
        assert!(merged.contains("view-distance=6"));
    }
    #[test]
    fn hostile_names() {
        for n in ["../x", "x/y", ".", "", "a b", "a\n"] {
            assert!(valid_name(n).is_err());
        }
    }
    #[test]
    fn version_selection() {
        assert_eq!(java_version("gtnh", "2.9.0"), "21");
        assert_eq!(java_version("forge", "1.7.10"), "8");
        assert_eq!(java_version("fabric", "1.20.4"), "17");
        assert_eq!(java_version("paper", "1.20.5"), "21");
        assert_eq!(java_version("paper", "26.1"), "25");
    }
    #[test]
    fn symlink_refusal() {
        let d = tempfile::tempdir().unwrap();
        std::os::unix::fs::symlink("/tmp", d.path().join("bad")).unwrap();
        assert!(private_dir(&d.path().join("bad/sub")).is_err());
    }
}
