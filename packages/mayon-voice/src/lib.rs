use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    env, fs,
    io::{self, BufRead, BufReader, Read, Write},
    os::unix::{fs::PermissionsExt, net::UnixStream},
    path::PathBuf,
    time::Duration,
};

pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;

#[derive(Clone, Deserialize, Serialize)]
#[serde(default, deny_unknown_fields)]
pub struct Config {
    pub engine: String,
    pub model_dir: PathBuf,
    pub model_file: Option<PathBuf>,
    pub whisper_binary: String,
    pub device: String,
    pub threads: u32,
    pub input_device: String,
    pub delivery: String,
    pub hotwords: Vec<String>,
    pub idle_seconds: u64,
    pub max_record_seconds: u64,
    pub polish: bool,
    pub key_file: PathBuf,
}
impl Default for Config {
    fn default() -> Self {
        Self {
            engine: "sensevoice".into(),
            model_dir: data_dir().join("models/sensevoice"),
            model_file: None,
            whisper_binary: "whisper-cli".into(),
            device: "cpu".into(),
            threads: 4,
            input_device: "auto".into(),
            delivery: "auto".into(),
            hotwords: vec![],
            idle_seconds: 600,
            max_record_seconds: 120,
            polish: false,
            key_file: "/run/secrets/deepseek-api-key".into(),
        }
    }
}
impl Config {
    pub fn load() -> Result<Self> {
        let path = config_dir().join("config.toml");
        let config: Self = match fs::read_to_string(path) {
            Ok(s) => toml::from_str(&s)?,
            Err(e) if e.kind() == io::ErrorKind::NotFound => Self::default(),
            Err(e) => return Err(e.into()),
        };
        if !["sensevoice", "paraformer", "whisper-cli"].contains(&config.engine.as_str())
            || !["auto", "fcitx", "wtype", "clipboard"].contains(&config.delivery.as_str())
            || !["cpu", "cuda"].contains(&config.device.as_str())
            || config.idle_seconds == 0
            || config.max_record_seconds == 0
            || config.max_record_seconds > 600
            || !(1..=16).contains(&config.threads)
        {
            return Err("配置值超出允许范围".into());
        }
        Ok(config)
    }
}
pub fn home() -> PathBuf {
    env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."))
}
pub fn config_dir() -> PathBuf {
    env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join(".config"))
        .join("mayon-voice")
}
pub fn data_dir() -> PathBuf {
    env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join(".local/share"))
        .join("mayon-voice")
}
pub fn runtime() -> Result<PathBuf> {
    let base = PathBuf::from(env::var_os("XDG_RUNTIME_DIR").ok_or("缺少 XDG_RUNTIME_DIR")?);
    let path = base.join("mayon-voice");
    fs::create_dir_all(&path)?;
    let meta = fs::symlink_metadata(&path)?;
    use std::os::unix::fs::MetadataExt;
    if !meta.is_dir() || meta.uid() != unsafe { libc::geteuid() } {
        return Err("runtime 目录归属错误".into());
    }
    fs::set_permissions(&path, fs::Permissions::from_mode(0o700))?;
    Ok(path)
}
pub fn socket_path() -> Result<PathBuf> {
    Ok(runtime()?.join("control.sock"))
}

pub fn client(command: &str) -> Result<Value> {
    client_with_timeout(command, Duration::from_secs(5))
}
pub fn client_with_timeout(command: &str, timeout: Duration) -> Result<Value> {
    let mut socket = UnixStream::connect(socket_path()?)?;
    socket.set_read_timeout(Some(timeout))?;
    socket.set_write_timeout(Some(timeout))?;
    writeln!(socket, "{command}")?;
    let mut response = String::new();
    BufReader::new(socket)
        .take(65536)
        .read_line(&mut response)?;
    Ok(serde_json::from_str(&response)?)
}
