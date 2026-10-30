//! Strictly read-only libvirt metadata inventory. Image files are never opened.
use crate::{
    cleanup,
    vm_xml::{self, Node},
};
use std::{
    collections::{HashMap, HashSet},
    os::unix::fs::MetadataExt,
    path::{Path, PathBuf},
    process::Stdio,
    time::Duration,
};
use tokio::{io::AsyncWriteExt, process::Command};

pub const URIS: [&str; 2] = ["qemu:///session", "qemu:///system"];
#[derive(Debug, Clone)]
pub struct Row {
    pub uri: String,
    pub owner: String,
    pub kind: String,
    pub path: Option<PathBuf>,
    pub actual: Option<u64>,
    pub virtual_size: Option<u64>,
    pub note: String,
    identity: Option<(u64, u64)>,
}
impl Row {
    pub fn key(&self) -> String {
        format!("{}:{}:{}:{:?}", self.uri, self.owner, self.kind, self.path)
    }
    pub fn details(&self) -> String {
        format!("{} · {}\n{}\n路径：{}\n占用 {} · 虚拟 {}\n{}\n\nVM 严格只读：不可选、不可清理。\ny 复制完整路径 · Esc 返回", self.kind,self.owner,self.uri,self.path.as_ref().map(|p|p.display().to_string()).unwrap_or_else(||"—".into()),cleanup::bytes(self.actual),cleanup::bytes(self.virtual_size),self.note)
    }
}
#[derive(Debug, Clone)]
pub struct Connection {
    pub uri: String,
    pub status: String,
    pub complete: bool,
}
#[derive(Debug, Default, Clone)]
pub struct Inventory {
    pub rows: Vec<Row>,
    pub connections: Vec<Connection>,
}
impl Inventory {
    pub fn pending() -> Self {
        Self {
            rows: vec![],
            connections: URIS
                .iter()
                .map(|uri| Connection {
                    uri: (*uri).into(),
                    status: "等待只读查询".into(),
                    complete: false,
                })
                .collect(),
        }
    }
    pub fn summary(&self) -> String {
        let mut files: HashMap<String, (Option<u64>, Option<u64>, bool)> = HashMap::new();
        for row in &self.rows {
            let Some(path) = &row.path else {
                continue;
            };
            let identity = row
                .identity
                .map(|(d, i)| format!("inode:{d}:{i}"))
                .unwrap_or_else(|| format!("path:{}", path.display()));
            let sizes = files.entry(identity).or_default();
            sizes.0 = sizes.0.max(row.actual);
            if row.kind != "ISO" && row.kind != "快照内存" {
                sizes.2 = true;
                sizes.1 = sizes.1.max(row.virtual_size);
            }
        }
        let mut actual = 0u64;
        let mut capacity = 0u64;
        let mut unknown = 0;
        let mut virtual_unknown = 0;
        for (allocated, virtual_size, disk) in files.into_values() {
            if disk && virtual_size.is_none() {
                virtual_unknown += 1;
            }
            if let Some(n) = allocated {
                actual = actual.saturating_add(n);
            } else {
                unknown += 1;
            }
            capacity = capacity.saturating_add(virtual_size.unwrap_or(0));
        }
        let incomplete = self.connections.iter().any(|c| !c.complete);
        format!(
            "VM：已知占用 {} · 已知虚拟 {}{}{}",
            cleanup::bytes(Some(actual)),
            if virtual_unknown > 0 {
                format!(
                    "{} + {virtual_unknown}项未知",
                    cleanup::bytes(Some(capacity))
                )
            } else {
                cleanup::bytes(Some(capacity))
            },
            if unknown > 0 {
                format!(" · {unknown} 项大小未知")
            } else {
                String::new()
            },
            if incomplete {
                " · 统计不完整"
            } else {
                " · 文件去重"
            }
        )
    }
    pub fn cli(&self) -> String {
        let mut lines = vec!["VM 空间（严格只读）".into(), self.summary()];
        for c in &self.connections {
            lines.push(format!("{}：{}", c.uri, c.status));
        }
        for r in &self.rows {
            lines.push(format!(
                "{} · {} · {}\n路径：{}\n占用 {} · 虚拟 {}\n{}",
                r.uri,
                r.owner,
                r.kind,
                r.path
                    .as_ref()
                    .map(|p| p.display().to_string())
                    .unwrap_or_else(|| "—".into()),
                cleanup::bytes(r.actual),
                cleanup::bytes(r.virtual_size),
                r.note
            ));
        }
        lines.join("\n")
    }
}
async fn query(uri: &str, operation: &str, args: &[&str]) -> Result<String, String> {
    // There is no generic libvirt command entry point and no write connection.
    if !URIS.contains(&uri)
        || !matches!(
            operation,
            "list"
                | "domstate"
                | "dumpxml"
                | "snapshot-list"
                | "snapshot-dumpxml"
                | "pool-list"
                | "pool-dumpxml"
                | "vol-list"
                | "vol-path"
        )
    {
        return Err("只读查询白名单拒绝请求".into());
    }
    let output = tokio::time::timeout(
        Duration::from_secs(3),
        Command::new("virsh")
            .args(["--readonly", "--connect", uri, operation])
            .args(args)
            .env("LC_ALL", "C")
            .stdin(Stdio::null())
            .kill_on_drop(true)
            .output(),
    )
    .await
    .map_err(|_| "libvirt 只读查询超时".to_string())?
    .map_err(|e| {
        if e.kind() == std::io::ErrorKind::NotFound {
            "virsh 未安装；VM 查询不可用".to_string()
        } else {
            "无法启动 virsh 只读查询".to_string()
        }
    })?;
    if !output.status.success() {
        let error = String::from_utf8_lossy(&output.stderr).to_lowercase();
        return Err(
            if error.contains("permission")
                || error.contains("not authorized")
                || error.contains("authentication")
                || error.contains("access denied")
            {
                "无权限访问 libvirt；未提权".into()
            } else {
                format!("{operation} 不可用（未启用、连接失败或功能不支持）")
            },
        );
    }
    if output.stdout.len() > 4 * 1024 * 1024 {
        return Err("libvirt 元数据过大；未继续扫描".into());
    }
    String::from_utf8(output.stdout).map_err(|_| "libvirt 元数据不是 UTF-8".into())
}
fn canonical(path: &Path) -> PathBuf {
    path.canonicalize().unwrap_or_else(|_| path.to_path_buf())
}
fn metadata_row(
    uri: &str,
    owner: &str,
    kind: &str,
    path: Option<PathBuf>,
    virtual_size: Option<u64>,
    note: &str,
) -> Row {
    let has_path = path.is_some();
    let metadata = path
        .as_ref()
        .and_then(|p| std::fs::metadata(p).ok())
        .filter(|m| m.is_file());
    Row {
        uri: uri.into(),
        owner: owner.into(),
        kind: kind.into(),
        path,
        actual: metadata.as_ref().map(|m| m.blocks().saturating_mul(512)),
        virtual_size,
        note: if has_path && metadata.is_none() {
            format!("{note}；文件缺失、非普通文件或无 stat 权限，大小未知")
        } else {
            note.into()
        },
        identity: metadata.map(|m| (m.dev(), m.ino())),
    }
}
#[derive(Default)]
struct Census {
    rows: Vec<Row>,
    refs: HashSet<PathBuf>,
    dirs: HashSet<PathBuf>,
    volumes: Vec<Row>,
    warnings: HashSet<String>,
}
impl Census {
    fn warn(&mut self, reason: impl Into<String>) {
        self.warnings.insert(reason.into());
    }
    fn file(
        &mut self,
        uri: &str,
        owner: &str,
        kind: &str,
        path: PathBuf,
        capacity: Option<u64>,
        note: &str,
    ) {
        if !path.is_absolute() {
            self.warn("相对路径无法安全定位，未扫描");
            return;
        }
        let path = canonical(&path);
        self.refs.insert(path.clone());
        self.rows
            .push(metadata_row(uri, owner, kind, Some(path), capacity, note));
    }
}
async fn source_path(uri: &str, node: &Node) -> Result<Option<PathBuf>, String> {
    if let Some(file) = node.attr("file") {
        return Ok(Some(file.into()));
    }
    if let (Some(pool), Some(volume)) = (node.attr("pool"), node.attr("volume")) {
        return Ok(Some(
            query(uri, "vol-path", &["--pool", pool, "--vol", volume])
                .await?
                .trim()
                .into(),
        ));
    }
    Ok(None)
}
fn backing_complete(disk: &Node) -> bool {
    if disk.child("driver").and_then(|d| d.attr("type")) == Some("raw") {
        return true;
    }
    let Some(mut node) = disk.child("backingStore") else {
        return false;
    };
    loop {
        if node.child("source").is_none() && node.child("backingStore").is_none() {
            return true;
        }
        match node.child("backingStore") {
            Some(child) => node = child,
            None => return false,
        }
    }
}
async fn domain_disks(c: &mut Census, uri: &str, owner: &str, root: &Node, live: bool) {
    let Some(devices) = root.child("devices") else {
        return;
    };
    for disk in devices.children.iter().filter(|n| n.name == "disk") {
        let kind = if disk.attr("device") == Some("cdrom") {
            "ISO"
        } else {
            "磁盘"
        };
        if kind != "ISO" && !backing_complete(disk) {
            c.warn("backing 链未明确终止；未引用镜像只能待核实");
        }
        if let Some(source) = disk.child("source") {
            match source_path(uri, source).await {
                Ok(Some(path)) => {
                    // Only raw / ISO logical length is knowable without probing headers.
                    let plain = kind == "ISO"
                        || disk.child("driver").and_then(|d| d.attr("type")) == Some("raw")
                            && disk.descendants("encryption").is_empty()
                            && disk.descendants("slices").is_empty();
                    let capacity = plain
                        .then(|| {
                            std::fs::metadata(&path)
                                .ok()
                                .filter(|m| m.is_file())
                                .map(|m| m.len())
                        })
                        .flatten();
                    c.file(
                        uri,
                        owner,
                        kind,
                        path,
                        capacity,
                        if live {
                            if plain {
                                "当前 VM 引用；raw / ISO 虚拟大小取文件逻辑长度"
                            } else {
                                "当前 VM 引用；qcow2 虚拟大小未知：禁止读取镜像头"
                            }
                        } else {
                            "持久 VM 配置引用；只读保留"
                        },
                    );
                }
                Ok(None) => {
                    if source.attr("protocol").is_some() || source.attr("dev").is_some() {
                        c.rows.push(metadata_row(
                            uri,
                            owner,
                            "远程/块盘",
                            None,
                            None,
                            "非本地普通镜像；不读取内容，不计本地占用",
                        ));
                    }
                }
                Err(e) => c.warn(e),
            }
        }
        // Backing chains, dataStore and active mirrors are references too.
        for source in disk.descendants("source") {
            if disk
                .child("source")
                .is_some_and(|direct| std::ptr::eq(direct, source))
            {
                continue;
            }
            match source_path(uri, source).await {
                Ok(Some(path)) => c.file(
                    uri,
                    owner,
                    "依赖",
                    path,
                    None,
                    "backing / dataStore / mirror 引用",
                ),
                Ok(None) => (),
                Err(e) => c.warn(e),
            }
        }
        for mirror in disk.descendants("mirror") {
            if let Some(file) = mirror.attr("file") {
                c.file(uri, owner, "依赖", file.into(), None, "活动 mirror 引用");
            }
        }
    }
}
async fn snapshots(c: &mut Census, uri: &str, owner: &str, uuid: &str) {
    let list = match query(uri, "snapshot-list", &["--domain", uuid, "--name"]).await {
        Ok(s) => s,
        Err(e) => {
            c.warn(e);
            return;
        }
    };
    for name in list.lines().filter(|s| !s.trim().is_empty()).take(128) {
        let label = format!("{owner} / {name}");
        c.rows.push(metadata_row(
            uri,
            &label,
            "快照",
            None,
            None,
            "快照元数据；内部快照已包含在镜像中，不能单独计量",
        ));
        let result = match query(
            uri,
            "snapshot-dumpxml",
            &["--domain", uuid, "--snapshotname", name],
        )
        .await
        {
            Ok(xml) => vm_xml::parse(&xml),
            Err(e) => Err(e),
        };
        match result {
            Ok(root) => {
                for disk in root.descendants("disk") {
                    let local = disk
                        .child("source")
                        .is_some_and(|s| s.attr("file").is_some() || s.attr("pool").is_some());
                    let iso = disk.attr("device") == Some("cdrom")
                        || disk
                            .child("source")
                            .and_then(|s| s.attr("file"))
                            .is_some_and(|p| image_kind(Path::new(p)) == Some("ISO"));
                    if local && !iso && !backing_complete(disk) {
                        c.warn("快照 backing 链未明确终止；未引用镜像只能待核实");
                    }
                }
                // Snapshot domain XML includes older disks and backing chains too.
                for source in root.descendants("source") {
                    match source_path(uri, source).await {
                        Ok(Some(path)) => {
                            c.file(uri, &label, "快照磁盘", path, None, "快照引用（保留）")
                        }
                        Ok(None) => (),
                        Err(e) => c.warn(e),
                    }
                }
                if let Some(path) = root.child("memory").and_then(|m| m.attr("file")) {
                    c.file(
                        uri,
                        &label,
                        "快照内存",
                        path.into(),
                        None,
                        "外部快照内存（保留）",
                    );
                }
            }
            Err(e) => c.warn(e),
        }
    }
    if list.lines().count() > 128 {
        c.warn("快照列表超过128项，统计不完整");
    }
}
async fn pools(c: &mut Census, uri: &str) {
    let list = match query(uri, "pool-list", &["--all", "--name"]).await {
        Ok(s) => s,
        Err(e) => {
            c.warn(e);
            return;
        }
    };
    for pool in list.lines().filter(|s| !s.trim().is_empty()).take(128) {
        match query(uri, "pool-dumpxml", &["--pool", pool])
            .await
            .and_then(|s| vm_xml::parse(&s))
        {
            Ok(root) => {
                if matches!(root.attr("type"), Some("dir" | "fs" | "netfs")) {
                    if let Some(path) = root.child("target").and_then(|n| n.child("path")) {
                        let p = PathBuf::from(path.text.trim());
                        if p.is_absolute() {
                            c.dirs.insert(p);
                        }
                    }
                }
            }
            Err(e) => c.warn(e),
        }
        let volumes = match query(uri, "vol-list", &["--pool", pool]).await {
            Ok(v) => v,
            Err(e) => {
                c.warn(e);
                continue;
            }
        };
        let names = volume_paths(&volumes);
        if names.is_err() {
            c.warn("存储卷列表格式未知，统计不完整");
            continue;
        }
        for name in names.unwrap().iter().take(512) {
            let path = match query(uri, "vol-path", &["--pool", pool, "--vol", name]).await {
                Ok(p) => PathBuf::from(p.trim()),
                Err(e) => {
                    c.warn(e);
                    continue;
                }
            };
            if !path.is_absolute() {
                c.warn("存储卷路径不是本地绝对路径");
                continue;
            }
            let capacity = if image_kind(&path) == Some("ISO") {
                std::fs::metadata(&path)
                    .ok()
                    .filter(|m| m.is_file())
                    .map(|m| m.len())
            } else {
                None
            };
            c.volumes.push(metadata_row(
                uri,
                pool,
                "存储卷",
                Some(canonical(&path)),
                capacity,
                "libvirt 池登记；虚拟容量未知时禁止探测镜像头",
            ));
        }
        if volumes.lines().count() > 514 {
            c.warn("池卷超过512项，统计不完整");
        }
    }
    if list.lines().count() > 128 {
        c.warn("存储池超过128项，统计不完整");
    }
}
fn volume_paths(table: &str) -> Result<Vec<String>, String> {
    let mut paths = vec![];
    for line in table.lines().map(str::trim).filter(|s| !s.is_empty()) {
        if line.starts_with("Name") || line.chars().all(|c| c == '-') {
            continue;
        }
        // File volume paths are absolute; preserve spaces within the path.
        let (_, path) = line.split_once(" /").ok_or("volume path unavailable")?;
        paths.push(format!("/{path}"));
    }
    Ok(paths)
}
fn image_kind(path: &Path) -> Option<&'static str> {
    match path.extension()?.to_str()?.to_ascii_lowercase().as_str() {
        "iso" => Some("ISO"),
        "qcow" | "qcow2" | "img" | "raw" | "vmdk" | "vdi" | "vhd" | "vhdx" => Some("镜像"),
        _ => None,
    }
}
fn scan(c: &mut Census, uri: &str) {
    let mut todo: Vec<_> = c.dirs.iter().cloned().map(|p| (p, 0)).collect();
    let mut count = 0;
    while let Some((dir, depth)) = todo.pop() {
        let entries = match std::fs::read_dir(&dir) {
            Ok(es) => es,
            Err(_) => {
                c.warn("存储池目录无权限或不可读，扫描不完整");
                continue;
            }
        };
        for entry in entries {
            count += 1;
            if count > 10000 {
                c.warn("存储池扫描超过10000项，统计不完整");
                return;
            }
            let entry = match entry {
                Ok(e) => e,
                Err(_) => {
                    c.warn("存储池目录项不可读");
                    continue;
                }
            };
            let ty = match entry.file_type() {
                Ok(t) => t,
                Err(_) => {
                    c.warn("目录项类型未知");
                    continue;
                }
            };
            if ty.is_dir() {
                if depth < 4 {
                    todo.push((entry.path(), depth + 1));
                } else {
                    c.warn("存储池扫描深度超过4层，统计不完整");
                }
                continue;
            }
            // Do not traverse directory symlinks. File aliases are deduplicated by inode.
            if (ty.is_file() || ty.is_symlink()) && image_kind(&entry.path()).is_some() {
                c.volumes.push(metadata_row(
                    uri,
                    "存储池目录",
                    "扫描文件",
                    Some(canonical(&entry.path())),
                    None,
                    "仅按扩展名识别；stat，不读取镜像内容",
                ));
            }
        }
    }
}
async fn connection(uri: &str) -> (Census, Connection) {
    let mut c = Census::default();
    let list = match query(uri, "list", &["--all", "--uuid"]).await {
        Ok(s) => s,
        Err(reason) => {
            return (
                c,
                Connection {
                    uri: uri.into(),
                    status: reason,
                    complete: false,
                },
            )
        }
    };
    for uuid in list
        .lines()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .take(128)
    {
        if !uuid.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-') {
            c.warn("VM UUID 非法，未查询");
            continue;
        }
        let state = query(uri, "domstate", &["--domain", uuid])
            .await
            .unwrap_or_else(|_| "状态未知".into());
        let xml = query(uri, "dumpxml", &["--domain", uuid])
            .await
            .and_then(|s| vm_xml::parse(&s));
        let owner = xml
            .as_ref()
            .ok()
            .and_then(|n| n.child("name"))
            .map(|n| n.text.as_str())
            .unwrap_or(uuid);
        c.rows
            .push(metadata_row(uri, owner, "虚拟机", None, None, state.trim()));
        match &xml {
            Ok(root) => domain_disks(&mut c, uri, owner, root, true).await,
            Err(e) => c.warn(e.clone()),
        }
        match query(uri, "dumpxml", &["--domain", uuid, "--inactive"])
            .await
            .and_then(|s| vm_xml::parse(&s))
        {
            Ok(root) => domain_disks(&mut c, uri, owner, &root, false).await,
            Err(e) => c.warn(e),
        }
        snapshots(&mut c, uri, owner, uuid).await;
    }
    if list.lines().count() > 128 {
        c.warn("VM 超过128项，统计不完整");
    }
    pools(&mut c, uri).await;
    let scan_uri = uri.to_string();
    c = tokio::task::spawn_blocking(move || {
        scan(&mut c, &scan_uri);
        c
    })
    .await
    .unwrap_or_else(|_| {
        let mut failed = Census::default();
        failed.warn("存储池扫描失败");
        failed
    });
    let complete = c.warnings.is_empty();
    let mut warnings: Vec<_> = c.warnings.iter().cloned().collect();
    warnings.sort();
    let status = if complete {
        "只读连接可用".into()
    } else {
        format!("部分可用：{}", warnings.join("；"))
    };
    (
        c,
        Connection {
            uri: uri.into(),
            status,
            complete,
        },
    )
}
async fn bounded_connection(uri: &str) -> (Census, Connection) {
    tokio::time::timeout(Duration::from_secs(30), connection(uri))
        .await
        .unwrap_or_else(|_| {
            (
                Census::default(),
                Connection {
                    uri: uri.into(),
                    status: "只读查询超过30秒；本连接统计不可用".into(),
                    complete: false,
                },
            )
        })
}
pub async fn collect() -> Inventory {
    let (a, b) = tokio::join!(bounded_connection(URIS[0]), bounded_connection(URIS[1]));
    merge(vec![a, b])
}
fn merge(parts: Vec<(Census, Connection)>) -> Inventory {
    let all_complete = parts.iter().all(|(_, c)| c.complete);
    let refs: HashSet<_> = parts
        .iter()
        .flat_map(|(c, _)| c.refs.iter().cloned())
        .collect();
    let referenced_ids: HashSet<_> = parts
        .iter()
        .flat_map(|(c, _)| c.rows.iter().filter_map(|r| r.identity))
        .collect();
    let mut result = Inventory::default();
    let mut volumes = vec![];
    for (c, status) in parts {
        result.connections.push(status);
        result.rows.extend(c.rows);
        volumes.extend(c.volumes);
    }
    // Prefer sizes known from stat (ISO/raw) over extension-only scan rows.
    volumes.sort_by_key(|r| r.virtual_size.is_none());
    let mut known: HashSet<_> = result
        .rows
        .iter()
        .filter_map(|r| r.path.as_ref().map(|p| (r.uri.clone(), p.clone())))
        .collect();
    for mut volume in volumes {
        let Some(path) = &volume.path else {
            continue;
        };
        for row in result
            .rows
            .iter_mut()
            .filter(|r| r.path.as_ref() == Some(path))
        {
            if row.virtual_size.is_none() {
                row.virtual_size = volume.virtual_size;
            }
        }
        if !known.insert((volume.uri.clone(), path.clone())) {
            continue;
        }
        if image_kind(path) == Some("ISO") {
            volume.kind = "ISO".into();
            volume.note = if refs.contains(path) {
                "已知 VM 引用的 ISO；只显示/复制，不删除"
            } else {
                "未见已知 VM 引用的 ISO；只显示/复制，不删除"
            }
            .into();
        } else if refs.contains(path)
            || volume
                .identity
                .is_some_and(|id| referenced_ids.contains(&id))
        {
            volume.kind = "依赖".into();
            volume.note = "另一个 VM/快照/连接的引用，保留".into();
        } else if image_kind(path) == Some("镜像") {
            volume.kind = if all_complete {
                "孤立镜像候选"
            } else {
                "未引用待核实"
            }
            .into();
            volume.note = "仅已列 VM/快照/已知 backing 链的引用；绝不删除".into();
        } else {
            volume.kind = "存储卷".into();
        }
        result.rows.push(volume);
    }
    let mut dedup = HashSet::new();
    result.rows.retain(|r| dedup.insert(r.key()));
    result
        .rows
        .sort_by(|a, b| b.actual.cmp(&a.actual).then_with(|| a.key().cmp(&b.key())));
    for c in &result.connections {
        result.rows.push(metadata_row(
            &c.uri,
            "连接状态",
            "连接",
            None,
            None,
            &c.status,
        ));
    }
    result
}
pub async fn copy_path(path: &Path) -> Result<(), String> {
    // Only the path is passed; no shell, file open, VM mutation, or file manager.
    let mut child = Command::new("wl-copy")
        .args(["--type", "text/plain"])
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .kill_on_drop(true)
        .spawn()
        .map_err(|_| "wl-copy 不可用；完整路径见详情".to_string())?;
    let mut input = child.stdin.take().ok_or("无法复制路径")?;
    input
        .write_all(path.as_os_str().as_encoded_bytes())
        .await
        .map_err(|_| "无法写入剪贴板")?;
    drop(input);
    let status = tokio::time::timeout(Duration::from_secs(3), child.wait())
        .await
        .map_err(|_| "复制路径超时")?
        .map_err(|_| "复制路径失败")?;
    if status.success() {
        Ok(())
    } else {
        Err("剪贴板不可用；完整路径见详情".into())
    }
}
#[cfg(test)]
#[path = "vm_tests.rs"]
mod tests;
