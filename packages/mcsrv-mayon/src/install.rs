//! Server installers for official Minecraft, Paper, Fabric, Forge, NeoForge,
//! Modrinth mrpack archives and official GTNH server packs.
use anyhow::{anyhow, bail, Context, Result};
use reqwest::blocking::{Client, Response};
use serde::Deserialize;
use sha1::{Digest as _, Sha1};
use sha2::{Sha256, Sha512};
use std::{
    fs::{self, File, OpenOptions},
    io::{Read, Write},
    path::{Component, Path, PathBuf},
    time::Duration,
};
use zip::ZipArchive;

const USER_AGENT: &str = "mayon/mcsrv-mayon/0.1.0 (https://github.com/mayon/nix-dotfiles)";
const MAX_ARCHIVE_BYTES: u64 = 2 * 1024 * 1024 * 1024;
const MAX_UNPACKED_BYTES: u64 = 8 * 1024 * 1024 * 1024;
const MAX_ENTRIES: usize = 100_000;

fn client() -> Result<Client> {
    Ok(Client::builder()
        .user_agent(USER_AGENT)
        .connect_timeout(Duration::from_secs(15))
        .timeout(Duration::from_secs(180))
        .build()?)
}
fn get(url: &str) -> Result<Response> {
    let response = client()?
        .get(url)
        .send()
        .with_context(|| format!("下载请求失败：{url}"))?;
    if !response.status().is_success() {
        bail!("下载失败 {}：{}", response.status(), url);
    }
    Ok(response)
}
fn json<T: for<'de> Deserialize<'de>>(url: &str) -> Result<T> {
    let response = get(url)?;
    response
        .json()
        .with_context(|| format!("无法解析 API 响应：{url}"))
}
fn safe_rel(name: &str) -> Result<PathBuf> {
    let path = Path::new(name);
    if path.as_os_str().is_empty()
        || path.is_absolute()
        || name.contains('\\')
        || name.contains(':')
    {
        bail!("压缩包包含非法路径：{name}");
    }
    let mut out = PathBuf::new();
    for c in path.components() {
        match c {
            Component::Normal(x) => out.push(x),
            Component::CurDir => {}
            _ => bail!("压缩包路径越界：{name}"),
        }
    }
    if out.as_os_str().is_empty() {
        bail!("压缩包包含空路径");
    }
    Ok(out)
}
fn ensure_empty(dir: &Path) -> Result<()> {
    fs::create_dir_all(dir)?;
    if fs::read_dir(dir)?.next().is_some() {
        bail!("目标目录非空，拒绝覆盖：{}", dir.display());
    }
    Ok(())
}
fn download_file(
    url: &str,
    dst: &Path,
    sha1: Option<&str>,
    sha512: Option<&str>,
    sha256: Option<&str>,
) -> Result<()> {
    if dst.exists() {
        bail!("目标文件已存在，拒绝覆盖：{}", dst.display());
    }
    let parent = dst.parent().ok_or_else(|| anyhow!("目标路径没有父目录"))?;
    fs::create_dir_all(parent)?;
    let mut response = get(url)?;
    if response
        .content_length()
        .is_some_and(|n| n > MAX_ARCHIVE_BYTES)
    {
        bail!("下载超过大小上限");
    }
    let temp = parent.join(format!(
        ".mcsrv-download-{}-{}",
        std::process::id(),
        rand_suffix()
    ));
    let result = (|| -> Result<()> {
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temp)?;
        let mut h1 = Sha1::new();
        let mut h512 = Sha512::new();
        let mut h256 = Sha256::new();
        let mut size = 0u64;
        let mut buf = [0u8; 65536];
        loop {
            let n = response.read(&mut buf)?;
            if n == 0 {
                break;
            }
            size += n as u64;
            if size > MAX_ARCHIVE_BYTES {
                bail!("下载超过大小上限");
            }
            file.write_all(&buf[..n])?;
            h1.update(&buf[..n]);
            h512.update(&buf[..n]);
            h256.update(&buf[..n]);
        }
        file.sync_all()?;
        if let Some(expected) = sha1 {
            if format!("{:x}", h1.finalize()) != expected.to_ascii_lowercase() {
                bail!("SHA-1 校验失败");
            }
        }
        if let Some(expected) = sha512 {
            if format!("{:x}", h512.finalize()) != expected.to_ascii_lowercase() {
                bail!("SHA-512 校验失败");
            }
        }
        if let Some(expected) = sha256 {
            if format!("{:x}", h256.finalize()) != expected.to_ascii_lowercase() {
                bail!("SHA-256 校验失败");
            }
        }
        fs::hard_link(&temp, dst).or_else(|e| {
            if e.kind() == std::io::ErrorKind::AlreadyExists {
                Err(e)
            } else {
                fs::rename(&temp, dst)
            }
        })?;
        fs::remove_file(&temp)?;
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temp);
    }
    result
}
fn rand_suffix() -> String {
    format!(
        "{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos()
    )
}
fn extract_zip(zip_path: &Path, root: &Path, allow_overwrite: bool) -> Result<Vec<String>> {
    let file = File::open(zip_path)?;
    let mut archive = ZipArchive::new(file).context("无效 ZIP 文件")?;
    if archive.len() > MAX_ENTRIES {
        bail!("压缩包文件数量超过限制");
    }
    let mut total = 0u64;
    let mut report = Vec::new();
    for i in 0..archive.len() {
        let mut entry = archive.by_index(i)?;
        let rel = safe_rel(entry.name())?;
        if entry.unix_mode().is_some_and(|m| m & 0o170000 == 0o120000) {
            bail!("压缩包含符号链接：{}", entry.name());
        }
        let dst = root.join(&rel);
        if entry.is_dir() {
            fs::create_dir_all(&dst)?;
            continue;
        }
        total = total.saturating_add(entry.size());
        if total > MAX_UNPACKED_BYTES {
            bail!("解压内容超过限制");
        }
        if let Some(parent) = dst.parent() {
            fs::create_dir_all(parent)?;
        }
        if !allow_overwrite && dst.exists() {
            bail!("解压会覆盖已有文件：{}", dst.display());
        }
        let mut out = OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(allow_overwrite)
            .create_new(!allow_overwrite)
            .open(&dst)?;
        std::io::copy(&mut entry, &mut out)?;
        report.push(rel.display().to_string());
    }
    Ok(report)
}
fn validate_origin(url: &str, allowed: &[&str]) -> Result<()> {
    let u = url::Url::parse(url)?;
    if u.scheme() != "https" || !allowed.iter().any(|h| u.host_str() == Some(h)) {
        bail!("下载地址不在允许的官方域名范围内：{url}");
    }
    Ok(())
}

#[derive(Deserialize)]
struct Manifest {
    versions: Vec<ManifestVersion>,
    latest: ManifestLatest,
}
#[derive(Deserialize)]
struct ManifestLatest {
    release: String,
}
#[derive(Deserialize)]
struct ManifestVersion {
    id: String,
    url: String,
}
#[derive(Deserialize)]
struct VersionDetails {
    downloads: Downloads,
}
#[derive(Deserialize)]
struct Downloads {
    server: Option<Download>,
}
#[derive(Deserialize)]
struct Download {
    url: String,
    sha1: String,
}
fn vanilla_url(version: &str) -> Result<(String, String)> {
    let m: Manifest = json("https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")?;
    let v = m
        .versions
        .iter()
        .find(|v| v.id == version)
        .ok_or_else(|| anyhow!("Mojang 未知版本：{version}"))?;
    let d: VersionDetails = json(&v.url)?;
    let server = d
        .downloads
        .server
        .ok_or_else(|| anyhow!("Minecraft {version} 没有服务端文件"))?;
    Ok((server.url, server.sha1))
}
fn install_vanilla(dir: &Path, version: &str) -> Result<Vec<String>> {
    let (url, hash) = vanilla_url(version)?;
    download_file(&url, &dir.join("server.jar"), Some(&hash), None, None)?;
    Ok(vec!["-jar".into(), "server.jar".into(), "nogui".into()])
}
fn install_paper(dir: &Path, requested: &str) -> Result<(Vec<String>, String)> {
    #[derive(Deserialize)]
    struct Project {
        versions: std::collections::HashMap<String, Vec<String>>,
    }
    #[derive(Deserialize)]
    struct Build {
        id: u64,
        channel: String,
        downloads: std::collections::HashMap<String, PaperArtifact>,
    }
    #[derive(Deserialize)]
    struct PaperArtifact {
        name: String,
        url: String,
        checksums: PaperChecksums,
    }
    #[derive(Deserialize)]
    struct PaperChecksums {
        sha256: String,
    }
    let client = Client::builder()
        .user_agent(USER_AGENT)
        .connect_timeout(Duration::from_secs(15))
        .timeout(Duration::from_secs(60))
        .build()?;
    let project: Project = client
        .get("https://fill.papermc.io/v3/projects/paper")
        .send()?
        .error_for_status()?
        .json()?;
    let mut versions: Vec<String> = project.versions.values().flatten().cloned().collect();
    versions.sort_by(|a, b| version_cmp(b, a));
    versions.dedup();
    if requested != "latest" && !versions.iter().any(|v| v == requested) {
        bail!("Paper 不支持 Minecraft {requested}");
    }
    let candidates: Vec<String> = if requested == "latest" {
        versions
    } else {
        vec![requested.to_owned()]
    };
    for version in candidates {
        let builds: Vec<Build> = client
            .get(format!(
                "https://fill.papermc.io/v3/projects/paper/versions/{version}/builds"
            ))
            .send()?
            .error_for_status()?
            .json()?;
        if let Some(build) = builds.iter().find(|b| b.channel == "STABLE") {
            let artifact = build
                .downloads
                .get("server:default")
                .ok_or_else(|| anyhow!("Paper stable build 缺少 server:default 文件"))?;
            validate_origin(&artifact.url, &["fill-data.papermc.io"])?;
            let name = safe_rel(&artifact.name)?;
            download_file(
                &artifact.url,
                &dir.join(&name),
                None,
                None,
                Some(&artifact.checksums.sha256),
            )?;
            let display = name.file_name().unwrap().to_string_lossy().into_owned();
            let argv = vec!["-jar".into(), display, "--nogui".into()];
            let _build_id = build.id;
            return Ok((argv, version));
        }
    }
    bail!("Paper 没有可用稳定 build")
}
fn version_cmp(a: &str, b: &str) -> std::cmp::Ordering {
    let parse = |s: &str| {
        s.split('.')
            .map(|x| x.parse::<u32>().unwrap_or(0))
            .collect::<Vec<_>>()
    };
    parse(a).cmp(&parse(b))
}

fn install_fabric(dir: &Path, mc: &str, requested_loader: Option<&str>) -> Result<Vec<String>> {
    #[derive(Deserialize)]
    struct Loader {
        loader: LoaderInfo,
    }
    #[derive(Deserialize)]
    struct LoaderInfo {
        version: String,
    }
    #[derive(Deserialize)]
    struct Installer {
        version: String,
        stable: bool,
    }
    let data: Vec<Loader> = json(&format!(
        "https://meta.fabricmc.net/v2/versions/loader/{mc}"
    ))?;
    let installers: Vec<Installer> = json("https://meta.fabricmc.net/v2/versions/installer")?;
    let installer = installers
        .iter()
        .find(|v| v.stable)
        .or_else(|| installers.first())
        .ok_or_else(|| anyhow!("Fabric 官方 API 未返回 installer 版本"))?
        .version
        .clone();
    let loader = requested_loader
        .map(str::to_owned)
        .or_else(|| data.first().map(|v| v.loader.version.clone()))
        .ok_or_else(|| anyhow!("Fabric 没有 Minecraft {mc} 的 loader"))?;
    let name = format!("fabric-server-mc-{mc}-loader-{loader}.jar");
    let url = format!(
        "https://meta.fabricmc.net/v2/versions/loader/{mc}/{loader}/{installer}/server/jar"
    );
    download_file(&url, &dir.join(&name), None, None, None)?;
    Ok(vec!["-jar".into(), name, "nogui".into()])
}
fn resolve_loader(kind: &str, mc: &str, selector: &str) -> Result<String> {
    if selector != "latest" && selector != "recommended" {
        return Ok(selector.to_owned());
    }
    if kind == "forge" {
        #[derive(Deserialize)]
        struct Promotions {
            promos: std::collections::HashMap<String, String>,
        }
        let p: Promotions =
            json("https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json")?;
        let key = format!(
            "{mc}-{}",
            if selector == "latest" {
                "latest"
            } else {
                "recommended"
            }
        );
        let loader = p
            .promos
            .get(&key)
            .ok_or_else(|| anyhow!("Forge {mc} 没有 {selector} promotion"))?;
        Ok(if mc == "1.7.10" {
            format!("{loader}-{mc}")
        } else {
            loader.clone()
        })
    } else {
        let url = "https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml";
        let text = get(url)?.text()?;
        let pieces: Vec<_> = mc.split('.').collect();
        let prefix = if pieces.first() == Some(&"1") {
            if pieces.len() < 2 {
                bail!("NeoForge Minecraft 版本不完整");
            }
            format!("{}.{}.", pieces[1], pieces.get(2).unwrap_or(&"0"))
        } else {
            format!(
                "{}.{}.{}.",
                pieces.first().unwrap_or(&"0"),
                pieces.get(1).unwrap_or(&"0"),
                pieces.get(2).unwrap_or(&"0")
            )
        };
        let mut versions: Vec<_> = text
            .split("<version>")
            .skip(1)
            .filter_map(|s| s.split_once("</version>").map(|(v, _)| v.trim()))
            .filter(|v| v.starts_with(&prefix))
            .filter(|v| selector == "latest" || !v.contains('-'))
            .collect();
        versions.sort_by(|a, b| version_cmp(b, a));
        versions.first().map(|s| s.to_string()).ok_or_else(|| {
            anyhow!("NeoForge 没有匹配 Minecraft {mc} 的 {selector} build；可显式 MC@loader")
        })
    }
}
fn install_forge_like(
    dir: &Path,
    kind: &str,
    mc: &str,
    loader: &str,
    java: &str,
) -> Result<Vec<String>> {
    let resolved = resolve_loader(kind, mc, loader)?;
    let version = if kind == "neoforge" || resolved.starts_with(mc) {
        resolved.clone()
    } else {
        format!("{mc}-{resolved}")
    };
    let (url, file, host) = if kind == "forge" {
        (format!("https://maven.minecraftforge.net/net/minecraftforge/forge/{version}/forge-{version}-installer.jar"), "forge-installer.jar", "maven.minecraftforge.net")
    } else {
        (format!("https://maven.neoforged.net/releases/net/neoforged/neoforge/{version}/neoforge-{version}-installer.jar"), "neoforge-installer.jar", "maven.neoforged.net")
    };
    validate_origin(&url, &[host])?;
    let installer = dir.join(file);
    download_file(&url, &installer, None, None, None)?;
    let status = std::process::Command::new(java)
        .args(["-jar", file, "--installServer"])
        .current_dir(dir)
        .status()
        .context("启动服务端安装器失败")?;
    if !status.success() {
        bail!("{kind} 服务端安装器退出码 {status}");
    }
    let args = if kind == "forge" {
        dir.join(format!(
            "libraries/net/minecraftforge/forge/{version}/unix_args.txt"
        ))
    } else {
        dir.join(format!(
            "libraries/net/neoforged/neoforge/{version}/unix_args.txt"
        ))
    };
    if args.is_file() {
        return Ok(vec![
            format!("@{}", args.strip_prefix(dir)?.display()),
            "nogui".into(),
        ]);
    }
    let universal = dir.join(format!("forge-{version}-universal.jar"));
    if kind == "forge" && universal.is_file() {
        return Ok(vec![
            "-jar".into(),
            universal
                .file_name()
                .unwrap()
                .to_string_lossy()
                .into_owned(),
            "nogui".into(),
        ]);
    }
    bail!(
        "{kind} 安装器完成，但没有发现 unix_args.txt 或受支持的服务端 jar；请检查 {}",
        dir.display()
    )
}

#[derive(Deserialize)]
struct PrismPack {
    components: Vec<PrismComponent>,
}
#[derive(Deserialize)]
struct PrismComponent {
    uid: String,
    version: String,
}

fn latest_mc() -> Result<String> {
    let m: Manifest = json("https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")?;
    Ok(m.latest.release)
}
#[derive(serde::Serialize)]
struct Installed {
    minecraft: String,
    loader: String,
    loader_version: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pack_version: Option<String>,
}
fn write_installed(dir: &Path, info: Installed) -> Result<()> {
    let path = dir.join("installed.json");
    let mut f = OpenOptions::new().write(true).create_new(true).open(path)?;
    serde_json::to_writer_pretty(&mut f, &info)?;
    f.write_all(b"\n")?;
    f.sync_all()?;
    Ok(())
}
fn prism_info(source: &Path, fallback_mc: &str) -> Result<Installed> {
    let path = if source.join("mmc-pack.json").is_file() {
        source.join("mmc-pack.json")
    } else {
        bail!("Prism 实例缺少 mmc-pack.json")
    };
    let pack: PrismPack = serde_json::from_slice(&fs::read(path)?)?;
    if pack
        .components
        .iter()
        .any(|c| c.uid.to_ascii_lowercase().contains("lwjgl3ify"))
    {
        bail!("检测到 lwjgl3ify Prism 客户端包；客户端 Forge 1.7.10 不能直接导出为服务端，请选择 GTNH 官方 Server ZIP");
    }
    let get = |uid: &str| {
        pack.components
            .iter()
            .find(|c| c.uid == uid)
            .map(|c| c.version.clone())
    };
    let minecraft = get("net.minecraft").unwrap_or_else(|| fallback_mc.to_owned());
    if let Some(v) = get("net.minecraftforge") {
        Ok(Installed {
            minecraft,
            loader: "forge".into(),
            loader_version: Some(v),
            pack_version: None,
        })
    } else if let Some(v) = get("net.fabricmc.fabric-loader") {
        Ok(Installed {
            minecraft,
            loader: "fabric".into(),
            loader_version: Some(v),
            pack_version: None,
        })
    } else if let Some(v) = get("net.neoforged").or_else(|| get("net.neoforged.neoforge")) {
        Ok(Installed {
            minecraft,
            loader: "neoforge".into(),
            loader_version: Some(v),
            pack_version: None,
        })
    } else {
        bail!("Prism 实例未声明可识别服务端 loader")
    }
}

/// Resolve metadata early so the caller can choose a matching JDK before running installers.
/// Returns `(loader_kind, minecraft_version)`; Forge loader versions remain in the input selector.
pub fn java_hint(kind: &str, version: &str, source: Option<&str>) -> Result<(String, String)> {
    match kind {
        "prism" => {
            let source = Path::new(source.ok_or_else(|| anyhow!("Prism 导入需要实例目录"))?);
            let info = prism_info(source, version)?;
            Ok((info.loader, info.minecraft))
        }
        "mrpack" => {
            let path = Path::new(source.ok_or_else(|| anyhow!("mrpack 需要本地文件路径"))?);
            let mut archive = ZipArchive::new(File::open(path).context("无法打开 mrpack 文件")?)?;
            let mut raw = String::new();
            archive
                .by_name("modrinth.index.json")
                .context("mrpack 缺少 modrinth.index.json")?
                .read_to_string(&mut raw)?;
            let index: MrIndex = serde_json::from_str(&raw)?;
            let mc = index
                .dependencies
                .get("minecraft")
                .and_then(|v| v.as_str())
                .ok_or_else(|| anyhow!("mrpack dependencies 缺少 minecraft 版本"))?;
            let loader = if index.dependencies.contains_key("fabric-loader") {
                "fabric"
            } else if index.dependencies.contains_key("forge") {
                "forge"
            } else if index.dependencies.contains_key("neoforge") {
                "neoforge"
            } else {
                bail!("mrpack 未声明 Fabric/Forge/NeoForge loader")
            };
            Ok((loader.into(), mc.into()))
        }
        "forge" | "neoforge" => Ok((
            kind.into(),
            version
                .split_once('@')
                .map_or(version, |(mc, _)| mc)
                .to_owned(),
        )),
        _ => Ok((kind.into(), version.to_owned())),
    }
}

fn install_prism(
    dir: &Path,
    fallback_version: &str,
    java: &str,
    source: &Path,
) -> Result<Vec<String>> {
    let info = prism_info(source, fallback_version)?;
    let loader = info.loader_version.as_deref().unwrap_or("");
    let argv = match info.loader.as_str() {
        "fabric" => install_fabric(dir, &info.minecraft, Some(loader))?,
        _ => install_forge_like(dir, &info.loader, &info.minecraft, loader, java)?,
    };
    let report = super::mods::import_prism(source, dir)?;
    crate::model::write_private(&dir.join("import-report.txt"), report.join("\n").as_bytes())?;
    write_installed(dir, info)?;
    Ok(argv)
}

#[derive(Deserialize)]
struct MrIndex {
    files: Vec<MrFile>,
    dependencies: serde_json::Map<String, serde_json::Value>,
}
#[derive(Deserialize)]
struct MrFile {
    path: String,
    hashes: Hashes,
    downloads: Vec<String>,
    env: Option<MrEnv>,
}
#[derive(Deserialize)]
struct Hashes {
    sha1: Option<String>,
    sha512: Option<String>,
}
#[derive(Deserialize)]
struct MrEnv {
    server: Option<String>,
}
fn install_mrpack(dir: &Path, path: &Path, java: &str) -> Result<Vec<String>> {
    let mut z = ZipArchive::new(File::open(path)?)?;
    let mut index = String::new();
    z.by_name("modrinth.index.json")
        .context("mrpack 缺少 modrinth.index.json")?
        .read_to_string(&mut index)?;
    let format: serde_json::Value = serde_json::from_str(&index)?;
    if format["formatVersion"] != 1 || format["game"] != "minecraft" {
        bail!("仅支持 Minecraft mrpack formatVersion=1");
    }
    let manifest: MrIndex = serde_json::from_str(&index)?;
    if manifest.files.len() > MAX_ENTRIES {
        bail!("mrpack 文件数超限");
    }
    let mc = manifest
        .dependencies
        .get("minecraft")
        .and_then(|v| v.as_str())
        .ok_or_else(|| anyhow!("mrpack dependencies 缺少 minecraft 版本"))?;
    let loader_pair = ["fabric-loader", "forge", "neoforge"]
        .into_iter()
        .find_map(|key| {
            manifest
                .dependencies
                .get(key)
                .and_then(|v| v.as_str())
                .map(|version| (key, version))
        });
    let (loader_id, loader_version) =
        loader_pair.ok_or_else(|| anyhow!("mrpack 未声明 Fabric/Forge/NeoForge loader"))?;
    let argv = match loader_id {
        "fabric-loader" => install_fabric(dir, mc, Some(loader_version))?,
        "forge" => install_forge_like(dir, "forge", mc, loader_version, java)?,
        _ => install_forge_like(dir, "neoforge", mc, loader_version, java)?,
    };
    let mut downloaded = 0u64;
    for f in manifest.files {
        if f.env.as_ref().and_then(|e| e.server.as_deref()) == Some("unsupported") {
            continue;
        }
        let rel = safe_rel(&f.path)?;
        let dst = dir.join(rel);
        let url = f
            .downloads
            .first()
            .ok_or_else(|| anyhow!("mrpack 文件没有下载地址：{}", f.path))?;
        validate_origin(url, &["cdn.modrinth.com", "cdn-raw.modrinth.com"])?;
        download_file(
            url,
            &dst,
            f.hashes.sha1.as_deref(),
            f.hashes.sha512.as_deref(),
            None,
        )?;
        downloaded += fs::metadata(&dst)?.len();
        if downloaded > MAX_UNPACKED_BYTES {
            bail!("mrpack 下载总大小超限");
        }
    }
    extract_mrpack_layers(path, dir)?;
    Ok(argv)
}
fn extract_mrpack_layers(path: &Path, dir: &Path) -> Result<()> {
    let mut archive = ZipArchive::new(File::open(path)?)?;
    if archive.len() > MAX_ENTRIES {
        bail!("mrpack ZIP 文件数超限");
    }
    let mut total = 0u64;
    for prefix in ["overrides", "server-overrides"] {
        let mut seen = std::collections::HashSet::new();
        for i in 0..archive.len() {
            let mut entry = archive.by_index(i)?;
            let rel = safe_rel(entry.name())?;
            let Ok(rest) = rel.strip_prefix(prefix) else {
                continue;
            };
            if rest.as_os_str().is_empty() {
                continue;
            }
            if !seen.insert(rest.to_path_buf()) {
                bail!("mrpack overrides 存在重复路径");
            }
            if entry.unix_mode().is_some_and(|m| m & 0o170000 == 0o120000) {
                bail!("mrpack overrides 含符号链接");
            }
            let dst = dir.join(rest);
            crate::model::no_symlinks(&dst)?;
            if entry.is_dir() {
                fs::create_dir_all(&dst)?;
                continue;
            }
            total = total
                .checked_add(entry.size())
                .ok_or_else(|| anyhow!("mrpack 大小溢出"))?;
            if total > MAX_UNPACKED_BYTES {
                bail!("mrpack 解压总大小超限");
            }
            if let Some(parent) = dst.parent() {
                fs::create_dir_all(parent)?;
            }
            let mut temporary = tempfile::NamedTempFile::new_in(dst.parent().unwrap())?;
            let expected = entry.size();
            let actual = std::io::copy(
                &mut entry
                    .by_ref()
                    .take(MAX_UNPACKED_BYTES - total + expected + 1),
                &mut temporary,
            )?;
            if actual != expected {
                bail!("mrpack 文件大小与ZIP声明不匹配");
            }
            temporary.persist(&dst)?;
        }
    }
    Ok(())
}
fn install_gtnh(dir: &Path, version: &str) -> Result<Vec<String>> {
    if !version
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || ".-_".contains(c))
    {
        bail!("非法 GTNH 版本号");
    }
    let filename = format!("GT_New_Horizons_{version}_Server_Java_17-26.zip");
    let section = if version.contains("beta") || version.contains("RC") || version.contains("rc") {
        "ServerPacks/betas"
    } else {
        "ServerPacks"
    };
    let url = format!("https://downloads.gtnewhorizons.com/{section}/{filename}");
    let archive = dir.join(".gtnh-server.zip");
    download_file(&url, &archive, None, None, None)?;
    extract_zip(&archive, dir, false)?;
    fs::remove_file(archive)?;
    if dir.join("java9args.txt").is_file() && dir.join("lwjgl3ify-forgePatches.jar").is_file() {
        return Ok(vec![
            "-Dfml.readTimeout=180".into(),
            "-Duser.language=en".into(),
            "@java9args.txt".into(),
            "-jar".into(),
            "lwjgl3ify-forgePatches.jar".into(),
            "nogui".into(),
        ]);
    }
    for script in ["startserver-java9.sh", "startserver-java9"] {
        if dir.join(script).is_file() {
            bail!("GTNH 包提供 {script}；需要检查包内启动脚本的 restart/参数逻辑后才能自动托管。暂支持可识别的 lwjgl3ify java9args 启动布局。");
        }
    }
    bail!("GTNH 服务端包缺少可识别的 lwjgl3ify java9args/forgePatches 布局")
}

/// Install selected server software into an empty instance directory.
/// `source` is a local Prism instance path, mrpack path, or optional Forge
/// loader selector. GTNH archives are derived from the official version history.
pub fn install(
    dir: &Path,
    kind: &str,
    version: &str,
    java: &str,
    source: Option<&str>,
) -> Result<Vec<String>> {
    ensure_empty(dir)?;
    let mut resolved_version = version.to_owned();
    let argv = match kind {
        "vanilla" => {
            if version == "latest" {
                resolved_version = latest_mc()?;
            }
            install_vanilla(dir, &resolved_version)?
        }
        "paper" => {
            let (argv, actual) = install_paper(dir, version)?;
            resolved_version = actual;
            argv
        }
        "fabric" => {
            if version == "latest" {
                resolved_version = latest_mc()?;
            }
            install_fabric(dir, &resolved_version, None)?
        }
        "forge" | "neoforge" => {
            let (mc, loader) = version
                .split_once('@')
                .unwrap_or((version, source.unwrap_or("recommended")));
            install_forge_like(dir, kind, mc, loader, java)?
        }
        "gtnh" => install_gtnh(dir, version)?,
        "mrpack" => install_mrpack(
            dir,
            Path::new(source.ok_or_else(|| anyhow!("mrpack 需要本地文件路径"))?),
            java,
        )?,
        "prism" => {
            return install_prism(
                dir,
                version,
                java,
                Path::new(source.ok_or_else(|| anyhow!("Prism 导入需要实例目录"))?),
            )
        }
        _ => bail!("不支持的服务端类型：{kind}"),
    };
    let info = match kind {
        "vanilla" => Installed {
            minecraft: resolved_version.clone(),
            loader: "vanilla".into(),
            loader_version: None,
            pack_version: None,
        },
        "paper" => Installed {
            minecraft: resolved_version.clone(),
            loader: "paper".into(),
            loader_version: None,
            pack_version: None,
        },
        "fabric" => {
            let mc = resolved_version.clone();
            let loader = argv
                .get(1)
                .and_then(|n| n.split("-loader-").nth(1))
                .and_then(|n| n.strip_suffix(".jar"))
                .map(str::to_owned);
            Installed {
                minecraft: mc,
                loader: "fabric".into(),
                loader_version: loader,
                pack_version: None,
            }
        }
        "forge" | "neoforge" => {
            let (mc, selector) = version
                .split_once('@')
                .unwrap_or((version, source.unwrap_or("recommended")));
            Installed {
                minecraft: mc.into(),
                loader: kind.into(),
                loader_version: Some(resolve_loader(kind, mc, selector)?),
                pack_version: None,
            }
        }
        "gtnh" => Installed {
            minecraft: "1.7.10".into(),
            loader: "forge".into(),
            loader_version: None,
            pack_version: Some(version.into()),
        },
        "mrpack" => {
            let path = Path::new(source.unwrap());
            let mut z = ZipArchive::new(File::open(path)?)?;
            let mut text = String::new();
            z.by_name("modrinth.index.json")?
                .read_to_string(&mut text)?;
            let m: MrIndex = serde_json::from_str(&text)?;
            let mc = m
                .dependencies
                .get("minecraft")
                .and_then(|v| v.as_str())
                .ok_or_else(|| anyhow!("mrpack 缺少 minecraft"))?
                .to_owned();
            let (loader_name, loader_version) = [
                ("fabric-loader", "fabric"),
                ("forge", "forge"),
                ("neoforge", "neoforge"),
            ]
            .into_iter()
            .find_map(|(k, l)| {
                m.dependencies
                    .get(k)
                    .and_then(|v| v.as_str())
                    .map(|v| (l, v.to_owned()))
            })
            .ok_or_else(|| anyhow!("mrpack 缺少 loader"))?;
            Installed {
                minecraft: mc,
                loader: loader_name.to_string(),
                loader_version: Some(loader_version),
                pack_version: None,
            }
        }
        _ => unreachable!(),
    };
    write_installed(dir, info)?;
    Ok(argv)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_zip_traversal() {
        assert!(safe_rel("../oops").is_err());
        assert!(safe_rel("/tmp/oops").is_err());
    }
    #[test]
    fn gtnh_version_name_is_bounded() {
        assert!("2.9.0-RC-2"
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || ".-_".contains(c)));
    }
}
