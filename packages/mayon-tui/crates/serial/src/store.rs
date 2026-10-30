use crate::{codec::Encoding, transport::Settings};
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    fs::{self, File, OpenOptions},
    io::{self, Write},
    os::unix::fs::{OpenOptionsExt, PermissionsExt},
    path::{Path, PathBuf},
};

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct Profile {
    pub settings: Settings,
    pub encoding: Encoding,
    pub ending: String,
    pub flash: String,
    pub flash_dir: String,
}
impl Default for Profile {
    fn default() -> Self {
        Self {
            settings: Settings::default(),
            encoding: Encoding::Utf8,
            ending: "CRLF".into(),
            flash: String::new(),
            flash_dir: String::new(),
        }
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Favorite {
    pub name: String,
    pub value: String,
    pub hex: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct Config {
    pub devices: BTreeMap<String, Profile>,
    pub favorites: Vec<Favorite>,
    pub highlights: Vec<String>,
    pub scrollback: usize,
}
impl Default for Config {
    fn default() -> Self {
        Self {
            devices: BTreeMap::new(),
            favorites: Vec::new(),
            highlights: vec!["ERROR".into(), "WARN".into(), "FAULT".into()],
            scrollback: 100_000,
        }
    }
}
pub struct Store {
    pub config: Config,
    pub history: Vec<String>,
    pub config_path: PathBuf,
    pub data: PathBuf,
}
fn xdg(variable: &str, fallback: &str) -> io::Result<PathBuf> {
    if let Some(path) = std::env::var_os(variable).filter(|v| !v.is_empty()) {
        return Ok(path.into());
    }
    Ok(
        PathBuf::from(std::env::var_os("HOME").ok_or_else(|| io::Error::other("HOME 未设置"))?)
            .join(fallback),
    )
}
pub fn private_dir(path: &Path) -> io::Result<()> {
    fs::create_dir_all(path)?;
    fs::set_permissions(path, fs::Permissions::from_mode(0o700))
}
pub fn private_file(path: &Path) -> io::Result<File> {
    OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(path)
}
fn atomic_json(path: &Path, value: &impl Serialize) -> io::Result<()> {
    let temporary = path.with_extension(format!("{}.tmp", std::process::id()));
    let mut file = private_file(&temporary)?;
    let result = (|| {
        serde_json::to_writer_pretty(&mut file, value)?;
        file.write_all(b"\n")?;
        file.sync_all()?;
        fs::rename(&temporary, path)
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result
}
impl Store {
    pub fn load() -> io::Result<Self> {
        Self::at(
            xdg("XDG_CONFIG_HOME", ".config")?.join("serial-mayon"),
            xdg("XDG_DATA_HOME", ".local/share")?.join("serial-mayon"),
        )
    }
    pub fn at(config_dir: PathBuf, data: PathBuf) -> io::Result<Self> {
        private_dir(&config_dir)?;
        private_dir(&data)?;
        private_dir(&data.join("logs"))?;
        let config_path = config_dir.join("config.json");
        let config = match fs::read(&config_path) {
            Ok(bytes) => serde_json::from_slice(&bytes).map_err(io::Error::other)?,
            Err(e) if e.kind() == io::ErrorKind::NotFound => Config::default(),
            Err(e) => return Err(e),
        };
        let history = match fs::read(data.join("history.json")) {
            Ok(bytes) => serde_json::from_slice(&bytes).map_err(io::Error::other)?,
            Err(e) if e.kind() == io::ErrorKind::NotFound => Vec::new(),
            Err(e) => return Err(e),
        };
        Ok(Self {
            config,
            history,
            config_path,
            data,
        })
    }
    pub fn save(&self) -> io::Result<()> {
        atomic_json(&self.config_path, &self.config)?;
        atomic_json(&self.data.join("history.json"), &self.history)
    }
    pub fn remember(&mut self, line: String) {
        if self.history.last() != Some(&line) {
            self.history.push(line);
        }
        if self.history.len() > 1000 {
            self.history.drain(..self.history.len() - 1000);
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn persistence_permissions_and_invalid_config() {
        let dir = tempfile::tempdir().unwrap();
        let mut store = Store::at(dir.path().join("config"), dir.path().join("data")).unwrap();
        store.remember("中文 status".into());
        store.save().unwrap();
        assert_eq!(
            fs::metadata(&store.config_path)
                .unwrap()
                .permissions()
                .mode()
                & 0o777,
            0o600
        );
        assert_eq!(
            fs::metadata(&store.data).unwrap().permissions().mode() & 0o777,
            0o700
        );
        let path = store.config_path.clone();
        assert_eq!(
            Store::at(path.parent().unwrap().into(), store.data.clone())
                .unwrap()
                .history,
            vec!["中文 status"]
        );
        fs::write(&path, b"invalid").unwrap();
        assert!(Store::at(path.parent().unwrap().into(), store.data).is_err());
        assert_eq!(fs::read(path).unwrap(), b"invalid");
    }
}
