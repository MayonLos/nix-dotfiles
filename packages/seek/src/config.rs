use anyhow::{bail, Context, Result};
use serde::{Deserialize, Serialize};
use std::{
    fs,
    io::{self, Write},
    os::unix::fs::{DirBuilderExt, OpenOptionsExt, PermissionsExt},
    path::{Path, PathBuf},
};

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Config {
    pub confirmed: bool,
    pub include: Vec<PathBuf>,
    pub exclude: Vec<String>,
    pub embeddings: bool,
    pub ocr: bool,
    pub max_file_mb: u64,
    pub qa: Qa,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Qa {
    pub backend: String,
    pub key_file: PathBuf,
    pub model: String,
}
impl Default for Qa {
    fn default() -> Self {
        Self {
            backend: "deepseek".into(),
            key_file: "/run/secrets/deepseek-api-key".into(),
            model: "deepseek-flash".into(),
        }
    }
}
impl Default for Config {
    fn default() -> Self {
        Self {
            confirmed: false,
            include: vec![],
            exclude: [
                "**/.*",
                "**/.*/**",
                "**/node_modules/**",
                "**/target/**",
                "**/Steam/**",
                "**/PrismLauncher/**",
                "**/prism*/**",
                "**/VirtualBox VMs/**",
                "**/VMs/**",
                "**/libvirt/**",
                "**/xwechat_files/**",
                "**/secrets/**",
                "**/*credential*",
                "**/*token*",
                "**/.env*",
                "**/*.pem",
                "**/*.key",
                "**/*.qcow2",
                "**/*.vdi",
                "**/*.vmdk",
                "**/*.iso",
            ]
            .iter()
            .map(|s| s.to_string())
            .collect(),
            embeddings: true,
            ocr: false,
            max_file_mb: 32,
            qa: Qa::default(),
        }
    }
}
pub fn home() -> Result<PathBuf> {
    Ok(std::env::var_os("HOME").context("HOME 未设置")?.into())
}
pub fn xdg(var: &str, fallback: &str) -> Result<PathBuf> {
    Ok(std::env::var_os(var)
        .map(PathBuf::from)
        .unwrap_or(home()?.join(fallback))
        .join("seek"))
}
pub fn config_path() -> Result<PathBuf> {
    Ok(xdg("XDG_CONFIG_HOME", ".config")?.join("config.toml"))
}
pub fn private_dir(path: &Path) -> Result<()> {
    if path.is_symlink() {
        bail!("私有目录不能是 symlink");
    }
    fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(path)?;
    fs::set_permissions(path, fs::Permissions::from_mode(0o700))?;
    Ok(())
}
pub fn atomic(path: &Path, bytes: &[u8]) -> Result<()> {
    let parent = path.parent().context("缺少父目录")?;
    private_dir(parent)?;
    let mut tmp = tempfile::NamedTempFile::new_in(parent)?;
    tmp.as_file()
        .set_permissions(fs::Permissions::from_mode(0o600))?;
    tmp.write_all(bytes)?;
    tmp.as_file().sync_all()?;
    tmp.persist(path).map_err(|e| e.error)?;
    Ok(())
}
pub fn load(path: &Path) -> Result<Config> {
    let c: Config = toml::from_str(
        &fs::read_to_string(path).context("先执行 seek init，再审核配置并 seek init --confirm")?,
    )?;
    if c.max_file_mb == 0 || c.max_file_mb > 256 {
        bail!("max_file_mb 须在 1..256");
    }
    if c.include.iter().any(|p| !p.is_absolute()) {
        bail!("include 必须是绝对路径");
    }
    Ok(c)
}
pub fn approved(c: &Config) -> Result<()> {
    if !c.confirmed || c.include.is_empty() {
        bail!("索引范围尚未确认：编辑 config.toml 的 include/exclude 后，运行 seek init --confirm");
    }
    Ok(())
}
pub fn init(path: &Path, confirm: bool) -> Result<()> {
    if !path.exists() {
        let h = home()?;
        let mut names = vec![];
        for e in fs::read_dir(&h)?.flatten() {
            if !e.file_type()?.is_dir() || e.file_name().to_string_lossy().starts_with('.') {
                continue;
            }
            names.push(e.path());
            for sub in fs::read_dir(e.path()).into_iter().flatten().flatten() {
                if sub.file_type()?.is_dir() && !sub.file_name().to_string_lossy().starts_with('.')
                {
                    names.push(sub.path());
                }
            }
        }
        names.sort();
        println!("目录名调查（最多两级，未读文件内容）：");
        for n in &names {
            println!("  {}", n.strip_prefix(&h).unwrap_or(n).display());
        }
        let mut c = Config::default();
        for p in ["Vaults", "notes", "Documents/notes", "Dev", "latex"] {
            if names.contains(&h.join(p)) {
                c.include.push(h.join(p));
            }
        }
        atomic(path, toml::to_string_pretty(&c)?.as_bytes())?;
        println!(
            "建议已写入 {}。请审核 include/exclude；确认前不索引。",
            path.display()
        );
    }
    if confirm {
        let mut c = load(path)?;
        println!("将允许读取以下目录的文件内容（不跟随 symlink）：");
        for p in &c.include {
            println!("  {}", p.display());
        }
        println!("排除规则：{}", c.exclude.join(", "));
        print!("输入 yes 确认索引范围：");
        io::stdout().flush()?;
        let mut answer = String::new();
        io::stdin().read_line(&mut answer)?;
        if answer.trim() != "yes" {
            bail!("未确认");
        }
        c.confirmed = true;
        approved(&c)?;
        atomic(path, toml::to_string_pretty(&c)?.as_bytes())?;
    }
    Ok(())
}
pub fn lock(data: &Path) -> Result<fs::File> {
    private_dir(data)?;
    let f = fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .open(data.join("index.lock"))?;
    fs2::FileExt::try_lock_exclusive(&f).context("已有索引任务运行")?;
    Ok(f)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn requires_explicit_scope() {
        assert!(approved(&Config::default()).is_err());
    }
    #[test]
    fn private_writes() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("x/c.toml");
        atomic(&p, b"x").unwrap();
        assert_eq!(fs::metadata(p).unwrap().permissions().mode() & 0o777, 0o600);
    }
}
