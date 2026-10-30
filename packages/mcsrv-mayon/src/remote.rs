//! SSH targets use the user's OpenSSH config and credentials without reading either.
//! Every remote shell word is quoted; secret payloads travel only over SSH stdin.
use crate::model::*;
use anyhow::{bail, Context, Result};
use clap::Subcommand;
use serde::{Deserialize, Serialize};
use std::{
    fs,
    io::Write,
    os::unix::fs::PermissionsExt,
    path::{Component, Path, PathBuf},
    process::{Command, Output, Stdio},
};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Target {
    pub name: String,
    pub host: String,
    #[serde(default)]
    pub port: Option<u16>,
    /// Relative to the remote home directory, never interpolated as shell code.
    pub directory: String,
    pub java: String,
    #[serde(default)]
    pub public_address: Option<String>,
}
#[derive(Subcommand)]
pub enum TargetAction {
    List,
    Add {
        name: String,
        /// SSH config alias or user@hostname; uses existing keys and known_hosts.
        host: String,
        #[arg(long)]
        port: Option<u16>,
        #[arg(long, default_value = ".local/share/mcsrv-cloud")]
        directory: String,
        #[arg(long, default_value = "java")]
        java: String,
        #[arg(long)]
        public_address: Option<String>,
    },
    Remove {
        name: String,
    },
}
#[derive(Subcommand)]
pub enum CloudAction {
    Probe,
    /// Upload a stopped local instance into a new remote directory.
    Deploy {
        name: String,
        #[arg(long)]
        confirm: String,
    },
    /// Create a clean Vanilla/Paper/Fabric server; modpacks are rejected.
    Create {
        name: String,
        #[arg(long, default_value = "vanilla", value_parser = ["vanilla", "paper", "fabric"])]
        kind: String,
        #[arg(long, default_value = "latest")]
        version: String,
        #[arg(long, default_value_t = 4096)]
        memory: u32,
        #[arg(long, default_value_t = 25565)]
        port: u16,
        #[arg(long)]
        accept_eula: bool,
    },
    Start {
        name: String,
    },
    Stop {
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
    /// Flush, archive, and download the world into local cloud-backups/.
    Backup {
        name: String,
    },
    /// Copy a local world to a stopped remote instance, preserving overwritten files.
    UploadWorld {
        name: String,
        source: PathBuf,
        #[arg(long)]
        confirm: String,
    },
    /// Provision a user-owned frps service. Requires frps on the remote PATH.
    #[command(hide = true)]
    DeployFrps {
        #[arg(long)]
        confirm: String,
        #[arg(long, default_value_t = 7000)]
        bind_port: u16,
        #[arg(long, default_value_t = 25565)]
        allow_start: u16,
        #[arg(long, default_value_t = 25575)]
        allow_end: u16,
    },
}

pub fn quote(word: &str) -> String {
    format!("'{}'", word.replace('\'', "'\\''"))
}
fn words(words: &[String]) -> String {
    words.iter().map(|s| quote(s)).collect::<Vec<_>>().join(" ")
}
fn validate_host(host: &str) -> Result<()> {
    if host.is_empty()
        || host.starts_with('-')
        || host.len() > 255
        || !host
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"._-@:[%]".contains(&b))
    {
        bail!("SSH 目标须为已有 config 别名或 user@hostname，不接受选项/空白/命令");
    }
    Ok(())
}
fn validate_target(t: &Target) -> Result<()> {
    valid_name(&t.name)?;
    validate_host(&t.host)?;
    if let Some(address) = &t.public_address {
        validate_host(address)?;
        if address.contains('@') {
            bail!("公网地址不含用户名称");
        }
    }
    if t.port == Some(0) || t.java.is_empty() || t.java.contains(['\0', '\n', '\r']) {
        bail!("SSH 端口或 Java 命令无效");
    }
    if t.directory.is_empty()
        || Path::new(&t.directory).is_absolute()
        || !Path::new(&t.directory)
            .components()
            .all(|c| matches!(c, Component::Normal(_)))
        || t.directory.contains(['\0', '\n', '\r', ':'])
    {
        bail!("远端目录必须是 HOME 内无 .. 的相对路径");
    }
    Ok(())
}
fn target_dir(root: &Path) -> Result<PathBuf> {
    let dir = root.join("targets");
    private_dir(&dir)?;
    Ok(dir)
}
pub fn load_target(root: &Path, name: &str) -> Result<Target> {
    valid_name(name)?;
    let path = target_dir(root)?.join(format!("{name}.json"));
    no_symlinks(&path)?;
    let metadata = fs::metadata(&path)?;
    if metadata.permissions().mode() & 0o777 != 0o600 {
        bail!("SSH 目标配置必须为 0600");
    }
    let t: Target = serde_json::from_slice(&fs::read(path)?)?;
    validate_target(&t)?;
    if t.name != name {
        bail!("SSH 目标名称不一致");
    }
    Ok(t)
}
pub fn targets(root: &Path, action: &TargetAction) -> Result<()> {
    match action {
        TargetAction::List => {
            println!("local  本机服务器");
            for entry in fs::read_dir(target_dir(root)?)? {
                let path = entry?.path();
                if path.extension().and_then(|s| s.to_str()) == Some("json") {
                    if let Some(name) = path.file_stem().and_then(|s| s.to_str()) {
                        let t = load_target(root, name)?;
                        println!(
                            "{}  ssh {} {}  ~/{}",
                            t.name,
                            t.host,
                            t.port
                                .map(|p| format!("port={p}"))
                                .unwrap_or_else(|| "port=SSH-config".into()),
                            t.directory
                        );
                    }
                }
            }
        }
        TargetAction::Add {
            name,
            host,
            port,
            directory,
            java,
            public_address,
        } => {
            if name == "local" {
                bail!("local 是本机保留目标");
            }
            let t = Target {
                name: name.clone(),
                host: host.clone(),
                port: *port,
                directory: directory.clone(),
                java: java.clone(),
                public_address: public_address.clone(),
            };
            validate_target(&t)?;
            let path = target_dir(root)?.join(format!("{name}.json"));
            if path.exists() {
                bail!("目标已存在，请先移除配置（不会移除远端数据）");
            }
            write_private(&path, &serde_json::to_vec_pretty(&t)?)?;
            println!("已保存 SSH 目标；未连接主机。cloud {name} probe 可检查环境。");
        }
        TargetAction::Remove { name } => {
            load_target(root, name)?;
            fs::remove_file(target_dir(root)?.join(format!("{name}.json")))?;
            println!("已移除目标配置，远端实例与世界保留");
        }
    }
    Ok(())
}
fn ssh_command(t: &Target, script: &str) -> Result<Command> {
    validate_target(t)?;
    let mut c = Command::new("ssh");
    c.args(["-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10"]);
    if let Some(port) = t.port {
        c.args(["-p", &port.to_string()]);
    }
    c.arg("--").arg(&t.host);
    c.arg(format!("sh -c {}", quote(script)));
    Ok(c)
}
fn remote(t: &Target, script: &str, stdin: Option<&[u8]>) -> Result<Output> {
    let mut c = ssh_command(t, script)?;
    c.stdin(if stdin.is_some() {
        Stdio::piped()
    } else {
        Stdio::null()
    })
    .stdout(Stdio::piped())
    .stderr(Stdio::piped());
    let mut child = c.spawn().context("无法运行系统 ssh")?;
    if let Some(input) = stdin {
        child
            .stdin
            .take()
            .context("SSH stdin 不可用")?
            .write_all(input)?;
    }
    let out = child.wait_with_output()?;
    if !out.status.success() {
        // Remote application output can contain arbitrary server data. Never echo it in errors.
        bail!(
            "SSH 操作失败（{}）；请检查 SSH 信任、认证、远端依赖及实例状态",
            out.status
        );
    }
    Ok(out)
}
fn show(t: &Target, script: &str) -> Result<()> {
    let out = remote(t, script, None)?;
    print!("{}", String::from_utf8_lossy(&out.stdout));
    Ok(())
}
fn public_host(t: &Target) -> &str {
    t.public_address
        .as_deref()
        .unwrap_or_else(|| t.host.rsplit('@').next().unwrap_or(&t.host))
}
fn address(t: &Target, port: u16) -> String {
    let host = public_host(t);
    if host.contains(':') && !host.starts_with('[') {
        format!("[{host}]:{port}")
    } else {
        format!("{host}:{port}")
    }
}
fn base(t: &Target) -> String {
    format!("\"$HOME\"/{}", quote(&t.directory))
}
fn path(t: &Target, name: &str) -> Result<String> {
    valid_name(name)?;
    Ok(format!("{}/{}", base(t), quote(name)))
}
/// Lock outside the instance directory so publication/renames cannot replace the lock inode.
fn target_lock(t: &Target, name: &str) -> Result<String> {
    valid_name(name)?;
    let locks = format!("{}/.locks", base(t));
    Ok(format!(
        "set -eu\numask 077\nmkdir -p {locks}\nexec 9>{locks}/{}\nflock -x 9\n",
        quote(&format!("{name}.operation.lock"))
    ))
}
fn in_instance(t: &Target, name: &str) -> Result<String> {
    Ok(format!("set -eu\numask 077\ncd {}\n", path(t, name)?))
}
fn locked_instance(t: &Target, name: &str) -> Result<String> {
    Ok(format!(
        "{}{}",
        target_lock(t, name)?,
        in_instance(t, name)?
    ))
}
fn unit(name: &str) -> String {
    format!("mcsrv-cloud-{name}")
}
fn running_script(name: &str) -> String {
    let u = quote(&unit(name));
    let exact = quote(&format!("={}", unit(name)));
    format!("(systemctl --user is-active --quiet {u}.service 2>/dev/null || tmux has-session -t {exact} 2>/dev/null || ! flock -n run.lock -c :)")
}
fn ensure_stopped(name: &str) -> String {
    format!(
        "if {}; then echo '实例运行中，先停止' >&2; exit 1; fi\n",
        running_script(name)
    )
}
/// The runner keeps FIFO open for the lifetime of the server and retains a graceful stop path.
fn runner(java: &str, memory: u32, argv: &[String]) -> String {
    let mut args = vec![
        java.into(),
        format!("-Xms{}M", memory.min(1024)),
        format!("-Xmx{memory}M"),
    ];
    args.extend_from_slice(argv);
    format!("#!/bin/sh\nset -eu\numask 077\ncd -- \"$(dirname -- \"$0\")\"\nexec 8>run.lock\nflock -n 8 || exit 1\nif [ -e console.in ] && [ ! -p console.in ]; then exit 1; fi\n[ -p console.in ] || mkfifo -m 600 console.in\nexec 3<>console.in\nexec {} <console.in >>console.log 2>&1\n", words(&args))
}
fn put(t: &Target, filename: &str, contents: &[u8], executable: bool) -> Result<()> {
    let permission = if executable { "700" } else { "600" };
    remote(
        t,
        &format!("set -eu; umask 077; cat > {filename}; chmod {permission} {filename}"),
        Some(contents),
    )?;
    Ok(())
}
fn start(t: &Target, name: &str, script: &str) -> Result<()> {
    let prefix = locked_instance(t, name)?;
    let u = quote(&unit(name));
    let script = quote(script);
    show(t, &format!("{prefix}{}\nif systemctl --user show-environment >/dev/null 2>&1; then\n systemd-run --user --collect --quiet --unit={u} --property=UMask=0077 --property=TimeoutStopSec=120 --property=KillMode=mixed --working-directory=\"$PWD\" sh \"$PWD\"/{script} 9>&-\n echo '托管：systemd --user；退出 SSH 后运行。重启存活需管理员启用 linger。'\nelse\n command -v tmux >/dev/null || {{ echo '需要 systemd 用户会话或 tmux' >&2; exit 1; }}\n tmux new-session -d -s {u} \"sh ./{}\" 9>&-\n echo '托管：tmux；不设开机自启。'\nfi", ensure_stopped(name), script))
}
fn console(t: &Target, name: &str, text: &str) -> Result<()> {
    if text.is_empty() || text.len() > 4096 || text.contains(['\0', '\n', '\r']) {
        bail!("控制台命令必须是 1–4096 字节单行");
    }
    let mut input = text.as_bytes().to_vec();
    input.push(b'\n');
    remote(
        t,
        &format!(
            "{}{} || exit 1\ntest -p console.in\ntimeout 5 sh -c 'cat > console.in'\n",
            locked_instance(t, name)?,
            running_script(name)
        ),
        Some(&input),
    )?;
    Ok(())
}
fn rsync(t: &Target, source: &str, destination: &str, backups: bool) -> Result<()> {
    let transport = format!(
        "ssh -T -o BatchMode=yes -o ConnectTimeout=10{}",
        t.port.map(|p| format!(" -p {p}")).unwrap_or_default()
    );
    let mut c = Command::new("rsync");
    c.args([
        "-rlt",
        "--safe-links",
        "--protect-args",
        "--chmod=Du=rwx,Dgo=,Fu=rw,Fgo=",
        "--exclude=mods/",
        "--exclude=backups/",
        "--exclude=logs-manager/",
        "--exclude=*.lock",
        "--exclude=*.sock",
        "--exclude=console.in",
        "--exclude=console.log",
        "-e",
        &transport,
    ]);
    if backups {
        c.args([
            "--backup",
            "--backup-dir",
            &format!(
                ".upload-preserved-{}",
                chrono::Utc::now().timestamp_millis()
            ),
        ]);
    }
    c.arg("--")
        .arg(source)
        .arg(format!("{}:{destination}", t.host));
    if !c
        .status()
        .context("需要系统 rsync（远端也需安装）")?
        .success()
    {
        bail!("rsync 上传失败；未删除源文件或远端多余文件");
    }
    Ok(())
}
fn check_tree(dir: &Path) -> Result<()> {
    no_symlinks(dir)?;
    for e in fs::read_dir(dir)? {
        let e = e?;
        let ft = e.file_type()?;
        if ft.is_symlink() || (!ft.is_dir() && !ft.is_file()) {
            bail!("上传源中有符号链接或特殊文件，拒绝上传");
        }
        if ft.is_dir() {
            check_tree(&e.path())?;
        }
    }
    Ok(())
}
fn require_confirmation(value: &str, name: &str) -> Result<()> {
    if value != name {
        bail!("此操作会写入远端，需 --confirm {name}");
    }
    Ok(())
}

fn show_address(t: &Target, name: &str) -> Result<()> {
    if name == "frps" {
        return Ok(());
    }
    let out = remote(
        t,
        &format!(
            "{}sed -n 's/^server-port=//p' server.properties | head -n 1",
            in_instance(t, name)?
        ),
        None,
    )?;
    let port: u16 = String::from_utf8(out.stdout)?
        .trim()
        .parse()
        .context("远端游戏端口无效")?;
    println!(
        "直连 {} · 云安全组和主机防火墙请放行 TCP {port}",
        address(t, port)
    );
    Ok(())
}
fn ensure_clean_instance(dir: &Path, c: &Config) -> Result<()> {
    if !["vanilla", "paper", "fabric"].contains(&c.kind.as_str()) {
        bail!("云端仅部署原版/Paper/Fabric；Prism、GTNH、mrpack和其他整合包请留在本机");
    }
    let metadata: serde_json::Value =
        serde_json::from_slice(&fs::read(dir.join("installed.json"))?)?;
    if !["vanilla", "paper", "fabric"].contains(&metadata["loader"].as_str().unwrap_or(""))
        || metadata.get("pack_version").is_some_and(|v| !v.is_null())
        || dir.join("mmc-pack.json").exists()
        || dir.join("import-report.txt").exists()
        || (dir.join("mods").exists() && fs::read_dir(dir.join("mods"))?.next().is_some())
    {
        bail!("拒绝上传含模组或整合包来源的实例");
    }
    for world in worlds(dir)? {
        crate::world::validate_vanilla(&dir.join(world))?;
    }
    Ok(())
}

fn game_name(name: &str) -> Result<()> {
    valid_name(name)?;
    if name == "frps" {
        bail!("frps 为隧道服务保留名称，请为 Minecraft 选择其他名字");
    }
    Ok(())
}

fn check_java(t: &Target, required: &str) -> Result<()> {
    let code = r#"import subprocess,re,sys; p=subprocess.run([sys.argv[1],'-version'],capture_output=True,text=True,check=True); m=re.search(r'version "(?:1\.)?(\d+)',p.stderr+p.stdout); assert m and int(m.group(1))>=int(sys.argv[2]), 'Java major version too old'"#;
    remote(
        t,
        &format!(
            "python3 -c {} {} {}",
            quote(code),
            quote(&t.java),
            quote(required)
        ),
        None,
    )
    .context("远端 Java 版本不满足该 Minecraft/loader，请 target add 指定匹配的 --java 路径")?;
    Ok(())
}

pub fn cloud(root: &Path, target: &str, action: &CloudAction) -> Result<()> {
    let t = load_target(root, target)?;
    match action {
        CloudAction::Probe => show(&t, &format!("set -eu\nprintf 'Java: '; {} -version 2>&1 | head -n 1\nfor tool in rsync python3 tar timeout flock; do command -v \"$tool\" || true; done\nif systemctl --user show-environment >/dev/null 2>&1; then echo 'systemd --user 可用'; loginctl show-user \"$(id -un)\" -p Linger 2>/dev/null || true; else command -v tmux || true; fi\necho '云厂商安全组及主机防火墙需自行放行游戏 TCP 端口；RCON 不应公网开放。'", quote(&t.java))),
        CloudAction::Deploy { name, confirm } => {
            require_confirmation(confirm, name)?;
            game_name(name)?;
            let dir = instance(root, name)?;
            let _op = lock(&dir, "operation.lock")?;
            let _run = lock(&dir, "run.lock")?;
            let c = load(root, name)?;
            ensure_clean_instance(&dir, &c)?;
            check_java(&t, java_version(&c.kind,&c.version))?;
            // Ignore program-created transient special files; inspect the transferred subset below.
            for e in fs::read_dir(&dir)? {
                let e = e?;
                if e.file_name() == "console.in" || e.file_name().to_string_lossy().ends_with(".sock") { continue; }
                if e.file_type()?.is_dir() { check_tree(&e.path())?; }
                else if e.file_type()?.is_symlink() { bail!("上传实例含符号链接"); }
            }
            let dest = path(&t, name)?;
            let staging = format!(".upload-{}", &random_secret()[..16]);
            let stage_expr = format!("{}/{}", base(&t), quote(&staging));
            remote(&t, &format!("set -eu; umask 077; {} -version >/dev/null 2>&1; mkdir -p {}; test ! -e {dest}; mkdir {stage_expr}", quote(&t.java), base(&t)), None)?;
            let source = format!("{}/", dir.canonicalize()?.display());
            rsync(&t, &source, &format!("{}/{staging}/", t.directory), false)?;
            put(&t, &format!("{stage_expr}/run-cloud.sh"), runner(&t.java, c.memory_mb, &c.argv).as_bytes(), true)?;
            remote(&t, &format!("{}test ! -e {dest}; mv {stage_expr} {dest}",target_lock(&t,name)?), None)?;
            println!("已部署 {name} · 直连 {}；Java 已检查。请放行云安全组/主机防火墙 TCP {}，再 cloud {target} start {name}。", address(&t,c.port), c.port);
            Ok(())
        }
        CloudAction::Create { name, kind, version, memory, port, accept_eula } => {
            game_name(name)?;
            if !accept_eula { bail!("接受 https://aka.ms/MinecraftEULA 后传 --accept-eula"); }
            if !(512..=24576).contains(memory) || *port == 0 { bail!("内存/端口无效"); }
            if !["vanilla", "paper", "fabric"].contains(&kind.as_str()) { bail!("云端仅支持 Vanilla/Paper/Fabric，整合包请留在本机"); }
            if kind != "vanilla" {
                let temp = tempfile::Builder::new().prefix(".cloud-create-").tempdir_in(root)?;
                private_dir(&temp.path().join("targets"))?;
                write_private(&temp.path().join("targets").join(format!("{target}.json")), &serde_json::to_vec(&t)?)?;
                let executable = std::env::var_os("MCSRV_SELF").map(PathBuf::from).unwrap_or(std::env::current_exe()?);
                let status = Command::new(executable).arg("--root").arg(temp.path()).args(["create",name,"--kind",kind,"--version",version,"--memory",&memory.to_string(),"--port",&port.to_string(),"--whitelist","--accept-eula"]).status()?;
                if !status.success() { bail!("本地准备服务端失败，未上传远端"); }
                return cloud(temp.path(),target,&CloudAction::Deploy { name:name.clone(),confirm:name.clone() });
            }
            let dest = path(&t,name)?;
            let staging = format!(".create-{}", &random_secret()[..16]);
            let stage_expr = format!("{}/{}",base(&t),quote(&staging));
            let script = format!("set -eu; umask 077; {} -version >/dev/null 2>&1; mkdir -p {}; test ! -e {dest}; python3 - {} {} {} {} {}", quote(&t.java), base(&t), quote(version), quote(&port.to_string()), quote(&t.directory), quote(&staging), quote(&t.java));
            remote(&t, &script, Some(VANILLA_DOWNLOAD.as_bytes()))?;
            put(&t, &format!("{stage_expr}/run-cloud.sh"), runner(&t.java, *memory, &["-jar".into(), "server.jar".into(), "nogui".into()]).as_bytes(), true)?;
            remote(&t,&format!("{}test ! -e {dest}; mv {stage_expr} {dest}",target_lock(&t,name)?),None)?;
            println!("已在远端下载 Vanilla {version} · {memory}MiB · 直连 {} · 正版验证/白名单默认开启。启动后 console whitelist add 玩家；云安全组/主机防火墙放行 TCP {port}。", address(&t,*port));
            Ok(())
        }
        CloudAction::Start { name } => {
            remote(&t, &format!("{}{} -version >/dev/null 2>&1", in_instance(&t, name)?, quote(&t.java)), None)?;
            start(&t, name, "run-cloud.sh")?;
            show_address(&t,name)
        }
        CloudAction::Stop { name } => {
            if name == "frps" {
                return show(&t, &format!("{}if systemctl --user is-active --quiet mcsrv-cloud-frps.service 2>/dev/null; then systemctl --user stop mcsrv-cloud-frps.service; else tmux kill-session -t =mcsrv-cloud-frps; fi", locked_instance(&t, name)?));
            }
            show(&t, &format!("{}{} || exit 1\ntest -p console.in\nprintf 'stop\\n' | timeout 5 sh -c 'cat > console.in'\nfor attempt in $(seq 1 120); do if ! {}; then echo '已停止'; exit 0; fi; sleep 1; done\necho '120 秒仍未停止，请检查日志（未强杀世界）' >&2; exit 1", locked_instance(&t, name)?, running_script(name), running_script(name)))
        }
        CloudAction::Status { name } => { show(&t, &format!("{}if {}; then echo '运行中'; else echo '已停止'; fi", in_instance(&t,name)?,running_script(name)))?; show_address(&t,name) },
        CloudAction::Logs { name } => show(&t, &format!("{}test ! -f console.log || tail -c 24000 console.log | tail -n 120", in_instance(&t, name)?)),
        CloudAction::Command { name, command } => { console(&t, name, command)?; println!("命令已发送；cloud {target} logs {name} 查看响应"); Ok(()) },
        CloudAction::Backup { name } => download_backup(root, &t, name),
        CloudAction::UploadWorld { name, source, confirm } => {
            require_confirmation(confirm, name)?;
            game_name(name)?;
            // Snapshot checks session.lock and before/after metadata without ever writing source.
            let temp = tempfile::Builder::new().prefix(".cloud-world-").tempdir_in(root)?;
            let snapshot = temp.path().join("world");
            crate::world::copy_world(source,&snapshot)?;
            let staging = format!(".world-upload-{}", &random_secret()[..16]);
            remote(&t,&format!("{}mkdir {}",in_instance(&t,name)?,quote(&staging)),None)?;
            rsync(&t, &format!("{}/", snapshot.display()), &format!("{}/{name}/{staging}/",t.directory),false)?;
            let preserved = format!("world-preserved-{}", &random_secret()[..16]);
            let commit = world_commit_script(name,&staging,&preserved)?;
            remote(&t,&format!("{}{commit}",locked_instance(&t,name)?),None)?;
            println!("世界已整体替换；旧世界和旧维度保存在远端 {preserved}/，源存档未改动");
            Ok(())
        }
        CloudAction::DeployFrps { confirm, bind_port, allow_start, allow_end } => {
            require_confirmation(confirm, target)?;
            if *bind_port == 0 || *allow_start == 0 || allow_end < allow_start || allow_end - allow_start > 100 || (*allow_start..=*allow_end).contains(bind_port) { bail!("frps 控制端口/映射范围无效（最多101个游戏端口，不能包含控制端口）"); }
            let secrets = root.join("frps-secrets"); private_dir(&secrets)?;
            let token_path = secrets.join(format!("{target}.token"));
            if token_path.exists() { bail!("已有 frps token，拒绝覆盖；请保留该文件并手工管理现有部署"); }
            let token = random_secret();
            let dir = path(&t, "frps")?;
            remote(&t, &format!("set -eu; umask 077; command -v frps >/dev/null; mkdir -p {}; test ! -e {dir}; mkdir {dir}", base(&t)), None)?;
            write_private(&token_path, token.as_bytes())?;
            let config = format!("bindPort = {bind_port}\nauth.method = \"token\"\nauth.token = {}\ntransport.tls.force = true\nlog.to = \"/dev/null\"\nallowPorts = [{{ start = {allow_start}, end = {allow_end} }}]\n", serde_json::to_string(&token)?);
            put(&t, &format!("{dir}/frps.toml"), config.as_bytes(), false)?;
            put(&t, &format!("{dir}/run-cloud.sh"), b"#!/bin/sh\nset -eu\numask 077\ncd -- \"$(dirname -- \"$0\")\"\nexec 8>run.lock\nflock -n 8 || exit 1\nexec frps -c frps.toml >/dev/null 2>&1\n", true)?;
            start(&t, "frps", "run-cloud.sh")?;
            println!("frps 已部署；token 仅存 {} (0600)，请把该文件用于 tunnel 配置。云安全组需放行 TCP {bind_port} 与 {allow_start}–{allow_end}；控制连接也需 Clash DIRECT。", token_path.display());
            Ok(())
        }
    }
}
/// Under the caller's operation lock, replace all old dimensions without merging regions.
/// Every moved old directory is retained, and an interrupted/failed commit restores it.
fn world_commit_script(name: &str, staging: &str, preserved: &str) -> Result<String> {
    valid_name(name)?;
    if !staging.starts_with(".world-upload-")
        || !staging
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b".-".contains(&b))
    {
        bail!("非法上传暂存目录");
    }
    valid_name(preserved)?;
    let stage = quote(staging);
    let keep = quote(preserved);
    Ok(format!("{}{LEVEL_NAME}stage={stage}\nkeep={keep}\ntest -d \"$stage\" && test ! -L \"$stage\"\ntest -f \"$stage/level.dat\"\ntest ! -e \"$keep\"\nmkdir \"$keep\"\ncommitted=0\nrollback() {{ status=$?; trap - EXIT HUP INT TERM; if [ \"$committed\" -eq 0 ]; then if [ ! -e \"$stage\" ] && [ -d \"$level\" ]; then mv -- \"$level\" \"$stage\" || true; fi; for old in \"$keep\"/*; do [ -e \"$old\" ] || continue; basename=${{old##*/}}; if [ ! -e \"$basename\" ]; then mv -- \"$old\" \"$basename\" || true; fi; done; fi; exit \"$status\"; }}\ntrap rollback EXIT\ntrap 'exit 130' HUP INT TERM\nfor world in \"$level\" \"${{level}}_nether\" \"${{level}}_the_end\"; do if [ -e \"$world\" ]; then test -d \"$world\" && test ! -L \"$world\"; mv -- \"$world\" \"$keep/$world\"; fi; done\nmv -- \"$stage\" \"$level\"\ncommitted=1\n", ensure_stopped(name)))
}

const LEVEL_NAME: &str = "level=$(sed -n 's/^level-name=//p' server.properties | head -n 1); level=${level:-world}\ncase \"$level\" in ''|*[!a-zA-Z0-9_-]*) echo '世界名不安全' >&2; exit 1;; esac\nprintf '%s\\n' \"$level\"\n";
fn download_backup(root: &Path, t: &Target, name: &str) -> Result<()> {
    let prefix = locked_instance(t, name)?;
    // Stop the server first. This gives a definite consistency boundary on every loader,
    // including legacy GTNH; no optimistic sleeps after save-all are used as evidence.
    let stopped = ensure_stopped(name);
    let script = format!("{prefix}{stopped}{LEVEL_NAME}set --\nfor world in \"$level\" \"${{level}}_nether\" \"${{level}}_the_end\"; do if [ -d \"$world\" ] && [ ! -L \"$world\" ]; then set -- \"$@\" \"$world\"; fi; done\n[ \"$#\" -gt 0 ]\nexec tar -czf - -- \"$@\"\n");
    // LEVEL_NAME emits a line for UploadWorld; suppress it in the binary stream.
    let script = script.replace("printf '%s\\n' \"$level\"", ":");
    let dir = root.join("cloud-backups").join(&t.name);
    private_dir(&dir)?;
    let destination = dir.join(format!(
        "{name}-{}.tar.gz",
        chrono::Utc::now().format("%Y%m%d-%H%M%S-%f")
    ));
    let mut file = tempfile::NamedTempFile::new_in(&dir)?;
    file.as_file()
        .set_permissions(fs::Permissions::from_mode(0o600))?;
    let mut c = ssh_command(t, &script)?;
    c.stdin(Stdio::null())
        .stdout(Stdio::from(file.as_file().try_clone()?))
        .stderr(Stdio::null());
    if !c.status()?.success() {
        bail!("远端世界备份下载失败（临时归档未发布）");
    }
    file.as_file_mut().flush()?;
    file.persist(&destination)?;
    println!(
        "已下载一致世界备份：{}（远端服务器需先停止）",
        destination.display()
    );
    Ok(())
}

const VANILLA_DOWNLOAD: &str = r#"import sys,os,json,urllib.request,hashlib,tempfile,pathlib,subprocess,re
version,port,base,name,java=sys.argv[1:]
def get(url):
    if not url.startswith('https://'): raise ValueError('HTTPS required')
    req=urllib.request.Request(url,headers={'User-Agent':'mcsrv-mayon/0.1'})
    with urllib.request.urlopen(req,timeout=90) as r: return r.read(1024*1024*1024)
manifest=json.loads(get('https://piston-meta.mojang.com/mc/game/version_manifest_v2.json'))
if version=='latest': version=manifest['latest']['release']
entry=next(x for x in manifest['versions'] if x['id']==version)
data=get(entry['url'])
if hashlib.sha1(data).hexdigest()!=entry['sha1']: raise ValueError('metadata checksum')
metadata=json.loads(data)
required=metadata.get('javaVersion',{}).get('majorVersion',8)
actual=subprocess.run([java,'-version'],capture_output=True,text=True,check=True)
match=re.search(r'version \"(?:1\.)?(\d+)',actual.stderr+actual.stdout)
if not match or int(match.group(1))<required: raise ValueError('Java version too old; required '+str(required))
server=metadata['downloads']['server']
jar=get(server['url'])
if len(jar)!=server['size'] or hashlib.sha1(jar).hexdigest()!=server['sha1']: raise ValueError('server checksum')
base=pathlib.Path.home()/base
with tempfile.TemporaryDirectory(prefix='.download-',dir=base) as stage:
    stage=pathlib.Path(stage)
    (stage/'server.jar').write_bytes(jar)
    (stage/'server.properties').write_text('server-port='+port+'\nlevel-name=world\nonline-mode=true\nwhite-list=true\nenforce-whitelist=true\nenable-rcon=false\n')
    (stage/'eula.txt').write_text('eula=true\n')
    (stage/'installed.json').write_text(json.dumps({'minecraft':version,'loader':'vanilla'}))
    os.rename(stage,base/name)
print('Vanilla '+version+' SHA-1 verified')
"#;

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn shell_quote_preserves_hostile_words_as_single_arguments() {
        let hostile = "a ' $(touch /tmp/NO) `id`;\n spaces";
        let output = Command::new("sh")
            .arg("-c")
            .arg(format!("printf '%s' {}", quote(hostile)))
            .output()
            .unwrap();
        assert!(output.status.success());
        assert_eq!(output.stdout, hostile.as_bytes());
    }
    #[test]
    fn ssh_arguments_cannot_become_options_or_shell_fragments() {
        for bad in [
            "-oProxyCommand=id",
            "host;id",
            "host $(id)",
            "x\ny",
            "",
            "user@host:22/path",
        ] {
            assert!(validate_host(bad).is_err(), "{bad}");
        }
        for good in ["cloud", "user@example.org", "127.0.0.1", "user@[::1]"] {
            assert!(validate_host(good).is_ok());
        }
    }
    #[test]
    fn targets_are_private_without_network_calls() {
        let d = tempfile::tempdir().unwrap();
        targets(
            d.path(),
            &TargetAction::Add {
                name: "test".into(),
                host: "127.0.0.1".into(),
                port: Some(2222),
                directory: ".local/share/test".into(),
                java: "java".into(),
                public_address: None,
            },
        )
        .unwrap();
        let file = d.path().join("targets/test.json");
        assert_eq!(
            fs::metadata(file).unwrap().permissions().mode() & 0o777,
            0o600
        );
        assert_eq!(load_target(d.path(), "test").unwrap().port, Some(2222));
    }
    #[test]
    fn remote_paths_and_java_are_quoted() {
        let t = Target {
            name: "test".into(),
            host: "127.0.0.1".into(),
            port: Some(2222),
            directory: "space/'dir".into(),
            java: "java ' odd".into(),
            public_address: None,
        };
        validate_target(&t).unwrap();
        let script = runner(&t.java, 2048, &["-jar".into(), "$(touch NO).jar".into()]);
        let output = Command::new("sh")
            .arg("-n")
            .arg("-c")
            .arg(script)
            .output()
            .unwrap();
        assert!(output.status.success());
        assert!(path(&t, "../no").is_err());
    }
    #[test]
    fn world_upload_rejects_symlinks() {
        let d = tempfile::tempdir().unwrap();
        std::os::unix::fs::symlink("/tmp", d.path().join("escape")).unwrap();
        assert!(check_tree(d.path()).is_err());
    }
    #[test]
    fn confirmation_is_specific_to_target_or_instance() {
        assert!(require_confirmation("wrong", "cloud").is_err());
        assert!(require_confirmation("cloud", "cloud").is_ok());
    }
    fn upload_fixture() -> tempfile::TempDir {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("server.properties"), "level-name=world\n").unwrap();
        for world in ["world", "world_nether", "world_the_end"] {
            fs::create_dir(dir.path().join(world)).unwrap();
            fs::write(dir.path().join(world).join("old-region"), b"old").unwrap();
        }
        fs::create_dir(dir.path().join(".world-upload-test")).unwrap();
        fs::write(dir.path().join(".world-upload-test/level.dat"), b"new").unwrap();
        dir
    }
    fn commit_fixture(dir: &Path, before: &str) -> std::process::ExitStatus {
        let script = world_commit_script("demo", ".world-upload-test", "world-preserved-test")
            .unwrap()
            .replace(&ensure_stopped("demo"), "");
        Command::new("sh")
            .arg("-c")
            .arg(format!("set -eu\n{before}\n{script}"))
            .current_dir(dir)
            .status()
            .unwrap()
    }
    #[test]
    fn world_commit_replaces_whole_directory_and_preserves_old_dimensions() {
        let dir = upload_fixture();
        assert!(commit_fixture(dir.path(), "").success());
        assert_eq!(
            fs::read(dir.path().join("world/level.dat")).unwrap(),
            b"new"
        );
        assert!(!dir.path().join("world/old-region").exists());
        assert!(!dir.path().join("world_nether").exists());
        for world in ["world", "world_nether", "world_the_end"] {
            assert!(dir
                .path()
                .join("world-preserved-test")
                .join(world)
                .join("old-region")
                .is_file());
        }
    }
    #[test]
    fn failed_final_rename_rolls_back_all_old_worlds() {
        let dir = upload_fixture();
        assert!(!commit_fixture(
            dir.path(),
            "mv() { if [ \"$2\" = .world-upload-test ]; then return 1; fi; command mv \"$@\"; }"
        )
        .success());
        for world in ["world", "world_nether", "world_the_end"] {
            assert!(dir.path().join(world).join("old-region").is_file());
        }
        assert!(dir.path().join(".world-upload-test/level.dat").is_file());
    }
    #[test]
    fn interrupted_commit_after_rename_restores_old_worlds() {
        let dir = upload_fixture();
        assert!(!commit_fixture(dir.path(),"mv() { command mv \"$@\"; if [ \"$2\" = .world-upload-test ]; then kill -TERM $$; fi; }").success());
        for world in ["world", "world_nether", "world_the_end"] {
            assert!(dir.path().join(world).join("old-region").is_file());
        }
        assert!(dir.path().join(".world-upload-test/level.dat").is_file());
    }
    #[test]
    fn ssh_without_explicit_port_respects_existing_config() {
        let t = Target {
            name: "demo".into(),
            host: "cloud".into(),
            port: None,
            directory: ".cloud".into(),
            java: "java".into(),
            public_address: None,
        };
        let command = ssh_command(&t, "true").unwrap();
        assert!(!command.get_args().any(|s| s == "-p"));
        let legacy: Target = serde_json::from_str(
            r#"{"name":"demo","host":"cloud","port":2222,"directory":".cloud","java":"java"}"#,
        )
        .unwrap();
        assert_eq!(legacy.port, Some(2222));
    }
}
