//! Modrinth search, server-side install and conservative Prism instance import.
use anyhow::{anyhow, bail, Context, Result};
use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use sha1::{Digest as _, Sha1};
use sha2::Sha512;
use std::{
    collections::{HashSet, VecDeque},
    fs::{self, File, OpenOptions},
    io::{Read, Write},
    path::{Component, Path, PathBuf},
    time::Duration,
};
use zip::ZipArchive;

const API: &str = "https://api.modrinth.com/v2";
const UA: &str = "mayon/mcsrv-mayon/0.1.0 (https://github.com/mayon/nix-dotfiles)";
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ModHit {
    pub id: String,
    pub slug: String,
    pub title: String,
    pub description: String,
    #[serde(default)]
    pub server_side: String,
    #[serde(default)]
    pub client_side: String,
    #[serde(default)]
    pub downloads: u64,
}
#[derive(Deserialize)]
struct SearchResponse {
    hits: Vec<ModHit>,
}
#[derive(Deserialize)]
struct Project {
    id: String,
    title: String,
    server_side: String,
    client_side: String,
}
#[derive(Deserialize)]
struct Version {
    id: String,
    project_id: String,
    version_number: String,
    #[serde(default)]
    game_versions: Vec<String>,
    #[serde(default)]
    loaders: Vec<String>,
    #[serde(default)]
    dependencies: Vec<Dependency>,
    files: Vec<VersionFile>,
}
#[derive(Clone, Deserialize)]
struct Dependency {
    project_id: Option<String>,
    version_id: Option<String>,
    dependency_type: String,
}
#[derive(Deserialize)]
struct VersionFile {
    url: String,
    filename: String,
    primary: bool,
    hashes: Hashes,
}
#[derive(Deserialize)]
struct Hashes {
    sha1: Option<String>,
    sha512: Option<String>,
}
fn client() -> Result<Client> {
    Ok(Client::builder()
        .user_agent(UA)
        .connect_timeout(Duration::from_secs(10))
        .timeout(Duration::from_secs(120))
        .build()?)
}
fn safe_name(name: &str) -> Result<&str> {
    if name.is_empty()
        || name == "."
        || name == ".."
        || name.contains('/')
        || name.contains('\\')
        || name.chars().any(char::is_control)
    {
        bail!("Modrinth 文件名非法：{name}");
    }
    Ok(name)
}
fn safe_rel(name: &str) -> Result<PathBuf> {
    let path = Path::new(name);
    if path.is_absolute() || name.contains('\\') || name.contains(':') {
        bail!("Prism 文件路径非法：{name}");
    }
    let mut result = PathBuf::new();
    for c in path.components() {
        match c {
            Component::Normal(x) => result.push(x),
            Component::CurDir => {}
            _ => bail!("Prism 路径越界：{name}"),
        }
    }
    if result.as_os_str().is_empty() {
        bail!("空文件路径");
    }
    Ok(result)
}
fn copy_tree(src: &Path, dst: &Path) -> Result<()> {
    let md = fs::symlink_metadata(src)?;
    if md.file_type().is_symlink() {
        bail!("拒绝复制 Prism 符号链接：{}", src.display());
    }
    if md.is_dir() {
        fs::create_dir_all(dst)?;
        for entry in fs::read_dir(src)? {
            let entry = entry?;
            let name = entry.file_name();
            let name = name.to_string_lossy();
            let rel = safe_rel(&name)?;
            copy_tree(&entry.path(), &dst.join(rel))?;
        }
    } else if md.is_file() {
        if dst.exists() {
            bail!("Prism 导入会覆盖文件：{}", dst.display());
        }
        if let Some(p) = dst.parent() {
            fs::create_dir_all(p)?;
        }
        fs::copy(src, dst)?;
    }
    Ok(())
}
#[derive(Deserialize)]
struct FabricMod {
    id: Option<String>,
    environment: Option<serde_json::Value>,
}
fn client_only(path: &Path) -> Result<(Option<String>, bool)> {
    if path.extension().and_then(|x| x.to_str()) != Some("jar") {
        return Ok((None, false));
    }
    let f = File::open(path)?;
    let mut zip = match ZipArchive::new(f) {
        Ok(z) => z,
        Err(_) => return Ok((None, false)),
    };
    let mut raw = match zip.by_name("fabric.mod.json") {
        Ok(f) => f,
        Err(_) => return Ok((None, false)),
    };
    let mut text = String::new();
    raw.read_to_string(&mut text)?;
    let m: FabricMod = serde_json::from_str(&text).context("无效 fabric.mod.json")?;
    let env = m
        .environment
        .as_ref()
        .and_then(|v| v.as_str())
        .unwrap_or("");
    if env == "client" {
        return Ok((
            Some(m.id.unwrap_or_else(|| {
                path.file_name()
                    .unwrap_or_default()
                    .to_string_lossy()
                    .into_owned()
            })),
            true,
        ));
    }
    Ok((None, true))
}

/// Best-effort public Modrinth lookup for jars without affirmative Fabric
/// client metadata. API/network errors are deliberately returned to the caller
/// so the importer can preserve the source jar and report the uncertainty.
fn modrinth_server_unsupported(
    path: &Path,
    cache: &mut std::collections::HashMap<String, Option<String>>,
) -> Result<Option<String>> {
    let mut input = File::open(path)?;
    let mut hasher = Sha1::new();
    let mut buf = [0; 65536];
    loop {
        let n = input.read(&mut buf)?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    let hash = format!("{:x}", hasher.finalize());
    if let Some(cached) = cache.get(&hash) {
        return Ok(cached.clone());
    }
    let response = client()?
        .get(format!("{API}/version_file/{hash}"))
        .query(&[("algorithm", "sha1")])
        .send()?;
    if response.status() == reqwest::StatusCode::NOT_FOUND {
        cache.insert(hash, None);
        return Ok(None);
    }
    let version: Version = response.error_for_status()?.json()?;
    let project = get_project(&version.project_id)?;
    let result = if project.server_side == "unsupported" {
        Some(project.title)
    } else {
        None
    };
    cache.insert(hash, result.clone());
    Ok(result)
}
/// Copy Prism `mods/` and `config/` into a fresh server directory. Jars
/// positively identified as client-only by Fabric metadata or Modrinth project
/// metadata are removed; unknown Forge/Quilt/other jars are preserved.
pub fn import_prism(prism: &Path, destination: &Path) -> Result<Vec<String>> {
    if !prism.is_dir() {
        bail!("Prism 实例目录不存在：{}", prism.display());
    }
    fs::create_dir_all(destination)?;
    let source_root = if prism.join(".minecraft").exists() {
        let candidate = prism.join(".minecraft");
        if fs::symlink_metadata(&candidate)?.file_type().is_symlink() {
            bail!("拒绝读取 Prism .minecraft 符号链接");
        }
        candidate
    } else if prism.join("minecraft").exists() {
        let candidate = prism.join("minecraft");
        if fs::symlink_metadata(&candidate)?.file_type().is_symlink() {
            bail!("拒绝读取 Prism minecraft 符号链接");
        }
        candidate
    } else {
        prism.to_path_buf()
    };
    let mut report = Vec::new();
    let mut modrinth_cache = std::collections::HashMap::new();
    for tree in ["mods", "config"] {
        let src = source_root.join(tree);
        if !src.exists() {
            continue;
        }
        if destination.join(tree).exists() {
            bail!("Prism 导入目标已有 {tree}，拒绝合并覆盖");
        }
        if tree == "mods" {
            if fs::symlink_metadata(&src)?.file_type().is_symlink() {
                bail!("拒绝读取 Prism mods 符号链接");
            }
            fs::create_dir_all(destination.join(tree))?;
            for e in fs::read_dir(&src)? {
                let e = e?;
                let p = e.path();
                let dest = destination.join(tree).join(e.file_name());
                let metadata = fs::symlink_metadata(&p)?;
                if metadata.file_type().is_symlink() {
                    bail!("拒绝复制 Prism 符号链接：{}", p.display());
                }
                if metadata.is_file() && p.extension().and_then(|x| x.to_str()) == Some("jar") {
                    let (fabric_client, has_fabric_metadata) = client_only(&p)?;
                    let mut api_failed = false;
                    let client_id = if fabric_client.is_some() || has_fabric_metadata {
                        fabric_client
                    } else {
                        match modrinth_server_unsupported(&p, &mut modrinth_cache) {
                            Ok(Some(title)) => {
                                Some(format!("{title}（Modrinth 标记 server_side=unsupported）"))
                            }
                            Ok(None) => None,
                            Err(error) => {
                                api_failed = true;
                                report.push(format!(
                                    "Modrinth 服务端标记查询失败，保留并待确认：{}（{error:#}）",
                                    e.file_name().to_string_lossy()
                                ));
                                None
                            }
                        }
                    };
                    match client_id {
                        Some(id) => {
                            let evidence = if has_fabric_metadata {
                                "fabric.mod.json environment=client"
                            } else {
                                "Modrinth server_side=unsupported"
                            };
                            report.push(format!("已排除客户端模组 {id}（{evidence}）"));
                            continue;
                        }
                        None => {
                            if !api_failed {
                                report.push(format!(
                                    "保留并待确认服务端兼容性：{}",
                                    e.file_name().to_string_lossy()
                                ));
                            }
                        }
                    }
                }
                copy_tree(&p, &dest)?;
            }
        } else {
            copy_tree(&src, &destination.join(tree))?;
        }
    }
    report.push("检测依据：Fabric fabric.mod.json 的 environment=client 与 Modrinth 项目 server_side=unsupported；查询失败、404 和未知格式的模组全部保留并供人工复核，不会从文件名猜测剔除 Forge 模组。".into());
    Ok(report)
}

/// Search public Modrinth projects. Results include server/client environment flags.
pub fn search(query: &str) -> Result<Vec<ModHit>> {
    if query.trim().is_empty() {
        bail!("搜索词不能为空");
    }
    let response: SearchResponse = client()?
        .get(format!("{API}/search"))
        .query(&[
            ("query", query),
            ("facets", "[[\"project_type:mod\"]]"),
            ("limit", "20"),
        ])
        .send()?
        .error_for_status()?
        .json()?;
    Ok(response.hits)
}
fn get_project(id: &str) -> Result<Project> {
    Ok(client()?
        .get(format!("{API}/project/{id}"))
        .send()?
        .error_for_status()?
        .json()?)
}
fn select_version(project: &str, mc: &str, loader: &str) -> Result<Version> {
    let versions: Vec<Version> = client()?
        .get(format!("{API}/project/{project}/version"))
        .query(&[
            ("loaders", format!("[\"{loader}\"]")),
            ("game_versions", format!("[\"{mc}\"]")),
        ])
        .send()?
        .error_for_status()?
        .json()?;
    versions
        .into_iter()
        .find(|v| v.game_versions.iter().any(|x| x == mc) && v.loaders.iter().any(|x| x == loader))
        .ok_or_else(|| anyhow!("Modrinth 项目 {project} 没有兼容 {mc}/{loader} 的版本"))
}
fn file_matches(file: &VersionFile, path: &Path) -> Result<bool> {
    let metadata = match fs::symlink_metadata(path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(false),
        Err(error) => return Err(error.into()),
    };
    if metadata.file_type().is_symlink() {
        bail!("拒绝覆盖模组符号链接：{}", path.display());
    }
    if !metadata.is_file() {
        bail!("模组目标不是普通文件：{}", path.display());
    }
    if file.hashes.sha1.is_none() && file.hashes.sha512.is_none() {
        bail!(
            "Modrinth 文件未提供校验哈希，无法安全复用：{}",
            path.display()
        );
    }
    let mut input = File::open(path)?;
    let mut sha1 = Sha1::new();
    let mut sha512 = Sha512::new();
    let mut buf = [0; 65536];
    loop {
        let n = input.read(&mut buf)?;
        if n == 0 {
            break;
        }
        sha1.update(&buf[..n]);
        sha512.update(&buf[..n]);
    }
    let sha1 = format!("{:x}", sha1.finalize());
    let sha512 = format!("{:x}", sha512.finalize());
    Ok(file
        .hashes
        .sha1
        .as_ref()
        .is_none_or(|expected| expected.eq_ignore_ascii_case(&sha1))
        && file
            .hashes
            .sha512
            .as_ref()
            .is_none_or(|expected| expected.eq_ignore_ascii_case(&sha512)))
}

/// Returns true when a new file was downloaded and false when the existing
/// ordinary file already matches a Modrinth hash. Mismatches are never replaced.
fn download_mod_as(file: &VersionFile, mods: &Path, output_name: &str) -> Result<bool> {
    crate::model::no_symlinks(mods)?;
    let name = safe_name(output_name)?;
    if file.hashes.sha1.is_none() && file.hashes.sha512.is_none() {
        bail!("Modrinth 文件没有校验哈希，拒绝下载：{name}");
    }
    let parsed = url::Url::parse(&file.url)?;
    if parsed.scheme() != "https"
        || !matches!(
            parsed.host_str(),
            Some("cdn.modrinth.com" | "cdn-raw.modrinth.com")
        )
    {
        bail!("拒绝非 Modrinth CDN 文件地址");
    }
    let dest = mods.join(name);
    if dest.exists() || fs::symlink_metadata(&dest).is_ok() {
        if file_matches(file, &dest)? {
            return Ok(false);
        }
        bail!(
            "已有模组内容与 Modrinth 文件不一致，拒绝覆盖：{}",
            dest.display()
        );
    }
    let mut response = client()?.get(&file.url).send()?.error_for_status()?;
    let temp = mods.join(format!(".{}.{}.part", name, std::process::id()));
    let result = (|| -> Result<()> {
        let mut out = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temp)?;
        let mut h1 = Sha1::new();
        let mut h512 = Sha512::new();
        let mut total = 0u64;
        let mut buf = [0; 65536];
        loop {
            let n = response.read(&mut buf)?;
            if n == 0 {
                break;
            }
            total += n as u64;
            if total > 512 * 1024 * 1024 {
                bail!("Modrinth 模组超过 512 MiB 限制");
            }
            out.write_all(&buf[..n])?;
            h1.update(&buf[..n]);
            h512.update(&buf[..n]);
        }
        out.sync_all()?;
        if file
            .hashes
            .sha1
            .as_ref()
            .is_some_and(|expected| format!("{:x}", h1.finalize()) != *expected)
        {
            bail!("模组 SHA-1 校验失败：{name}");
        }
        if file
            .hashes
            .sha512
            .as_ref()
            .is_some_and(|expected| format!("{:x}", h512.finalize()) != *expected)
        {
            bail!("模组 SHA-512 校验失败：{name}");
        }
        fs::hard_link(&temp, &dest).or_else(|error| {
            if error.kind() == std::io::ErrorKind::AlreadyExists {
                Err(error)
            } else {
                fs::rename(&temp, &dest)
            }
        })?;
        fs::remove_file(&temp)?;
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temp);
    }
    result.map(|()| true)
}

fn validate_server_support(project: &Project) -> Result<()> {
    match project.server_side.as_str() {
        "unsupported" => bail!("{} 标记为不支持服务端", project.title),
        "unknown" => bail!("{} 的服务端兼容性未知，拒绝自动安装或更新", project.title),
        _ => Ok(()),
    }
}

/// Resolve and install required project or exact-version dependencies. Dependency
/// files already present are accepted only when their published hashes match.
fn install_required_dependencies(
    mods: &Path,
    dependencies: Vec<Dependency>,
    mc: &str,
    loader: &str,
    root_project: &str,
) -> Result<Vec<String>> {
    let mut queue = VecDeque::new();
    for dependency in dependencies
        .into_iter()
        .filter(|d| d.dependency_type == "required")
    {
        if let Some(version_id) = dependency.version_id {
            let exact: Version = client()?
                .get(format!("{API}/version/{version_id}"))
                .send()?
                .error_for_status()?
                .json()?;
            queue.push_back((exact.project_id, Some(version_id)));
        } else if let Some(project_id) = dependency.project_id {
            queue.push_back((project_id, None));
        }
    }
    let mut seen = HashSet::new();
    let mut report = Vec::new();
    while let Some((project_id, exact_version_id)) = queue.pop_front() {
        if project_id == root_project || !seen.insert(project_id.clone()) {
            continue;
        }
        let project =
            get_project(&project_id).with_context(|| format!("读取必需依赖失败：{project_id}"))?;
        validate_server_support(&project)?;
        let version = if let Some(version_id) = exact_version_id {
            let version: Version = client()?
                .get(format!("{API}/version/{version_id}"))
                .send()?
                .error_for_status()?
                .json()?;
            if version.project_id != project.id
                || !version.game_versions.iter().any(|v| v == mc)
                || !version.loaders.iter().any(|v| v == loader)
            {
                bail!("Modrinth 必需依赖版本 {version_id} 与项目/游戏/loader 不匹配");
            }
            version
        } else {
            select_version(&project.id, mc, loader)?
        };
        let file = version
            .files
            .iter()
            .find(|f| f.primary)
            .or(version.files.first())
            .ok_or_else(|| anyhow!("必需依赖 {} 没有下载文件", project.title))?;
        let downloaded = download_mod_as(file, mods, &file.filename)?;
        report.push(if downloaded {
            format!(
                "已安装必需依赖 {} {}",
                project.title, version.version_number
            )
        } else {
            format!(
                "必需依赖已存在且哈希匹配：{} {}",
                project.title, version.version_number
            )
        });
        for dep in version
            .dependencies
            .into_iter()
            .filter(|d| d.dependency_type == "required")
        {
            if let Some(version_id) = dep.version_id {
                let exact: Version = client()?
                    .get(format!("{API}/version/{version_id}"))
                    .send()?
                    .error_for_status()?
                    .json()?;
                queue.push_back((exact.project_id, Some(version_id)));
            } else if let Some(project_id) = dep.project_id {
                queue.push_back((project_id, None));
            }
        }
    }
    Ok(report)
}

/// Install a Modrinth project after its required dependencies are available.
pub fn install(server_dir: &Path, project: &str, mc: &str, loader: &str) -> Result<Vec<String>> {
    let mods = server_dir.join("mods");
    crate::model::no_symlinks(&mods)?;
    fs::create_dir_all(&mods)?;
    let metadata =
        get_project(project).with_context(|| format!("读取 Modrinth 项目失败：{project}"))?;
    validate_server_support(&metadata)?;
    let version = select_version(&metadata.id, mc, loader)?;
    let file = version
        .files
        .iter()
        .find(|f| f.primary)
        .or(version.files.first())
        .ok_or_else(|| anyhow!("{} 版本没有下载文件", metadata.title))?;
    let mut report = Vec::new();
    if metadata.server_side == "optional" {
        report.push(format!(
            "{} 服务端支持为 optional（客户端支持：{}），请确认",
            metadata.title, metadata.client_side
        ));
    }
    report.extend(install_required_dependencies(
        &mods,
        version.dependencies.clone(),
        mc,
        loader,
        &metadata.id,
    )?);
    if download_mod_as(file, &mods, &file.filename)? {
        report.push(format!(
            "已安装 {} {}",
            metadata.title, version.version_number
        ));
    } else {
        report.push(format!(
            "项目文件已存在且哈希匹配：{} {}",
            metadata.title, version.version_number
        ));
    }
    Ok(report)
}

/// Update installed Modrinth-tracked jars. Each old file is moved into a
/// private in-instance backup directory before an atomic replacement; jars
/// absent from Modrinth's hash index remain untouched.
pub fn update(server_dir: &Path, mc: &str, loader: &str) -> Result<Vec<String>> {
    let mods = server_dir.join("mods");
    crate::model::no_symlinks(&mods)?;
    if !mods.is_dir() {
        return Ok(vec!["没有已安装模组".into()]);
    }
    let entries: Vec<_> = fs::read_dir(&mods)?.collect::<std::io::Result<Vec<_>>>()?;
    let mut report = Vec::new();
    for entry in entries {
        let path = entry.path();
        let metadata = fs::symlink_metadata(&path)?;
        if metadata.file_type().is_symlink() {
            if path.extension().and_then(|x| x.to_str()) == Some("jar") {
                bail!("拒绝更新符号链接模组：{}", path.display());
            }
            continue;
        }
        if !metadata.is_file() || path.extension().and_then(|x| x.to_str()) != Some("jar") {
            continue;
        }
        let filename = entry.file_name().to_string_lossy().into_owned();
        let mut file = File::open(&path)?;
        let mut hash = Sha1::new();
        let mut buf = [0; 65536];
        loop {
            let n = file.read(&mut buf)?;
            if n == 0 {
                break;
            }
            hash.update(&buf[..n]);
        }
        let sha1 = format!("{:x}", hash.finalize());
        let response = client()?
            .get(format!("{API}/version_file/{sha1}"))
            .query(&[("algorithm", "sha1")])
            .send()?;
        if response.status() == reqwest::StatusCode::NOT_FOUND {
            report.push(format!("未在 Modrinth 登记，保留：{filename}"));
            continue;
        }
        let tracked: Version = response
            .error_for_status()?
            .json()
            .with_context(|| format!("解析 Modrinth 文件索引失败：{filename}"))?;
        let project = get_project(&tracked.project_id)?;
        validate_server_support(&project)?;
        let latest = select_version(&tracked.project_id, mc, loader)?;
        if latest.id == tracked.id {
            report.push(format!("已是最新：{filename}"));
            continue;
        }
        let replacement = latest
            .files
            .iter()
            .find(|f| f.primary)
            .or(latest.files.first())
            .ok_or_else(|| anyhow!("更新版本没有下载文件：{}", project.title))?;
        let backup_dir = mods.join(".mcsrv-backups");
        crate::model::no_symlinks(&backup_dir)?;
        let backup = backup_dir.join(format!("{}-{}", tracked.id, filename));
        if backup.exists() {
            bail!("更新备份已存在，拒绝覆盖：{}", backup.display());
        }
        report.extend(install_required_dependencies(
            &mods,
            latest.dependencies.clone(),
            mc,
            loader,
            &project.id,
        )?);
        let staged_name = format!(
            ".mcsrv-update-{}-{}",
            std::process::id(),
            safe_name(&replacement.filename)?
        );
        let staged_downloaded = download_mod_as(replacement, &mods, &staged_name)?;
        fs::create_dir_all(&backup_dir)?;
        fs::rename(&path, &backup)?;
        let staged = mods.join(&staged_name);
        let new_path = mods.join(safe_name(&replacement.filename)?);
        let target_exists = fs::symlink_metadata(&new_path).is_ok();
        let target_is_existing_matching = target_exists && file_matches(replacement, &new_path)?;
        if target_exists && !target_is_existing_matching {
            let _ = fs::rename(&backup, &path);
            let _ = fs::remove_file(&staged);
            bail!(
                "更新文件名已存在且哈希不同，拒绝覆盖：{}",
                new_path.display()
            );
        }
        if staged_downloaded {
            if let Err(error) = fs::rename(staged, &new_path) {
                let _ = fs::rename(&backup, &path);
                return Err(error).context("更新安装失败，已尝试还原旧 JAR");
            }
        } else if target_is_existing_matching {
            fs::remove_file(staged)?;
        } else {
            fs::rename(staged, &new_path)?;
        }
        report.push(format!(
            "已更新 {} {} → {}（旧文件保存在 mods/.mcsrv-backups/）",
            project.title, tracked.version_number, latest.version_number
        ));
    }
    Ok(report)
}

/// Compare installed jar names to a Prism instance; all unknown metadata remains visible.
pub fn diff(server_dir: &Path, prism: &Path) -> Result<Vec<String>> {
    let hashes = |p: &Path| -> Result<std::collections::HashMap<String, String>> {
        let mut found = std::collections::HashMap::new();
        if p.exists() {
            for e in fs::read_dir(p)? {
                let e = e?;
                let path = e.path();
                if !path.is_file() || path.extension().and_then(|x| x.to_str()) != Some("jar") {
                    continue;
                }
                let mut f = File::open(&path)?;
                let mut hasher = Sha1::new();
                let mut buf = [0; 65536];
                loop {
                    let n = f.read(&mut buf)?;
                    if n == 0 {
                        break;
                    }
                    hasher.update(&buf[..n]);
                }
                found.insert(
                    e.file_name().to_string_lossy().to_lowercase(),
                    format!("{:x}", hasher.finalize()),
                );
            }
        }
        Ok(found)
    };
    let server = hashes(&server_dir.join("mods"))?;
    let prism_root = if prism.join(".minecraft").is_dir() {
        prism.join(".minecraft")
    } else if prism.join("minecraft").is_dir() {
        prism.join("minecraft")
    } else {
        prism.to_path_buf()
    };
    let client = hashes(&prism_root.join("mods"))?;
    let server_names: HashSet<_> = server.keys().cloned().collect();
    let client_names: HashSet<_> = client.keys().cloned().collect();
    let mut out = Vec::new();
    for n in server_names.difference(&client_names) {
        out.push(format!("仅服务端：{n}"));
    }
    for n in client_names.difference(&server_names) {
        out.push(format!("仅 Prism 客户端：{n}"));
    }
    for n in server_names.intersection(&client_names) {
        if server.get(n) != client.get(n) {
            out.push(format!("同名但内容不同：{n}"));
        }
    }
    if out.is_empty() {
        out.push("文件名与 SHA-1 内容均相同；模组 loader 兼容性仍需元数据核验。".into());
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn prism_path_guard_rejects_escape() {
        assert!(safe_rel("../mods/x.jar").is_err());
        assert!(safe_rel("C:/x.jar").is_err());
    }
    #[test]
    fn modrinth_filename_must_be_flat() {
        assert!(safe_name("../evil.jar").is_err());
        assert!(safe_name("ok.jar").is_ok());
    }
    #[test]
    fn matching_hash_allows_reuse_but_mismatch_does_not() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("mod.jar");
        fs::write(&path, b"known jar bytes").unwrap();
        let digest = format!("{:x}", Sha1::digest(b"known jar bytes"));
        let expected = VersionFile {
            url: "https://cdn.modrinth.com/file.jar".into(),
            filename: "mod.jar".into(),
            primary: true,
            hashes: Hashes {
                sha1: Some(digest),
                sha512: None,
            },
        };
        assert!(file_matches(&expected, &path).unwrap());
        let mismatch = VersionFile {
            hashes: Hashes {
                sha1: Some("00".repeat(20)),
                sha512: None,
            },
            ..expected
        };
        assert!(!file_matches(&mismatch, &path).unwrap());
    }
}
