//! frpc is an owned child: only a private config path appears in its argv.
use crate::model::*;
use anyhow::{bail, Context, Result};
use clap::Subcommand;
use serde::{Deserialize, Serialize};
use std::{
    fs::{self, OpenOptions},
    io::Read,
    os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt},
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
};

#[derive(Clone, Serialize, Deserialize)]
pub struct Settings {
    pub server_addr: String,
    pub server_port: u16,
    pub remote_port: u16,
    pub token_file: PathBuf,
    #[serde(default)]
    pub trusted_ca: Option<PathBuf>,
}
#[derive(Subcommand)]
pub enum FrpAction {
    /// 可选：用SSH主机作本机frp中转（明确确认）
    Relay {
        target: String,
        #[arg(long)]
        confirm: String,
        #[arg(long, default_value_t = 7000)]
        bind_port: u16,
        #[arg(long, default_value_t = 25565)]
        allow_start: u16,
        #[arg(long, default_value_t = 25575)]
        allow_end: u16,
    },
    RelayStop {
        target: String,
    },
    /// 配置实例隧道；name=lan 时用于客户端 LAN 世界
    Set {
        name: String,
        #[arg(long)]
        server: String,
        #[arg(long, default_value_t = 7000)]
        server_port: u16,
        #[arg(long)]
        remote_port: u16,
        #[arg(long)]
        token_file: PathBuf,
        #[arg(long)]
        trusted_ca: Option<PathBuf>,
    },
    Show {
        name: String,
    },
    Off {
        name: String,
    },
}
fn path(root: &Path, key: &str) -> Result<PathBuf> {
    valid_name(key)?;
    let dir = root.join("tunnels");
    private_dir(&dir)?;
    Ok(dir.join(format!("{key}.json")))
}
fn validate(c: &Settings) -> Result<()> {
    if c.server_addr.is_empty()
        || c.server_addr.len() > 253
        || !c
            .server_addr
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b".-:".contains(&b))
        || c.server_port == 0
        || c.remote_port < 1024
    {
        bail!("frps 地址须为主机名/IP，server-port 非零、remote-port 须1024..65535");
    }
    if !c.token_file.is_absolute() {
        bail!("token 文件须用绝对路径");
    }
    Ok(())
}
pub fn load_settings(root: &Path, key: &str) -> Result<Option<Settings>> {
    let path = path(root, key)?;
    no_symlinks(&path)?;
    if !path.exists() {
        return Ok(None);
    }
    let c = serde_json::from_slice(&fs::read(path)?)?;
    validate(&c)?;
    Ok(Some(c))
}
fn token(path: &Path) -> Result<String> {
    no_symlinks(path)?;
    let mut file = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK)
        .open(path)
        .context("无法打开 token 文件")?;
    let m = file.metadata()?;
    if !m.is_file()
        || m.uid() != unsafe { libc::getuid() }
        || m.mode() & 0o777 != 0o600
        || m.len() > 4096
    {
        bail!("token 须为当前用户拥有的0600普通文件，最大4096字节");
    }
    let mut text = String::new();
    file.by_ref()
        .take(4097)
        .read_to_string(&mut text)
        .context("token 必须是UTF-8")?;
    let text = text.trim();
    if text.is_empty() || text.len() > 4096 || text.chars().any(char::is_control) {
        bail!("token 内容无效（不显示内容）");
    }
    Ok(text.to_owned())
}
// JSON quoted strings are also valid TOML basic strings for these validated inputs.
fn quoted(text: &str) -> String {
    serde_json::to_string(text).expect("string serialization")
}
pub fn config(
    c: &Settings,
    name: &str,
    local_port: u16,
    local_ip: &str,
    secret: &str,
) -> Result<String> {
    validate(c)?;
    valid_name(name)?;
    if local_port == 0 {
        bail!("本地端口不能是0");
    }
    local_ip
        .parse::<std::net::IpAddr>()
        .context("隧道本地地址必须是IP")?;
    let ca = c
        .trusted_ca
        .as_ref()
        .map(|p| {
            format!(
                "transport.tls.trustedCaFile = {}\n",
                quoted(&p.to_string_lossy())
            )
        })
        .unwrap_or_default();
    Ok(format!("serverAddr = {}\nserverPort = {}\nauth.method = \"token\"\nauth.token = {}\ntransport.tls.enable = true\n{ca}log.to = \"console\"\nlog.level = \"error\"\nloginFailExit = true\n[[proxies]]\nname = {}\ntype = \"tcp\"\nlocalIP = {}\nlocalPort = {local_port}\nremotePort = {}\n", quoted(&c.server_addr), c.server_port, quoted(secret), quoted(&format!("mcsrv-{name}")), quoted(local_ip), c.remote_port))
}
pub fn action(root: &Path, action: FrpAction) -> Result<()> {
    match action {
        FrpAction::Relay { target,confirm,bind_port,allow_start,allow_end } => {
            return crate::remote::cloud(root,&target,&crate::remote::CloudAction::DeployFrps{confirm,bind_port,allow_start,allow_end});
        }
        FrpAction::RelayStop{target} => return crate::remote::cloud(root,&target,&crate::remote::CloudAction::Stop{name:"frps".into()}),
        FrpAction::Set { name, server, server_port, remote_port, token_file, trusted_ca } => {
            let c = Settings { server_addr:server, server_port, remote_port, token_file, trusted_ca };
            validate(&c)?;
            token(&c.token_file)?;
            write_private(&path(root,&name)?, &serde_json::to_vec_pretty(&c)?)?;
            println!("已保存隧道，下次启动生效。朋友连接：{}\n{}", address(&c), ROUTING_HINT);
        }
        FrpAction::Show { name } => match load_settings(root,&name)? {
            Some(c) => println!("朋友连接：{}（须启动且frps代理注册成功）\n{}", address(&c), ROUTING_HINT),
            None => println!("未配置公网隧道；frp set {name} --server HOST --remote-port PORT --token-file /绝对路径/token"),
        },
        FrpAction::Off { name } => {
            let p = path(root,&name)?;
            no_symlinks(&p)?;
            if p.exists() { fs::remove_file(p)?; }
            println!("配置已撤销；已启动的隧道在停止实例/LAN共享后退出");
        }
    }
    Ok(())
}
pub const ROUTING_HINT: &str = "Clash TUN：请将 frps 域名及解析后的公网IP置于 DIRECT（规则在代理规则之前）；程序不修改 Clash。子进程存活不代表代理注册成功，请从外网验证。";
pub fn address(c: &Settings) -> String {
    if c.server_addr.contains(':') {
        format!("[{}]:{}", c.server_addr, c.remote_port)
    } else {
        format!("{}:{}", c.server_addr, c.remote_port)
    }
}
pub struct Tunnel {
    child: Child,
    _directory: tempfile::TempDir,
}
impl Tunnel {
    pub fn check(&mut self) -> Result<()> {
        if self.child.try_wait()?.is_some() {
            bail!(
                "frpc 已退出：检查 frps 地址、token、远端端口和 DIRECT 规则；输出已抑制以保护凭据"
            );
        }
        Ok(())
    }
}
impl Drop for Tunnel {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}
pub fn start(root: &Path, key: &str, local_port: u16, bind: &str) -> Result<Option<Tunnel>> {
    let Some(c) = load_settings(root, key)? else {
        return Ok(None);
    };
    let secret = token(&c.token_file)?;
    let runtime = PathBuf::from(
        std::env::var_os("XDG_RUNTIME_DIR").context("frp 需 XDG_RUNTIME_DIR 私有运行目录")?,
    )
    .join("mcsrv-frp");
    private_dir(&runtime)?;
    let directory = tempfile::Builder::new()
        .prefix("tunnel-")
        .tempdir_in(runtime)?;
    fs::set_permissions(directory.path(), fs::Permissions::from_mode(0o700))?;
    let path = directory.path().join("frpc.toml");
    let local_ip = match bind {
        "" | "0.0.0.0" => "127.0.0.1",
        "::" => "::1",
        other => other,
    };
    write_private(
        &path,
        config(&c, key, local_port, local_ip, &secret)?.as_bytes(),
    )?;
    let mut cmd = Command::new("frpc");
    parent_death_signal(&mut cmd);
    for name in [
        "http_proxy",
        "HTTP_PROXY",
        "https_proxy",
        "HTTPS_PROXY",
        "all_proxy",
        "ALL_PROXY",
    ] {
        cmd.env_remove(name);
    }
    let child = cmd
        .arg("-c")
        .arg(path)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .context("启动 frpc 失败；Nix包应提供frp")?;
    println!("公网隧道已请求：{} · {}", address(&c), ROUTING_HINT);
    Ok(Some(Tunnel {
        child,
        _directory: directory,
    }))
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn modern_config_and_secret_permissions() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("secret");
        write_private(&p, b"not-a-real-token").unwrap();
        let c = Settings {
            server_addr: "127.0.0.1".into(),
            server_port: 17000,
            remote_port: 25565,
            token_file: p.clone(),
            trusted_ca: None,
        };
        let text = config(&c, "lan", 49152, "127.0.0.1", &token(&p).unwrap()).unwrap();
        assert!(
            text.contains("[[proxies]]")
                && text.contains("localPort = 49152")
                && text.contains("auth.token = \"not-a-real-token\"")
        );
        fs::set_permissions(p.clone(), fs::Permissions::from_mode(0o644)).unwrap();
        assert!(token(&p).is_err());
        std::os::unix::fs::symlink(&p, d.path().join("link")).unwrap();
        assert!(token(&d.path().join("link")).is_err());
    }
    #[test]
    fn toml_escapes_quote_and_backslash() {
        let c = Settings {
            server_addr: "example.org".into(),
            server_port: 7000,
            remote_port: 25565,
            token_file: "/tmp/token".into(),
            trusted_ca: None,
        };
        let text = config(&c, "friends", 25565, "::1", "a\"b\\c").unwrap();
        assert!(text.contains("auth.token = \"a\\\"b\\\\c\""));
        assert!(!text.contains("--token"));
    }
}
