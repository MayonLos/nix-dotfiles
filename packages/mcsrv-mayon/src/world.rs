//! Conservative validation and read-only copying of vanilla single-player worlds.
use anyhow::{bail, Context, Result};
use fs2::FileExt;
use std::{
    fs::{self, File, OpenOptions},
    io::{Read, Write},
    os::unix::{
        fs::{MetadataExt, OpenOptionsExt, PermissionsExt},
        io::AsRawFd,
    },
    path::{Path, PathBuf},
};

fn source_file(path: &Path) -> Result<File> {
    crate::model::no_symlinks(path)?;
    let file = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK)
        .open(path)?;
    if !file.metadata()?.is_file() {
        bail!("只复制普通文件：{}", path.display());
    }
    Ok(file)
}

fn world_lock(source: &Path) -> Result<Option<File>> {
    let lock = source.join("session.lock");
    crate::model::no_symlinks(&lock)?;
    if !lock.exists() {
        return Ok(None);
    }
    let file = source_file(&lock)?;
    FileExt::try_lock_shared(&file).context("存档正在使用；请先退出单人世界再复制")?;
    // Java FileChannel locks are POSIX record locks, independent of flock on Linux.
    let mut query: libc::flock = unsafe { std::mem::zeroed() };
    query.l_type = libc::F_WRLCK as _;
    query.l_whence = libc::SEEK_SET as _;
    let status = unsafe { libc::fcntl(file.as_raw_fd(), libc::F_GETLK, &mut query) };
    if status < 0 {
        return Err(std::io::Error::last_os_error().into());
    }
    if query.l_type != libc::F_UNLCK as libc::c_short {
        bail!("存档正在使用；请先退出单人世界再复制");
    }
    Ok(Some(file))
}

#[derive(Debug, PartialEq, Eq)]
struct Stamp {
    path: PathBuf,
    inode: u64,
    size: u64,
    mtime: (i64, i64),
    ctime: (i64, i64),
}
fn stamps(path: &Path, root: &Path, output: &mut Vec<Stamp>) -> Result<()> {
    let metadata = fs::symlink_metadata(path)?;
    if metadata.file_type().is_symlink() || (!metadata.is_file() && !metadata.is_dir()) {
        bail!("拒绝复制符号链接或特殊文件：{}", path.display());
    }
    if output.len() > 1_000_000 {
        bail!("存档文件数超过安全上限");
    }
    output.push(Stamp {
        path: path.strip_prefix(root)?.to_owned(),
        inode: metadata.ino(),
        size: metadata.len(),
        mtime: (metadata.mtime(), metadata.mtime_nsec()),
        ctime: (metadata.ctime(), metadata.ctime_nsec()),
    });
    if metadata.is_dir() {
        let mut entries = fs::read_dir(path)?
            .map(|e| e.map(|e| e.path()))
            .collect::<std::io::Result<Vec<_>>>()?;
        entries.sort();
        for child in entries {
            stamps(&child, root, output)?;
        }
    }
    Ok(())
}

/// Copies only regular files and directories, with private destination permissions.
fn copy_readonly_tree(source: &Path, destination: &Path) -> Result<()> {
    crate::model::no_symlinks(source)?;
    crate::model::no_symlinks(destination)?;
    let md = fs::symlink_metadata(source)?;
    if md.is_dir() {
        crate::model::private_dir(destination)?;
        for e in fs::read_dir(source)? {
            let e = e?;
            copy_readonly_tree(&e.path(), &destination.join(e.file_name()))?;
        }
    } else if md.is_file() {
        let mut input = source_file(source)?;
        if destination.exists() {
            bail!("目标文件已存在：{}", destination.display());
        }
        let mut output =
            tempfile::NamedTempFile::new_in(destination.parent().context("目标无父目录")?)?;
        output
            .as_file()
            .set_permissions(fs::Permissions::from_mode(0o600))?;
        std::io::copy(&mut input, &mut output)?;
        output.flush()?;
        output.persist_noclobber(destination)?;
    } else {
        bail!("拒绝复制符号链接或特殊文件：{}", source.display());
    }
    Ok(())
}

/// Make a consistent private copy without opening any source file for writing.
/// Modern Minecraft's session lock is checked; metadata is checked again after copying
/// to reject worlds which changed during the snapshot (including old lock formats).
pub fn copy_world(source: &Path, destination: &Path) -> Result<()> {
    crate::model::no_symlinks(source)?;
    crate::model::no_symlinks(destination)?;
    if destination.exists() {
        bail!("目标世界已存在，拒绝覆盖");
    }
    if !source.join("level.dat").is_file() {
        bail!("请选择含 level.dat 的单人存档目录");
    }
    let _lock = world_lock(source)?;
    validate_vanilla(source)?;
    let parent = destination.parent().context("目标无父目录")?;
    // Check before creating any destination directory: a rejected copy must never
    // create files inside the original world, including nonexistent descendants.
    let mut ancestor = parent;
    while !ancestor.exists() {
        ancestor = ancestor.parent().context("目标无有效祖先目录")?;
    }
    if ancestor.canonicalize()?.starts_with(source.canonicalize()?) {
        bail!("不能把目标放在原存档内");
    }
    crate::model::private_dir(parent)?;
    let mut before = Vec::new();
    stamps(source, source, &mut before)?;
    let staging = tempfile::Builder::new()
        .prefix(".world-copy-")
        .tempdir_in(parent)?;
    copy_readonly_tree(source, staging.path())?;
    let mut after = Vec::new();
    stamps(source, source, &mut after)?;
    if before != after {
        bail!("复制期间原存档发生变化；请退出世界后重试");
    }
    // Do not propagate the source world's lock identity/timestamp.
    let copied_lock = staging.path().join("session.lock");
    if copied_lock.exists() {
        fs::remove_file(copied_lock)?;
    }
    use std::os::unix::ffi::OsStrExt;
    let from = std::ffi::CString::new(staging.path().as_os_str().as_bytes())?;
    let to = std::ffi::CString::new(destination.as_os_str().as_bytes())?;
    let result = unsafe {
        libc::renameat2(
            libc::AT_FDCWD,
            from.as_ptr(),
            libc::AT_FDCWD,
            to.as_ptr(),
            libc::RENAME_NOREPLACE,
        )
    };
    if result < 0 {
        return Err(std::io::Error::last_os_error().into());
    }
    let _ = staging.keep();
    Ok(())
}

/// Refuse modded and unknown worlds rather than silently stripping mod data.
/// Positive evidence is modern vanilla's WasModded=false plus Version.Name and
/// DataVersion. Older saves without these fields require manual migration.
pub fn validate_vanilla(world: &Path) -> Result<String> {
    let info = inspect(world)?;
    if info.modded {
        bail!("检测到 FML/Forge/Fabric/mods 或自定义命名空间记录：不支持模组世界转为 Vanilla/Paper，请保留原服务端整合包");
    }
    let version = info
        .version
        .context("无法确认原版世界：level.dat 缺少 Version.Name；拒绝猜测或升级")?;
    if info.was_modded != Some(false) || !info.data_version {
        bail!("无法确认原版世界：缺少 DataVersion 或明确 WasModded=false；旧版/来源未知存档需人工迁移");
    }
    let era = version
        .split('.')
        .next()
        .and_then(|v| v.parse::<u32>().ok());
    if !(version.starts_with("1.") || era.is_some_and(|v| v >= 26))
        || !version.bytes().all(|b| b.is_ascii_digit() || b == b'.')
    {
        bail!("无法确认正式版 Minecraft 版本；快照/未知版本需人工迁移");
    }
    Ok(version)
}

#[derive(Default)]
struct WorldInfo {
    version: Option<String>,
    was_modded: Option<bool>,
    data_version: bool,
    modded: bool,
}
fn inspect(world: &Path) -> Result<WorldInfo> {
    let input = source_file(&world.join("level.dat"))?;
    let mut bytes = Vec::new();
    flate2::read::GzDecoder::new(input)
        .take(8 * 1024 * 1024 + 1)
        .read_to_end(&mut bytes)?;
    if bytes.len() > 8 * 1024 * 1024 {
        bail!("level.dat 解压大小超过安全上限");
    }
    let mut cursor = Nbt {
        bytes: &bytes,
        at: 0,
        info: WorldInfo::default(),
    };
    if cursor.byte()? != 10 {
        bail!("level.dat 不是 NBT compound");
    }
    cursor.string()?;
    cursor.payload(10, &[], 0)?;
    if cursor.at != bytes.len() {
        bail!("level.dat 含未识别尾随数据");
    }
    Ok(cursor.info)
}
struct Nbt<'a> {
    bytes: &'a [u8],
    at: usize,
    info: WorldInfo,
}
fn mod_marker(value: &str) -> bool {
    let lower = value.to_ascii_lowercase();
    lower.contains("fml")
        || lower.contains("forge")
        || lower.contains("fabric")
        || matches!(
            lower.as_str(),
            "mods" | "modlist" | "mod_list" | "modloader" | "mod_data" | "moddata"
        )
}
fn custom_namespace(value: &str) -> bool {
    value.split_once(':').is_some_and(|(namespace, path)| {
        namespace != "minecraft"
            && !namespace.is_empty()
            && !path.is_empty()
            && namespace
                .bytes()
                .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b"_.-".contains(&b))
            && path
                .bytes()
                .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b"_.-/".contains(&b))
    })
}
impl Nbt<'_> {
    fn take(&mut self, n: usize) -> Result<&[u8]> {
        let end = self.at.checked_add(n).context("NBT 长度溢出")?;
        let result = self.bytes.get(self.at..end).context("NBT 数据不完整")?;
        self.at = end;
        Ok(result)
    }
    fn byte(&mut self) -> Result<u8> {
        Ok(self.take(1)?[0])
    }
    fn string(&mut self) -> Result<String> {
        let n = u16::from_be_bytes(self.take(2)?.try_into()?) as usize;
        Ok(String::from_utf8(self.take(n)?.to_vec())?)
    }
    fn length(&mut self) -> Result<usize> {
        let n = i32::from_be_bytes(self.take(4)?.try_into()?);
        if n < 0 {
            bail!("NBT 长度为负数");
        }
        Ok(n as usize)
    }
    fn payload(&mut self, tag: u8, path: &[String], depth: usize) -> Result<()> {
        if depth > 64 {
            bail!("NBT 嵌套过深");
        }
        match tag {
            1 => {
                let value = self.byte()?;
                if path == ["Data", "WasModded"] {
                    self.info.was_modded = Some(value != 0);
                    self.info.modded |= value != 0;
                }
            }
            3 => {
                let value = i32::from_be_bytes(self.take(4)?.try_into()?);
                if path == ["Data", "DataVersion"] {
                    self.info.data_version = value > 0;
                }
            }
            2 | 4 | 5 | 6 => {
                self.take([0, 1, 2, 4, 8, 4, 8][tag as usize])?;
            }
            7 | 11 | 12 => {
                let n = self.length()?;
                let width = match tag {
                    11 => 4,
                    12 => 8,
                    _ => 1,
                };
                self.take(n.checked_mul(width).context("NBT 长度溢出")?)?;
            }
            8 => {
                let value = self.string()?;
                self.info.modded |= custom_namespace(&value);
                if path == ["Data", "Version", "Name"] {
                    self.info.version = Some(value.clone());
                }
                if path == ["Data", "ServerBrands"] && value != "vanilla" {
                    self.info.modded = true;
                }
            }
            9 => {
                let kind = self.byte()?;
                let n = self.length()?;
                if n > 1_000_000 || (kind == 0 && n != 0) {
                    bail!("NBT list 非法");
                }
                for _ in 0..n {
                    self.payload(kind, path, depth + 1)?;
                }
            }
            10 => loop {
                let kind = self.byte()?;
                if kind == 0 {
                    break;
                }
                let name = self.string()?;
                self.info.modded |= mod_marker(&name) || custom_namespace(&name);
                let mut child = path.to_vec();
                child.push(name);
                self.payload(kind, &child, depth + 1)?;
            },
            _ => bail!("NBT tag 非法"),
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn vanilla(path: &Path, extra: &[u8]) {
        let mut bytes=b"\x0a\x00\x00\x0a\x00\x04Data\x03\x00\x0bDataVersion\x00\x00\x10\x00\x01\x00\x09WasModded\x00\x0a\x00\x07Version\x08\x00\x04Name\x00\x061.21.1\x00".to_vec();
        bytes.extend_from_slice(extra);
        bytes.extend_from_slice(b"\x00\x00");
        let mut gzip = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
        gzip.write_all(&bytes).unwrap();
        fs::write(path.join("level.dat"), gzip.finish().unwrap()).unwrap();
    }
    #[test]
    fn source_contents_permissions_and_mtime_are_unchanged() {
        let temp = tempfile::tempdir().unwrap();
        let source = temp.path().join("save");
        fs::create_dir(&source).unwrap();
        vanilla(&source, b"");
        fs::write(source.join("session.lock"), b"timestamp").unwrap();
        fs::set_permissions(source.join("level.dat"), fs::Permissions::from_mode(0o400)).unwrap();
        let original = fs::read(source.join("level.dat")).unwrap();
        let before = fs::metadata(source.join("level.dat")).unwrap();
        let destination = temp.path().join("server/world");
        copy_world(&source, &destination).unwrap();
        let after = fs::metadata(source.join("level.dat")).unwrap();
        assert_eq!(before.permissions().mode(), after.permissions().mode());
        assert_eq!(
            (before.mtime(), before.mtime_nsec()),
            (after.mtime(), after.mtime_nsec())
        );
        assert_eq!(fs::read(source.join("level.dat")).unwrap(), original);
        assert_eq!(fs::read(destination.join("level.dat")).unwrap(), original);
        assert!(!destination.join("session.lock").exists());
        assert_eq!(
            fs::metadata(destination.join("level.dat"))
                .unwrap()
                .permissions()
                .mode()
                & 0o777,
            0o600
        );
        assert!(copy_world(&source, &destination).is_err());
        assert_eq!(validate_vanilla(&source).unwrap(), "1.21.1");
    }
    #[test]
    fn rejects_symlinks_active_world_and_destination_inside_source() {
        let temp = tempfile::tempdir().unwrap();
        let source = temp.path().join("save");
        fs::create_dir(&source).unwrap();
        vanilla(&source, b"");
        assert!(copy_world(&source, &source.join("must-not-exist/world")).is_err());
        assert!(!source.join("must-not-exist").exists());
        std::os::unix::fs::symlink("level.dat", source.join("evil")).unwrap();
        assert!(copy_world(&source, &temp.path().join("world")).is_err());
        fs::remove_file(source.join("evil")).unwrap();
        fs::write(source.join("session.lock"), b"lock").unwrap();
        let held = File::open(source.join("session.lock")).unwrap();
        held.lock_exclusive().unwrap();
        assert!(copy_world(&source, &temp.path().join("world")).is_err());
    }
    #[test]
    fn rejects_modded_markers_even_after_version_and_unknown_saves() {
        let temp = tempfile::tempdir().unwrap();
        for extra in [
            b"\x0a\x00\x03FML\x00".as_slice(),
            b"\x0a\x00\x05Forge\x00",
            b"\x0a\x00\x06fabric\x00",
            b"\x09\x00\x04mods\x08\x00\x00\x00\x00",
            b"\x08\x00\x05Biome\x00\x0acustom:ore",
        ] {
            vanilla(temp.path(), extra);
            assert!(validate_vanilla(temp.path()).is_err());
        }
        let mut gzip = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
        gzip.write_all(b"\x0a\x00\x00\x00").unwrap();
        fs::write(temp.path().join("level.dat"), gzip.finish().unwrap()).unwrap();
        assert!(validate_vanilla(temp.path()).is_err());
    }
}
