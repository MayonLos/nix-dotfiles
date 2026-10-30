use anyhow::{bail, Context, Result};
use serde::{Deserialize, Serialize};
use std::{
    fs::{self, OpenOptions},
    io::{Read, Write},
    os::unix::fs::{OpenOptionsExt, PermissionsExt},
    path::{Path, PathBuf},
};

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(default)]
pub struct Config {
    pub report_history: bool,
    pub danmaku: bool,
    pub danmaku_options: crate::danmaku::Options,
    pub download_dir: PathBuf,
}
impl Default for Config {
    fn default() -> Self {
        Self {
            report_history: true,
            danmaku: true,
            danmaku_options: Default::default(),
            download_dir: home().join("Videos/Bilibili"),
        }
    }
}
pub fn home() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."))
}
fn xdg(key: &str, fallback: &str) -> PathBuf {
    std::env::var_os(key)
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join(fallback))
}
pub fn data() -> PathBuf {
    xdg("XDG_DATA_HOME", ".local/share").join("bilitui")
}
pub fn cache() -> PathBuf {
    xdg("XDG_CACHE_HOME", ".cache").join("bilitui")
}
pub fn config_path() -> PathBuf {
    xdg("XDG_CONFIG_HOME", ".config").join("bilitui/config.toml")
}
pub fn private_dir(path: &Path) -> Result<()> {
    fs::create_dir_all(path)?;
    if fs::symlink_metadata(path)?.file_type().is_symlink() {
        bail!("私有目录不可为符号链接");
    }
    fs::set_permissions(path, fs::Permissions::from_mode(0o700))?;
    Ok(())
}
pub fn write_private(path: &Path, bytes: &[u8]) -> Result<()> {
    private_dir(path.parent().context("文件缺少父目录")?)?;
    let temp = path.with_extension(format!("tmp-{}", std::process::id()));
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&temp)?;
    let outcome = (|| -> Result<()> {
        file.write_all(bytes)?;
        file.sync_all()?;
        fs::rename(&temp, path)?;
        Ok(())
    })();
    if outcome.is_err() {
        let _ = fs::remove_file(temp);
    }
    outcome
}
pub fn read_cookie() -> Result<String> {
    let path = data().join("cookie");
    if !path.exists() {
        return Ok(String::new());
    }
    let meta = fs::symlink_metadata(&path)?;
    if !meta.is_file() || meta.permissions().mode() & 0o077 != 0 {
        bail!("cookie 必须是权限 0600 的普通文件");
    }
    // Linux O_NOFOLLOW also closes the metadata/open symlink race.
    let mut file = OpenOptions::new()
        .read(true)
        .custom_flags(0o400000)
        .open(path)?;
    let mut value = String::new();
    std::io::Read::by_ref(&mut file)
        .take(16385)
        .read_to_string(&mut value)?;
    if value.len() > 16384 || value.contains(['\r', '\n']) {
        bail!("cookie 格式无效");
    }
    Ok(value)
}
pub fn save_cookie(cookie: &str) -> Result<()> {
    if cookie.contains(['\n', '\r']) {
        bail!("cookie 格式无效");
    }
    write_private(&data().join("cookie"), cookie.as_bytes())
}
pub fn config() -> Result<Config> {
    let path = config_path();
    if path.exists() {
        Ok(toml::from_str(&fs::read_to_string(path)?)?)
    } else {
        Ok(Config::default())
    }
}
pub fn history() -> Vec<String> {
    fs::read(data().join("search.json"))
        .ok()
        .and_then(|b| serde_json::from_slice(&b).ok())
        .unwrap_or_default()
}
pub fn add_search(query: &str) -> Result<()> {
    let mut history = history();
    history.retain(|s| s != query);
    history.insert(0, query.into());
    history.truncate(40);
    write_private(&data().join("search.json"), &serde_json::to_vec(&history)?)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn private_file_mode() {
        let p = std::env::temp_dir().join(format!("bilitui-mode-{}", std::process::id()));
        private_dir(&p).unwrap();
        write_private(&p.join("cookie"), b"fixture").unwrap();
        assert_eq!(
            fs::metadata(p.join("cookie")).unwrap().permissions().mode() & 0o777,
            0o600
        );
        assert_eq!(
            fs::metadata(&p).unwrap().permissions().mode() & 0o777,
            0o700
        );
        fs::remove_file(p.join("cookie")).unwrap();
        fs::remove_dir(p).unwrap();
    }
}
