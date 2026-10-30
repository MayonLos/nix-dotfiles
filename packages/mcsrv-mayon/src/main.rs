mod backup;
mod frp;
mod install;
mod lan;
mod model;
mod mods;
mod protocol;
mod remote;
mod runtime;
mod tui;
mod world;
use anyhow::{bail, Context, Result};
use clap::{Parser, Subcommand};
use model::*;
use std::{fs, path::PathBuf, process::Command};
#[derive(Parser)]
#[command(version, about = "Minecraft 服务器管家 · 本地实例、存档与联机")]
struct Cli {
    #[arg(long, global = true)]
    root: Option<PathBuf>,
    #[arg(long)]
    demo: bool,
    #[command(subcommand)]
    command: Option<Action>,
}
#[derive(Subcommand)]
enum Action {
    List,
    /// Minecraft 客户端局域网世界
    Lan {
        #[command(subcommand)]
        action: LanAction,
    },
    #[command(hide = true)]
    LanValidate {
        id: String,
    },
    Frp {
        #[command(subcommand)]
        action: frp::FrpAction,
    },
    Target {
        #[command(subcommand)]
        action: remote::TargetAction,
    },
    Cloud {
        target: String,
        #[command(subcommand)]
        action: remote::CloudAction,
    },
    Create {
        name: String,
        #[arg(long, default_value = "paper")]
        kind: String,
        #[arg(long, default_value = "latest")]
        version: String,
        #[arg(long, default_value_t = 2048)]
        memory: u32,
        #[arg(long, default_value_t = 25565)]
        port: u16,
        #[arg(long)]
        offline: bool,
        #[arg(long)]
        whitelist: bool,
        #[arg(long)]
        world: Option<PathBuf>,
        #[arg(long)]
        source: Option<String>,
        #[arg(long)]
        java: Option<String>,
        #[arg(long)]
        accept_eula: bool,
        #[arg(long)]
        rcon: bool,
        #[arg(long, default_value = "")]
        bind: String,
        #[arg(long)]
        aikar: bool,
    },
    Start {
        name: String,
    },
    Stop {
        name: String,
    },
    #[command(hide = true)]
    Run {
        name: String,
    },
    Status {
        name: String,
    },
    Logs {
        name: String,
    },
    Command {
        name: String,
        command: String,
    },
    Rcon {
        name: String,
        command: String,
    },
    Backup {
        name: String,
    },
    Backups {
        name: String,
    },
    Restore {
        name: String,
        snapshot: String,
        #[arg(long)]
        confirm: String,
    },
    Config {
        name: String,
        #[arg(long)]
        backup_minutes: Option<u32>,
        #[arg(long)]
        keep_last: Option<u32>,
        #[arg(long)]
        lan: bool,
        #[arg(long)]
        no_lan: bool,
    },
    Mods {
        name: String,
        #[command(subcommand)]
        action: ModAction,
    },
    Network {
        name: String,
        #[arg(long)]
        connect: bool,
    },
}
#[derive(Subcommand)]
enum LanAction {
    List,
    Share {
        #[arg(long)]
        port: Option<u16>,
        #[arg(long, default_value_t = 3600)]
        seconds: u64,
    },
}
#[derive(Subcommand)]
enum ModAction {
    Search { query: String },
    Install { project: String },
    Update,
    Diff { prism: PathBuf },
}
fn json<T: serde::Serialize>(v: &T) -> Result<()> {
    println!("{}", serde_json::to_string_pretty(v)?);
    Ok(())
}
fn main() {
    // All program-created state, including Java-written server.properties, is private.
    unsafe {
        libc::umask(0o077);
    }
    if let Err(e) = execute() {
        eprintln!("错误: {e:#}");
        std::process::exit(1);
    }
}
fn execute() -> Result<()> {
    let cli = Cli::parse();
    if let Some(Action::LanValidate { id }) = cli.command.as_ref() {
        return lan::validate_id(id);
    }
    let root = cli.root.unwrap_or(
        PathBuf::from(std::env::var("HOME").context("HOME 未设置")?).join(".local/share/mcsrv"),
    );
    let root = if root.is_absolute() {
        root
    } else {
        std::env::current_dir()?.join(root)
    };
    private_dir(&root)?;
    let Some(action) = cli.command else {
        return tui::run(root, cli.demo);
    };
    match action {
        Action::Frp { action } => frp::action(&root, action),
        Action::Target { action } => remote::targets(&root, &action),
        Action::Cloud { target, action } => remote::cloud(&root, &target, &action),
        Action::LanValidate { id } => lan::validate_id(&id),
        Action::Lan { action } => match action {
            LanAction::List => json(&lan::discover()?),
            LanAction::Share { port, seconds } => {
                let mut worlds = lan::discover()?;
                if let Some(port) = port {
                    worlds.retain(|w| w.port == port);
                }
                if worlds.len() != 1 {
                    bail!(
                        "发现{}个 LAN 世界；请在游戏中对局域网开放，或用 --port 明确选择。",
                        worlds.len()
                    );
                }
                lan::watch(&root, &worlds.remove(0), seconds)
            }
        },
        Action::List => {
            let mut list = Vec::new();
            for e in fs::read_dir(&root)? {
                let e = e?;
                if let Some(n) = e.file_name().to_str() {
                    if valid_name(n).is_ok() && e.path().join("instance.json").is_file() {
                        list.push(load(&root, n)?);
                    }
                }
            }
            list.sort_by(|a, b| a.name.cmp(&b.name));
            json(&list)
        }
        Action::Create {
            name,
            kind,
            version,
            memory,
            port,
            offline,
            whitelist,
            world,
            source,
            java,
            accept_eula,
            rcon,
            bind,
            aikar,
        } => {
            valid_name(&name)?;
            if world.is_some() && !matches!(kind.as_str(), "vanilla" | "paper") {
                bail!("单人世界开服仅支持原版存档 → Vanilla/Paper；模组世界请使用原有本地创建流程手动管理");
            }
            if !accept_eula {
                bail!(
                    "请阅读 https://aka.ms/MinecraftEULA，接受后传 --accept-eula；向导也会明确询问"
                );
            }
            if !(512..=24576).contains(&memory) || port == 0 || port > 55535 {
                bail!("内存须512..24576MiB，端口须1..55535");
            }
            if !bind.is_empty() {
                bind.parse::<std::net::IpAddr>()
                    .context("绑定地址必须是 IP")?;
            }
            if rcon && bind != "127.0.0.1" && bind != "::1" {
                bail!("RCON 仅允许显式 --bind 127.0.0.1 或 ::1；局域网请用私有控制台");
            }
            if aikar && kind != "paper" {
                bail!("Aikar 标志仅支持 Paper，整合包使用官方参数");
            }
            let path = instance(&root, &name)?;
            if path.exists() {
                bail!("实例目录已存在，拒绝覆盖");
            }
            let explicit_java = java.clone();
            let imported_version = world
                .as_ref()
                .map(|path| world::validate_vanilla(path))
                .transpose()?;
            let version = if version == "latest" {
                imported_version.unwrap_or(version)
            } else {
                version
            };
            let (java_kind, java_mc) = install::java_hint(&kind, &version, source.as_deref())?;
            let java = java_path(
                java.as_deref()
                    .unwrap_or(java_version(&java_kind, &java_mc)),
            )?;
            let temp = tempfile::Builder::new()
                .prefix(".install-")
                .tempdir_in(&root)?;
            let argv = install::install(temp.path(), &kind, &version, &java, source.as_deref())?;
            let resolved: serde_json::Value =
                serde_json::from_slice(&fs::read(temp.path().join("installed.json"))?)
                    .context("安装元数据不完整")?;
            let version = resolved["minecraft"]
                .as_str()
                .context("缺少已解析 Minecraft 版本")?
                .to_owned();
            let java = java_path(
                explicit_java
                    .as_deref()
                    .unwrap_or(java_version(&kind, &version)),
            )?;
            if let Some(world) = world {
                world::copy_world(&world, &temp.path().join("world"))?;
            }
            let c = Config {
                name,
                kind,
                version,
                memory_mb: memory,
                port,
                online_mode: !offline,
                whitelist,
                java,
                argv,
                backup_minutes: 30,
                keep_last: 20,
                lan: false,
                aikar,
                rcon,
                bind,
            };
            // Imports cannot overwrite managed settings or smuggle existing EULA acceptance.
            let password = random_secret();
            write_private(&temp.path().join("rcon.secret"), password.as_bytes())?;
            let properties = temp.path().join("server.properties");
            no_symlinks(&properties)?;
            let original = if properties.exists() {
                fs::read_to_string(&properties)?
            } else {
                String::new()
            };
            let managed=format!("server-port={port}\nserver-ip={}\nlevel-name=world\nonline-mode={}\nwhite-list={}\nenforce-whitelist={}\nenable-rcon={}\nrcon.port={}\nrcon.password={password}\nbroadcast-rcon-to-ops=false\nenable-query=false\n",c.bind,c.online_mode,c.whitelist,c.whitelist,c.rcon,port+10000);
            let content=merge_properties(&original,&managed,"motd=Mayon Minecraft\nview-distance=6\nsimulation-distance=4\npause-when-empty-seconds=-1\n");
            write_private(&properties, content.as_bytes())?;
            write_private(&temp.path().join("eula.txt"), b"eula=true\n")?;
            save(temp.path(), &c)?;
            fs::rename(temp.keep(), &path)?;
            println!(
                "已创建 {} · {} · Java {} · {}MiB。模组/整合包是可执行代码，仅安装信任来源。",
                c.name,
                c.kind,
                java_version(&c.kind, &c.version),
                memory
            );
            Ok(())
        }
        Action::Start { name } => runtime::start(&root, &name),
        Action::Stop { name } => runtime::stop(&root, &name),
        Action::Run { name } => runtime::run(&root, &name),
        Action::Status { name } => json(&runtime::status(&root, &name)?),
        Action::Logs { name } => {
            println!("{}", runtime::logs(&instance(&root, &name)?)?);
            Ok(())
        }
        Action::Command { name, command } => {
            println!("{}", runtime::command(&root, &name, &command)?);
            Ok(())
        }
        Action::Rcon { name, command } => {
            println!("{}", runtime::rcon(&root, &name, &command)?);
            Ok(())
        }
        Action::Backup { name } => {
            println!("{}", backup::backup(&root, &name)?);
            Ok(())
        }
        Action::Backups { name } => {
            println!("{}", backup::snapshots(&root, &name)?);
            Ok(())
        }
        Action::Restore {
            name,
            snapshot,
            confirm,
        } => backup::restore(&root, &name, &snapshot, &confirm),
        Action::Config {
            name,
            backup_minutes,
            keep_last,
            lan,
            no_lan,
        } => {
            let dir = instance(&root, &name)?;
            let _lock = lock(&dir, "operation.lock")?;
            let _stopped = lock(&dir, "run.lock")?;
            let mut c = load(&root, &name)?;
            if let Some(m) = backup_minutes {
                c.backup_minutes = m;
            }
            if let Some(n) = keep_last {
                if n == 0 {
                    bail!("至少保留一份快照");
                }
                c.keep_last = n;
            }
            if lan && no_lan {
                bail!("--lan 与 --no-lan 冲突");
            }
            if lan {
                if !(25565..=25575).contains(&c.port) {
                    bail!("临时防火墙仅允许25565..25575");
                }
                c.lan = true;
            }
            if no_lan {
                c.lan = false;
            }
            save(&dir, &c)?;
            println!("配置已保存，下次启动生效");
            Ok(())
        }
        Action::Mods { name, action } => {
            let c = load(&root, &name)?;
            let dir = instance(&root, &name)?;
            let metadata: serde_json::Value =
                serde_json::from_slice(&fs::read(dir.join("installed.json"))?)?;
            let loader = metadata["loader"].as_str().unwrap_or(&c.kind);
            match action {
                ModAction::Search { query } => json(&mods::search(&query)?),
                ModAction::Diff { prism } => json(&mods::diff(&dir, &prism)?),
                ModAction::Install { project } => {
                    let _op = lock(&dir, "operation.lock")?;
                    let _run = lock(&dir, "run.lock")?;
                    json(&mods::install(&dir, &project, &c.version, loader)?)
                }
                ModAction::Update => {
                    let _op = lock(&dir, "operation.lock")?;
                    let _run = lock(&dir, "run.lock")?;
                    json(&mods::update(&dir, &c.version, loader)?)
                }
            }
        }
        Action::Network { name, connect } => {
            let c = load(&root, &name)?;
            println!(
                "局域网/组网地址（客户端连接后加 :{}）：\n{}",
                c.port,
                runtime::addresses()
            );
            println!(
                "临时防火墙: {}；仅开游戏 TCP 端口，不开 RCON。正版={} 白名单={}。",
                c.lan, c.online_mode, c.whitelist
            );
            println!("推荐 Tailscale：双方安装并加入受控 tailnet，访问 100.x 地址；无需端口转发。先在系统配置启用 services.tailscale.enable，再显式连接。凭据归 tailscaled，管家不读取凭据。\nClash：为 127.0.0.0/8、RFC1918、100.64.0.0/10、fd7a:115c:a1e0::/48 设 DIRECT；入站路由需实测。不重写 Verge 配置。");
            if let Ok(output) = Command::new("tailscale")
                .args(["status", "--json"])
                .output()
            {
                if output.status.success() {
                    if let Ok(status) = serde_json::from_slice::<serde_json::Value>(&output.stdout)
                    {
                        let state = match status["BackendState"].as_str() {
                            Some("Running") => "运行中",
                            Some("NeedsLogin") => "需要登录",
                            Some("Stopped") => "已断开",
                            _ => "尚未就绪",
                        };
                        let ips = status["Self"]["TailscaleIPs"]
                            .as_array()
                            .into_iter()
                            .flatten()
                            .filter_map(|v| v.as_str())
                            .filter(|s| s.parse::<std::net::IpAddr>().is_ok())
                            .collect::<Vec<_>>()
                            .join(", ");
                        println!("Tailscale：{state} · {ips}");
                    }
                }
            }
            if connect {
                let result = Command::new("tailscale")
                    .arg("up")
                    .status()
                    .context("请先安装并启用 Tailscale")?;
                if !result.success() {
                    bail!("Tailscale 连接失败");
                }
            }
            Ok(())
        }
    }
}
