//! User-owned subscriptions and config transactions. Never include upstream errors or bodies in diagnostics.
use crate::{
    api::Client,
    profiles::{ProfileItem, ProfileStore, Usage},
};
use base64::Engine as _;
use serde::{Deserialize, Serialize};
use serde_yaml::Value;
use std::{
    fs::{self, File, OpenOptions},
    io::Write,
    os::{
        fd::AsRawFd,
        unix::fs::{OpenOptionsExt, PermissionsExt},
    },
    path::{Path, PathBuf},
    process::Stdio,
    time::Duration,
};
type Result<T> = std::result::Result<T, String>;
const MAX_BODY: usize = 32 * 1024 * 1024;
pub const SERVICE: &str = "mayon-clash.service";
#[derive(Clone)]
pub struct Native {
    pub data: PathBuf,
    pub socket: PathBuf,
    pub mihomo: PathBuf,
    pub systemctl: PathBuf,
}
#[derive(Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Settings {
    pub tun: bool,
    pub mode: String,
    pub ipv6: bool,
    pub allow_lan: bool,
    pub log_level: String,
    pub mixed_port: u16,
    /// Saved base settings; built-in defaults fill this field when it is absent.
    pub baseline: String,
}
impl Default for Settings {
    fn default() -> Self {
        Self {
            tun: true,
            mode: "rule".into(),
            ipv6: true,
            allow_lan: false,
            log_level: "info".into(),
            mixed_port: 7897,
            baseline: "tun: {stack: mixed, auto-route: true, auto-detect-interface: true, strict-route: false, dns-hijack: ['any:53']}\ndns: {enable: true, listen: ':53', enhanced-mode: fake-ip, fake-ip-range: 198.18.0.1/16, nameserver: [223.5.5.5, 8.8.8.8]}\nsniffer: {enable: false}\nprofile: {}".into(),
        }
    }
}
impl Settings {
    pub fn set(&mut self, key: &str, value: &str) -> Result<()> {
        let boolean = || {
            value
                .parse::<bool>()
                .map_err(|_| "请输入 true 或 false".to_string())
        };
        match key {
            "tun" => self.tun = boolean()?,
            "ipv6" => self.ipv6 = boolean()?,
            "allow-lan" => self.allow_lan = boolean()?,
            "mode" if matches!(value, "rule" | "global" | "direct") => self.mode = value.into(),
            "log-level" if matches!(value, "silent" | "error" | "warning" | "info" | "debug") => {
                self.log_level = value.into()
            }
            "mixed-port" => {
                self.mixed_port = value
                    .parse::<u16>()
                    .ok()
                    .filter(|v| *v > 0)
                    .ok_or("端口范围 1–65535")?
            }
            _ => return Err("设置名称或取值无效".into()),
        }
        Ok(())
    }
}
#[derive(Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Store {
    pub current: Option<String>,
    pub items: Vec<Subscription>,
}
#[derive(Clone, Serialize, Deserialize)]
pub struct Subscription {
    pub id: String,
    pub name: String,
    // Sensitive: never Debug or serialize to stdout.
    pub url: String,
    pub updated: i64,
    pub interval_hours: u64,
    pub usage: Option<Usage>,
    pub nodes: usize,
    // Keep this retired key round-trippable so existing subscriptions.toml files
    // are not rewritten into a different on-disk schema during ordinary edits.
    #[serde(default, rename = "verge_current")]
    pub legacy_current_marker: bool,
}
impl Store {
    pub fn view(&self) -> ProfileStore {
        ProfileStore {
            current: self.current.clone(),
            items: self
                .items
                .iter()
                .map(|s| ProfileItem {
                    uid: Some(s.id.clone()),
                    name: Some(s.name.clone()),
                    url: Some(s.url.clone()),
                    updated: Some(s.updated),
                    extra: s.usage,
                })
                .collect(),
        }
    }
    pub fn due(&self) -> Vec<String> {
        let now = chrono::Utc::now().timestamp();
        self.items
            .iter()
            .filter(|s| {
                now.saturating_sub(s.updated) >= s.interval_hours.clamp(1, 8760) as i64 * 3600
            })
            .map(|s| s.id.clone())
            .collect()
    }
}
pub fn redact_url(raw: &str) -> String {
    reqwest::Url::parse(raw)
        .ok()
        .filter(|u| matches!(u.scheme(), "http" | "https"))
        .and_then(|u| u.host_str().map(|h| format!("{}://{h}/…", u.scheme())))
        .unwrap_or_else(|| {
            if raw.is_empty() {
                "等待粘贴".into()
            } else {
                "地址内容隐藏".into()
            }
        })
}
fn url(raw: &str) -> Result<reqwest::Url> {
    reqwest::Url::parse(raw)
        .ok()
        .filter(|u| matches!(u.scheme(), "http" | "https") && u.host_str().is_some())
        .ok_or_else(|| "订阅 URL 无效（内容隐藏）".into())
}
fn read_toml<T: for<'de> Deserialize<'de> + Default>(path: &Path) -> Result<T> {
    match fs::read_to_string(path) {
        Ok(s) => toml::from_str(&s).map_err(|_| "本地数据格式无效（内容隐藏）".into()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(T::default()),
        Err(_) => Err("无法读取本地数据".into()),
    }
}
fn private_dir(path: &Path) -> Result<()> {
    fs::create_dir_all(path)
        .and_then(|_| fs::set_permissions(path, fs::Permissions::from_mode(0o700)))
        .map_err(|_| "无法创建私有数据目录".into())
}
struct Temp(PathBuf);
impl Drop for Temp {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.0);
    }
}
fn stage(path: &Path, bytes: &[u8]) -> Result<Temp> {
    let name = path.with_extension(format!(
        "tmp-{}-{}",
        std::process::id(),
        chrono::Utc::now().timestamp_nanos_opt().unwrap_or_default()
    ));
    let temp = Temp(name);
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&temp.0)
        .map_err(|_| "无法创建临时文件")?;
    file.write_all(bytes)
        .and_then(|_| file.sync_all())
        .map_err(|_| "无法写入临时文件")?;
    Ok(temp)
}
fn replace(path: &Path, bytes: &[u8]) -> Result<()> {
    let temp = stage(path, bytes)?;
    fs::rename(&temp.0, path).map_err(|_| "原子替换失败")?;
    if let Some(parent) = path.parent() {
        File::open(parent)
            .and_then(|f| f.sync_all())
            .map_err(|_| "目录同步失败")?;
    }
    Ok(())
}
fn encoded<T: Serialize>(value: &T) -> Result<Vec<u8>> {
    toml::to_string(value)
        .map(String::into_bytes)
        .map_err(|_| "数据编码失败".into())
}
// flock serializes the TUI, CLI and automatic updates. Closing File releases the lock, including on cancellation.
struct Lock(File);
impl Drop for Lock {
    fn drop(&mut self) {
        unsafe {
            libc::flock(self.0.as_raw_fd(), libc::LOCK_UN);
        }
    }
}
impl Native {
    fn lock(&self) -> Result<Lock> {
        private_dir(&self.data)?;
        private_dir(&self.data.join("subscriptions"))?;
        let f = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .mode(0o600)
            .open(self.data.join("writer.lock"))
            .map_err(|_| "无法打开写入锁")?;
        if unsafe { libc::flock(f.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
            return Err("另一个订阅或设置操作正在进行".into());
        }
        Ok(Lock(f))
    }
    pub fn store(&self) -> Result<Store> {
        let s: Store = read_toml(&self.data.join("subscriptions.toml"))?;
        if s.items.iter().any(|s| !valid_id(&s.id)) {
            return Err("订阅索引含无效 ID".into());
        }
        Ok(s)
    }
    pub fn settings(&self) -> Result<Settings> {
        read_toml(&self.data.join("settings.toml"))
    }
    async fn initial_settings(&self) -> Result<Settings> {
        if self.data.join("settings.toml").exists() {
            return self.settings();
        }
        Ok(Settings::default())
    }
    pub async fn validate(&self, bytes: &[u8]) -> Result<()> {
        self.seed_geo()?;
        let candidate = stage(&self.data.join("validation.yaml"), bytes)?;
        let mut cmd = tokio::process::Command::new(&self.mihomo);
        cmd.args(["-t", "-d"])
            .arg(&self.data)
            .arg("-f")
            .arg(&candidate.0)
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .kill_on_drop(true);
        // Config tests must never fetch subscription/provider/Geo data. Restrict
        // only the validator child; the downloader and running core keep normal networking.
        unsafe {
            cmd.pre_exec(validation_network_filter);
        }
        let ok = tokio::time::timeout(Duration::from_secs(45), cmd.status())
            .await
            .ok()
            .and_then(std::result::Result::ok)
            .is_some_and(|s| s.success());
        if ok {
            Ok(())
        } else {
            Err("mihomo 配置校验失败或超时；保留原配置（详细内容隐藏）".into())
        }
    }
    fn seed_geo(&self) -> Result<()> {
        for (variable, name) in [
            ("MAYON_CLASH_GEOIP", "GeoIP.dat"),
            ("MAYON_CLASH_GEOSITE", "GeoSite.dat"),
            ("MAYON_CLASH_MMDB", "Country.mmdb"),
        ] {
            let path = self.data.join(name);
            if !path.exists() {
                if let Some(source) = std::env::var_os(variable) {
                    let data = fs::read(source).map_err(|_| "无法读取初始 Geo 数据")?;
                    replace(&path, &data)?;
                }
            }
        }
        Ok(())
    }
    async fn commit(
        &self,
        store: &Store,
        settings: &Settings,
        changed: Option<(&str, &[u8])>,
        running: bool,
    ) -> Result<()> {
        let config = if let Some(id) = &store.current {
            let bytes = match changed {
                Some((which, bytes)) if which == id => bytes.to_vec(),
                _ => fs::read(self.profile_path(id)?).map_err(|_| "当前订阅缓存不可读")?,
            };
            Some(merge(&bytes, settings, &self.socket)?)
        } else {
            None
        };
        if let Some(bytes) = &config {
            self.validate(bytes).await?;
        }
        let mut writes = vec![
            (self.data.join("subscriptions.toml"), encoded(store)?),
            (self.data.join("settings.toml"), encoded(settings)?),
        ];
        if let Some((id, bytes)) = changed {
            writes.push((self.profile_path(id)?, bytes.to_vec()));
        }
        if let Some(bytes) = &config {
            writes.push((self.data.join("config.yaml"), bytes.clone()));
        }
        let previous_settings = self.settings()?;
        let old: Vec<_> = writes
            .iter()
            .map(|(path, _)| (path.clone(), fs::read(path).ok()))
            .collect();
        let result: Result<()> = async {
            if let Some(previous) = fs::read(self.data.join("config.yaml"))
                .ok()
                .filter(|_| config.is_some())
            {
                replace(&self.data.join("config.previous.yaml"), &previous)?;
            }
            for (path, bytes) in &writes {
                replace(path, bytes)?;
            }
            if running && config.is_some() {
                self.reload_checked(settings).await?;
            }
            Ok(())
        }
        .await;
        if let Err(e) = result {
            let mut restored = true;
            for (path, bytes) in old {
                match bytes {
                    Some(bytes) => restored &= replace(&path, &bytes).is_ok(),
                    None => {
                        if path.exists() {
                            restored &= fs::remove_file(path).is_ok();
                        }
                    }
                }
            }
            if running {
                restored &= self.reload_checked(&previous_settings).await.is_ok();
            }
            return Err(if restored {
                format!("{e}；已回滚文件和运行配置")
            } else {
                format!("{e}；回滚未完成，请 X 关闭服务后检查数据目录")
            });
        }
        Ok(())
    }
    async fn reload_checked(&self, settings: &Settings) -> Result<()> {
        let client = Client::new(self.socket.clone()).map_err(|_| "无法创建控制接口")?;
        client.reload().await.map_err(|_| "内核热加载失败")?;
        let actual = client
            .configs()
            .await
            .map_err(|_| "热加载后无法确认运行状态")?;
        // ApplyConfig can return HTTP 204 even if a listener failed to bind.
        if actual.mode != settings.mode
            || actual.tun.enable != settings.tun
            || actual.mixed_port != Some(settings.mixed_port)
        {
            return Err("热加载后 TUN/监听端口/模式与设置不符".into());
        }
        Ok(())
    }
    fn profile_path(&self, id: &str) -> Result<PathBuf> {
        if !valid_id(id) {
            return Err("订阅 ID 无效".into());
        }
        Ok(self.data.join("subscriptions").join(format!("{id}.yaml")))
    }
    pub async fn add(&self, raw: &str, name: &str, running: bool) -> Result<()> {
        let _lock = self.lock()?;
        let settings = self.initial_settings().await?;
        let mut store = self.store()?;
        let downloaded = download(raw, running.then_some(settings.mixed_port)).await?;
        let bytes = merge(&downloaded.bytes, &settings, &self.socket)?;
        self.validate(&bytes).await?;
        let id = format!(
            "s{}",
            chrono::Utc::now().timestamp_nanos_opt().unwrap_or_default()
        );
        store.items.push(Subscription {
            id: id.clone(),
            name: if name.trim().is_empty() {
                downloaded.name
            } else {
                safe_name(name)
            },
            url: url(raw)?.to_string(),
            updated: chrono::Utc::now().timestamp(),
            interval_hours: downloaded.interval,
            usage: downloaded.usage,
            nodes: node_count(&downloaded.bytes),
            legacy_current_marker: false,
        });
        if store.current.is_none() {
            store.current = Some(id.clone());
        }
        self.commit(&store, &settings, Some((&id, &downloaded.bytes)), running)
            .await
    }
    pub async fn update(&self, id: &str, running: bool, new_url: Option<&str>) -> Result<()> {
        let _lock = self.lock()?;
        let mut store = self.store()?;
        let settings = self.initial_settings().await?;
        let item = store
            .items
            .iter_mut()
            .find(|s| s.id == id)
            .ok_or("订阅不存在")?;
        let raw = new_url.unwrap_or(&item.url);
        let downloaded = download(raw, running.then_some(settings.mixed_port)).await?;
        self.validate(&merge(&downloaded.bytes, &settings, &self.socket)?)
            .await?;
        item.url = url(raw)?.to_string();
        item.updated = chrono::Utc::now().timestamp();
        item.usage = downloaded.usage;
        item.interval_hours = downloaded.interval;
        item.nodes = node_count(&downloaded.bytes);
        self.commit(&store, &settings, Some((id, &downloaded.bytes)), running)
            .await
    }
    pub async fn select(&self, id: &str, running: bool) -> Result<()> {
        let _lock = self.lock()?;
        let mut store = self.store()?;
        if !store.items.iter().any(|s| s.id == id) {
            return Err("订阅不存在".into());
        }
        store.current = Some(id.into());
        self.commit(&store, &self.initial_settings().await?, None, running)
            .await
    }
    pub async fn rename(&self, id: &str, name: &str) -> Result<()> {
        let _lock = self.lock()?;
        let mut store = self.store()?;
        if name.trim().is_empty() {
            return Err("名称不能为空".into());
        }
        store
            .items
            .iter_mut()
            .find(|s| s.id == id)
            .ok_or("订阅不存在")?
            .name = safe_name(name);
        replace(&self.data.join("subscriptions.toml"), &encoded(&store)?)
    }
    pub fn delete(&self, id: &str) -> Result<()> {
        let _lock = self.lock()?;
        let mut store = self.store()?;
        if store.current.as_deref() == Some(id) {
            return Err("当前订阅不能删除；请先切换".into());
        }
        if !store.items.iter().any(|s| s.id == id) {
            return Err("订阅不存在".into());
        }
        store.items.retain(|s| s.id != id);
        replace(&self.data.join("subscriptions.toml"), &encoded(&store)?)?;
        fs::remove_file(self.profile_path(id)?).map_err(|_| "索引已删除；缓存文件删除失败".into())
    }
    pub async fn change(&self, key: &str, value: &str, running: bool) -> Result<()> {
        let _lock = self.lock()?;
        let mut settings = self.initial_settings().await?;
        settings.set(key, value)?;
        self.commit(&self.store()?, &settings, None, running).await
    }
    pub async fn generate(&self) -> Result<()> {
        let _lock = self.lock()?;
        let store = self.store()?;
        if store.current.is_none() {
            return Err("尚无订阅；请到 3 订阅添加".into());
        }
        self.commit(&store, &self.initial_settings().await?, None, false)
            .await
    }
    pub async fn service(&self, verb: &str) -> Result<()> {
        if !matches!(verb, "start" | "stop" | "restart") {
            return Err("服务操作无效".into());
        }
        let status = tokio::time::timeout(
            Duration::from_secs(40),
            tokio::process::Command::new(&self.systemctl)
                .args(["--no-ask-password", verb, SERVICE])
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .kill_on_drop(true)
                .status(),
        )
        .await;
        if status
            .ok()
            .and_then(std::result::Result::ok)
            .is_some_and(|s| s.success())
        {
            Ok(())
        } else {
            Err(self.failure().await)
        }
    }
    pub async fn failure(&self) -> String {
        let show = tokio::process::Command::new(&self.systemctl)
            .args(["show", SERVICE, "-p", "Result,ExecMainStatus"])
            .output()
            .await
            .ok();
        let journal = tokio::process::Command::new("journalctl")
            .args(["-u", SERVICE, "-n", "20", "--no-pager", "-o", "cat"])
            .output()
            .await
            .ok();
        // Classify locally; raw journal may include node names and credentials, so never render it.
        let logs = journal
            .map(|o| String::from_utf8_lossy(&o.stdout).to_string())
            .unwrap_or_default();
        let reason = if logs.contains("校验") || logs.contains("config") {
            "配置缺失或校验失败，请重新选择/更新订阅"
        } else if logs.contains("permission") || logs.contains("Operation not permitted") {
            "权限不足，请检查服务 capability 与 polkit"
        } else {
            "服务启动失败，请检查单元状态；日志内容已隐藏"
        };
        let fields = show
            .map(|o| {
                String::from_utf8_lossy(&o.stdout)
                    .lines()
                    .filter(|s| s.starts_with("Result=") || s.starts_with("ExecMainStatus="))
                    .filter(|s| {
                        s.chars()
                            .all(|c| c.is_ascii_alphanumeric() || "=-_".contains(c))
                    })
                    .collect::<Vec<_>>()
                    .join(" ")
            })
            .unwrap_or_default();
        format!("{reason} · {fields}")
    }
}
fn validation_network_filter() -> std::io::Result<()> {
    // seccomp_data.nr is at 0; args[0] (socket family) at 16 on Linux.
    // Allow AF_UNIX/AF_NETLINK for local inspection; deny Internet socket creation.
    let filter = [
        libc::sock_filter {
            code: (libc::BPF_LD | libc::BPF_W | libc::BPF_ABS) as u16,
            jt: 0,
            jf: 0,
            k: 0,
        },
        libc::sock_filter {
            code: (libc::BPF_JMP | libc::BPF_JEQ | libc::BPF_K) as u16,
            jt: 0,
            jf: 4,
            k: libc::SYS_socket as u32,
        },
        libc::sock_filter {
            code: (libc::BPF_LD | libc::BPF_W | libc::BPF_ABS) as u16,
            jt: 0,
            jf: 0,
            k: 16,
        },
        libc::sock_filter {
            code: (libc::BPF_JMP | libc::BPF_JEQ | libc::BPF_K) as u16,
            jt: 1,
            jf: 0,
            k: libc::AF_INET as u32,
        },
        libc::sock_filter {
            code: (libc::BPF_JMP | libc::BPF_JEQ | libc::BPF_K) as u16,
            jt: 0,
            jf: 1,
            k: libc::AF_INET6 as u32,
        },
        libc::sock_filter {
            code: (libc::BPF_RET | libc::BPF_K) as u16,
            jt: 0,
            jf: 0,
            k: libc::SECCOMP_RET_ERRNO | libc::ENETUNREACH as u32,
        },
        libc::sock_filter {
            code: (libc::BPF_RET | libc::BPF_K) as u16,
            jt: 0,
            jf: 0,
            k: libc::SECCOMP_RET_ALLOW,
        },
    ];
    let program = libc::sock_fprog {
        len: filter.len() as u16,
        filter: filter.as_ptr() as *mut _,
    };
    if unsafe { libc::prctl(libc::PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) } != 0
        || unsafe { libc::prctl(libc::PR_SET_SECCOMP, libc::SECCOMP_MODE_FILTER, &program) } != 0
    {
        return Err(std::io::Error::last_os_error());
    }
    Ok(())
}
fn valid_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() < 96
        && id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
}
fn safe_name(raw: &str) -> String {
    crate::search::redact_log(
        &raw.chars()
            .filter(|c| !c.is_control())
            .take(100)
            .collect::<String>(),
    )
}
fn node_count(bytes: &[u8]) -> usize {
    serde_yaml::from_slice::<Value>(bytes)
        .ok()
        .and_then(|v| v["proxies"].as_sequence().map(Vec::len))
        .unwrap_or(0)
}
pub fn merge(bytes: &[u8], settings: &Settings, socket: &Path) -> Result<Vec<u8>> {
    let mut value: Value =
        serde_yaml::from_slice(bytes).map_err(|_| "订阅不是有效 YAML（内容隐藏）")?;
    if !value.is_mapping()
        || (!value["proxies"].is_sequence() && !value["proxy-providers"].is_mapping())
    {
        return Err("订阅缺少 proxies / proxy-providers".into());
    }
    let baseline: Value = serde_yaml::from_str(&settings.baseline).unwrap_or(Value::Null);
    // Discard every remote control/listener inherited from a subscription. Keep outbound definitions and rules intact.
    for key in [
        "external-controller",
        "external-controller-tls",
        "external-controller-pipe",
        "external-ui",
        "external-ui-url",
        "external-ui-name",
        "secret",
        "listeners",
        "authentication",
        "port",
        "socks-port",
        "redir-port",
        "tproxy-port",
        "ss-config",
        "vmess-config",
        "tuic-server",
        "iptables",
        "ntp",
    ] {
        value.as_mapping_mut().unwrap().remove(Value::from(key));
    }
    for key in ["tun", "dns", "sniffer", "profile"] {
        if baseline[key].is_mapping() {
            value[key] = baseline[key].clone();
        } else {
            value.as_mapping_mut().unwrap().remove(Value::from(key));
        }
    }
    if value["tun"].is_null() {
        value["tun"]=serde_yaml::from_str("{stack: mixed, auto-route: true, auto-detect-interface: true, strict-route: false, dns-hijack: ['any:53']}").unwrap();
    }
    if value["dns"].is_null() {
        value["dns"]=serde_yaml::from_str("{enable: true, listen: ':53', enhanced-mode: fake-ip, fake-ip-range: 198.18.0.1/16, nameserver: [223.5.5.5, 8.8.8.8]}").unwrap();
    }
    if value["sniffer"].is_null() {
        value["sniffer"] = serde_yaml::from_str("{enable: false}").unwrap();
    }
    if value["profile"].is_null() {
        value["profile"] = Value::Mapping(Default::default());
    }
    value["tun"]["enable"] = settings.tun.into();
    value["tun"]["device"] = "mayon-clash".into();
    value["dns"]["ipv6"] = settings.ipv6.into();
    value["profile"]["store-selected"] = true.into();
    value["external-controller-unix"] = socket.to_string_lossy().to_string().into();
    value["mixed-port"] = settings.mixed_port.into();
    value["allow-lan"] = settings.allow_lan.into();
    value["bind-address"] = if settings.allow_lan { "*" } else { "127.0.0.1" }.into();
    value["mode"] = settings.mode.clone().into();
    value["ipv6"] = settings.ipv6.into();
    value["log-level"] = settings.log_level.clone().into();
    value["geodata-mode"] = true.into();
    value["geo-auto-update"] = false.into();
    serde_yaml::to_string(&value)
        .map(String::into_bytes)
        .map_err(|_| "配置编码失败".into())
}
struct Download {
    bytes: Vec<u8>,
    name: String,
    usage: Option<Usage>,
    interval: u64,
}
fn percent(raw: &str) -> String {
    let mut out = Vec::new();
    let mut it = raw.as_bytes().iter().copied();
    while let Some(c) = it.next() {
        if c == b'%' {
            if let (Some(a), Some(b)) = (it.next(), it.next()) {
                if let Ok(v) = u8::from_str_radix(&String::from_utf8_lossy(&[a, b]), 16) {
                    out.push(v);
                }
            }
        } else {
            out.push(c);
        }
    }
    String::from_utf8_lossy(&out).into()
}
fn header_meta(headers: &reqwest::header::HeaderMap, host: &str) -> (String, Option<Usage>, u64) {
    let title = headers
        .get("profile-title")
        .and_then(|v| v.to_str().ok())
        .map(|s| {
            if let Some(s) = s.strip_prefix("base64:") {
                base64::engine::general_purpose::STANDARD
                    .decode(s)
                    .ok()
                    .and_then(|b| String::from_utf8(b).ok())
                    .unwrap_or_default()
            } else {
                s.to_string()
            }
        });
    let filename = headers
        .get("content-disposition")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| {
            let fields: Vec<_> = v.split(';').map(str::trim).collect();
            fields
                .iter()
                .find_map(|s| {
                    s.strip_prefix("filename*=").map(|s| {
                        percent(s.trim_matches('"').split("''").last().unwrap_or_default())
                    })
                })
                .or_else(|| {
                    fields.iter().find_map(|s| {
                        s.strip_prefix("filename=")
                            .map(|s| s.trim_matches('"').to_string())
                    })
                })
        });
    let usage = headers
        .iter()
        .find(|(k, _)| {
            k.as_str()
                .strip_suffix("subscription-userinfo")
                .is_some_and(|p| p.is_empty() || p.ends_with('-'))
        })
        .and_then(|(_, v)| v.to_str().ok())
        .and_then(|v| Usage::from_header(v).ok());
    let interval = headers
        .get("profile-update-interval")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.parse::<u64>().ok())
        .unwrap_or(24)
        .clamp(1, 8760);
    (
        safe_name(
            &title
                .or(filename)
                .filter(|s| !s.trim().is_empty())
                .unwrap_or_else(|| host.into()),
        ),
        usage,
        interval,
    )
}
async fn download(raw: &str, proxy_port: Option<u16>) -> Result<Download> {
    let origin = url(raw)?;
    let fetch = |proxy: Option<u16>| {
        let origin = origin.clone();
        async move {
            let mut builder = reqwest::Client::builder()
                .no_proxy()
                .user_agent("clash.meta/mayon-clash")
                .timeout(Duration::from_secs(25))
                .redirect(reqwest::redirect::Policy::limited(5));
            if let Some(port) = proxy {
                builder = builder.proxy(
                    reqwest::Proxy::all(format!("http://127.0.0.1:{port}"))
                        .map_err(|_| "代理地址无效")?,
                );
            }
            let mut response = builder
                .build()
                .map_err(|_| "下载客户端创建失败")?
                .get(origin.clone())
                .send()
                .await
                .map_err(|_| "订阅下载失败（URL 隐藏）")?
                .error_for_status()
                .map_err(|_| "订阅服务器返回错误（URL 隐藏）")?;
            let (name, usage, interval) =
                header_meta(response.headers(), origin.host_str().unwrap_or("订阅"));
            if response
                .content_length()
                .is_some_and(|n| n > MAX_BODY as u64)
            {
                return Err("订阅超过 32 MiB".to_string());
            }
            let mut bytes = Vec::new();
            while let Some(chunk) = response.chunk().await.map_err(|_| "下载正文失败")? {
                if bytes.len() + chunk.len() > MAX_BODY {
                    return Err("订阅超过 32 MiB".into());
                }
                bytes.extend_from_slice(&chunk);
            }
            if bytes.starts_with(&[0xef, 0xbb, 0xbf]) {
                bytes.drain(..3);
            }
            Ok(Download {
                bytes,
                name,
                usage,
                interval,
            })
        }
    };
    match fetch(None).await {
        Ok(d) => Ok(d),
        Err(e) => {
            if let Some(port) = proxy_port {
                fetch(Some(port)).await
            } else {
                Err(e)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    static NEXT: AtomicUsize = AtomicUsize::new(0);
    const SUB: &[u8] = include_bytes!("../tests/fixtures/native-subscription.yaml");
    struct Fixture(Native);
    impl Fixture {
        fn new() -> Self {
            let data = std::env::temp_dir().join(format!(
                "mayon-native-{}-{}",
                std::process::id(),
                NEXT.fetch_add(1, Ordering::Relaxed)
            ));
            private_dir(&data).unwrap();
            let shell = std::env::var("MAYON_TEST_SHELL").unwrap_or_else(|_| "/bin/sh".into());
            let validator = data.join("validator");
            fs::write(&validator, format!("#!{shell}\nexit 0\n")).unwrap();
            fs::set_permissions(&validator, fs::Permissions::from_mode(0o700)).unwrap();
            Self(Native {
                socket: data.join("api.sock"),
                mihomo: validator,
                systemctl: "/not-used".into(),
                data,
            })
        }
        fn seed(&self) -> Store {
            let _lock = self.0.lock().unwrap();
            let s = Store {
                current: Some("a".into()),
                items: vec![Subscription {
                    id: "a".into(),
                    name: "A".into(),
                    url: "http://example.invalid/a".into(),
                    updated: 0,
                    interval_hours: 24,
                    usage: None,
                    nodes: 1,
                    legacy_current_marker: false,
                }],
            };
            replace(&self.0.data.join("subscriptions/a.yaml"), SUB).unwrap();
            replace(
                &self.0.data.join("subscriptions.toml"),
                &encoded(&s).unwrap(),
            )
            .unwrap();
            s
        }
    }
    impl Drop for Fixture {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0.data);
        }
    }
    #[test]
    fn validator_child_cannot_connect_to_loopback() {
        use std::os::unix::process::CommandExt;
        if let Ok(port) = std::env::var("MAYON_TEST_NETWORK_PROBE") {
            let error = std::net::TcpStream::connect(("127.0.0.1", port.parse::<u16>().unwrap()))
                .unwrap_err();
            assert_eq!(error.raw_os_error(), Some(libc::ENETUNREACH));
            return;
        }
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let mut cmd = std::process::Command::new(std::env::current_exe().unwrap());
        cmd.args([
            "--exact",
            "native::tests::validator_child_cannot_connect_to_loopback",
        ])
        .env(
            "MAYON_TEST_NETWORK_PROBE",
            listener.local_addr().unwrap().port().to_string(),
        );
        unsafe {
            cmd.pre_exec(validation_network_filter);
        }
        assert!(cmd.status().unwrap().success());
    }
    #[test]
    fn overrides_control_preserves_airport_rules() {
        let s=Settings{baseline:"tun: {stack: mixed, strict-route: false}\ndns: {nameserver: [1.1.1.1], enhanced-mode: fake-ip}\nprofile: {store-fake-ip: true}\nsniffer: {enable: false}".into(),..Default::default()};
        let merged = merge(SUB, &s, Path::new("/private/api.sock")).unwrap();
        let v: Value = serde_yaml::from_slice(&merged).unwrap();
        let origin: Value = serde_yaml::from_slice(SUB).unwrap();
        for key in [
            "proxies",
            "proxy-groups",
            "rules",
            "proxy-providers",
            "rule-providers",
        ] {
            assert_eq!(v[key], origin[key]);
        }
        assert!(v["external-controller"].is_null());
        assert!(v["external-controller-tls"].is_null());
        assert!(v["secret"].is_null());
        assert_eq!(
            v["external-controller-unix"].as_str(),
            Some("/private/api.sock")
        );
        assert_eq!(v["mixed-port"].as_u64(), Some(7897));
        assert_eq!(v["allow-lan"].as_bool(), Some(false));
        assert_eq!(v["tun"]["enable"].as_bool(), Some(true));
        assert_eq!(v["profile"]["store-selected"].as_bool(), Some(true));
        assert!(merge(b"not a mapping", &s, Path::new("/api")).is_err());
    }
    #[test]
    fn headers_titles_usage_intervals_redaction() {
        let mut h = reqwest::header::HeaderMap::new();
        h.insert("profile-title", "base64:RGVtbyB0aXRsZQ==".parse().unwrap());
        h.insert("profile-update-interval", "12".parse().unwrap());
        h.insert(
            "x-amz-meta-subscription-userinfo",
            "upload=1; download=2; total=10; expire=2000000000"
                .parse()
                .unwrap(),
        );
        let (title, u, i) = header_meta(&h, "fallback.invalid");
        assert_eq!(title, "Demo title");
        assert_eq!(u.unwrap().used_bytes(), 3);
        assert_eq!(i, 12);
        h.remove("profile-title");
        h.insert(
            "content-disposition",
            "attachment; filename*=UTF-8''Demo%20B.yaml"
                .parse()
                .unwrap(),
        );
        assert_eq!(header_meta(&h, "fallback.invalid").0, "Demo B.yaml");
        h.insert("profile-update-interval", "invalid".parse().unwrap());
        assert_eq!(header_meta(&h, "fallback.invalid").2, 24);
        assert_eq!(
            redact_url("https://user:password@example.invalid/private?token=hidden#foo"),
            "https://example.invalid/…"
        );
        assert!(!redact_url("bad token").contains("token"));
    }
    #[test]
    fn subscription_index_round_trips_retired_marker_without_interpreting_it() {
        let value: Store = toml::from_str(
            "current = 'a'\n[[items]]\nid = 'a'\nname = 'A'\nurl = 'https://example.invalid'\nupdated = 0\ninterval_hours = 24\nnodes = 0\nverge_current = true\n",
        )
        .unwrap();
        assert_eq!(value.current.as_deref(), Some("a"));
        assert_eq!(value.items[0].id, "a");
        assert_eq!(value.items[0].url, "https://example.invalid");
        assert!(value.items[0].legacy_current_marker);
        let saved = encoded(&value).unwrap();
        let saved = String::from_utf8(saved).unwrap();
        assert!(saved.contains("verge_current = true"));
        let restored: Store = toml::from_str(&saved).unwrap();
        assert_eq!(restored.current.as_deref(), Some("a"));
        assert_eq!(restored.items[0].id, "a");
        assert_eq!(restored.items[0].url, "https://example.invalid");
    }
    #[test]
    fn saved_baseline_round_trips_and_is_used_for_generation() {
        let f = Fixture::new();
        let baseline = "tun: {stack: system, strict-route: false}\ndns: {nameserver: [1.1.1.1], enhanced-mode: fake-ip}\nsniffer: {enable: false}\nprofile: {store-fake-ip: true}";
        let settings = Settings {
            baseline: baseline.into(),
            ..Settings::default()
        };
        replace(
            &f.0.data.join("settings.toml"),
            &encoded(&settings).unwrap(),
        )
        .unwrap();

        let loaded = f.0.settings().unwrap();
        assert_eq!(loaded.baseline, baseline);
        let generated = merge(SUB, &loaded, &f.0.socket).unwrap();
        let generated: Value = serde_yaml::from_slice(&generated).unwrap();
        assert_eq!(generated["tun"]["stack"].as_str(), Some("system"));
        assert_eq!(generated["dns"]["nameserver"][0].as_str(), Some("1.1.1.1"));
    }
    #[test]
    fn absent_saved_baseline_uses_built_in_defaults() {
        let settings: Settings = toml::from_str("tun = true\nmode = 'rule'\n").unwrap();
        assert_eq!(settings.baseline, Settings::default().baseline);
        let generated = merge(SUB, &settings, Path::new("/private/api.sock")).unwrap();
        let generated: Value = serde_yaml::from_slice(&generated).unwrap();
        assert_eq!(generated["tun"]["stack"].as_str(), Some("mixed"));
        assert_eq!(
            generated["dns"]["nameserver"][0].as_str(),
            Some("223.5.5.5")
        );
    }
    #[tokio::test]
    async fn validation_failure_never_changes_previous_config() {
        let f = Fixture::new();
        f.seed();
        f.0.generate().await.unwrap();
        let path = f.0.data.join("config.yaml");
        let before = fs::read(&path).unwrap();
        let shell = std::env::var("MAYON_TEST_SHELL").unwrap_or_else(|_| "/bin/sh".into());
        fs::write(&f.0.mihomo, format!("#!{shell}\nexit 1\n")).unwrap();
        assert!(f.0.change("mode", "global", false).await.is_err());
        assert_eq!(fs::read(path).unwrap(), before);
        assert_eq!(f.0.settings().unwrap().mode, "rule");
        assert!(!fs::read_dir(&f.0.data)
            .unwrap()
            .flatten()
            .any(|e| e.file_name().to_string_lossy().contains("tmp-")));
    }
    #[tokio::test]
    async fn hot_reload_failure_rolls_back_files_and_reloads_old_config() {
        let f = Fixture::new();
        f.seed();
        f.0.generate().await.unwrap();
        let before = fs::read(f.0.data.join("config.yaml")).unwrap();
        let listener = tokio::net::UnixListener::bind(&f.0.socket).unwrap();
        let server = tokio::spawn(async move {
            for (method, code, body) in [
                ("PUT /configs?force=true ", "500 Rejected", ""),
                ("PUT /configs?force=true ", "204 No Content", ""),
                (
                    "GET /configs ",
                    "200 OK",
                    r#"{"mode":"rule","tun":{"enable":true},"mixed-port":7897}"#,
                ),
            ] {
                let (mut socket, _) = listener.accept().await.unwrap();
                let mut b = [0; 4096];
                let n = socket.read(&mut b).await.unwrap();
                assert!(String::from_utf8_lossy(&b[..n]).starts_with(method));
                socket.write_all(format!("HTTP/1.1 {code}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",body.len()).as_bytes()).await.unwrap();
            }
        });
        let error = f.0.change("mode", "global", true).await.unwrap_err();
        assert!(error.contains("已回滚"));
        server.await.unwrap();
        assert_eq!(fs::read(f.0.data.join("config.yaml")).unwrap(), before);
        assert_eq!(f.0.settings().unwrap().mode, "rule");
    }
    #[tokio::test]
    async fn successful_http_status_with_failed_listener_rolls_back() {
        let f = Fixture::new();
        f.seed();
        f.0.generate().await.unwrap();
        let listener = tokio::net::UnixListener::bind(&f.0.socket).unwrap();
        let server = tokio::spawn(async move {
            for body in [
                "",
                r#"{"mode":"rule","tun":{"enable":false},"mixed-port":0}"#,
                "",
                r#"{"mode":"rule","tun":{"enable":true},"mixed-port":7897}"#,
            ] {
                let (mut socket, _) = listener.accept().await.unwrap();
                let mut b = [0; 4096];
                let _ = socket.read(&mut b).await.unwrap();
                socket.write_all(format!("HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",body.len()).as_bytes()).await.unwrap();
            }
        });
        assert!(f
            .0
            .change("mixed-port", "12345", true)
            .await
            .unwrap_err()
            .contains("已回滚"));
        server.await.unwrap();
        assert_eq!(f.0.settings().unwrap().mixed_port, 7897);
    }
    #[test]
    fn concurrent_writers_rejected_and_no_path_traversal() {
        let f = Fixture::new();
        let lock = f.0.lock().unwrap();
        assert!(f.0.lock().is_err());
        drop(lock);
        assert!(f.0.lock().is_ok());
        assert!(f.0.profile_path("../secret").is_err());
    }
    #[tokio::test]
    async fn proxy_retry_and_header_download() {
        let l = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = l.local_addr().unwrap().port();
        let server = tokio::spawn(async move {
            let (mut s, _) = l.accept().await.unwrap();
            let mut b = [0; 4096];
            let n = s.read(&mut b).await.unwrap();
            let r = String::from_utf8_lossy(&b[..n]);
            assert!(r.starts_with("GET http://127.0.0.1:1/sub"));
            assert!(r
                .to_lowercase()
                .contains("user-agent: clash.meta/mayon-clash"));
            s.write_all(format!("HTTP/1.1 200 OK\r\nContent-Length: {}\r\nProfile-title: Example\r\nSubscription-userinfo: upload=1;total=10\r\n\r\n",SUB.len()).as_bytes()).await.unwrap();
            s.write_all(SUB).await.unwrap();
        });
        let d = download("http://127.0.0.1:1/sub", Some(port))
            .await
            .unwrap();
        assert_eq!(d.name, "Example");
        assert_eq!(d.bytes, SUB);
        assert_eq!(d.usage.unwrap().total, 10);
        server.await.unwrap();
    }
}
