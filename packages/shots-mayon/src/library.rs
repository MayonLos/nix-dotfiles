use anyhow::{bail, Context, Result};
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use std::{
    collections::HashSet,
    fs, io,
    os::unix::{
        fs::{OpenOptionsExt, PermissionsExt},
        io::AsRawFd,
        process::CommandExt,
    },
    path::{Path, PathBuf},
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

const IMAGE_EXTENSIONS: &[&str] = &["png", "jpg", "jpeg", "webp", "bmp", "tif", "tiff", "avif"];
const VIDEO_EXTENSIONS: &[&str] = &["mp4", "mkv", "webm", "mov", "avi", "m4v"];
const OCR_TIMEOUT: Duration = Duration::from_secs(120);

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Entry {
    pub path: String,
    pub name: String,
    pub kind: String,
    pub source: String,
    pub modified: i64,
    pub text: String,
    pub favorite: bool,
}

#[derive(Debug)]
struct FileRecord {
    path: String,
    name: String,
    kind: String,
    source: String,
    modified: i64,
    mtime_ns: i64,
    size: u64,
}

pub struct Library {
    pub dir: PathBuf,
    home: PathBuf,
    config_home: PathBuf,
    db_path: PathBuf,
}

impl Library {
    pub fn open() -> Result<Self> {
        let home = std::env::var_os("HOME")
            .map(PathBuf::from)
            .context("HOME is not set")?;
        let data_home = std::env::var_os("XDG_DATA_HOME")
            .map(PathBuf::from)
            .filter(|path| path.is_absolute())
            .unwrap_or_else(|| home.join(".local/share"));
        let config_home = std::env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .filter(|path| path.is_absolute())
            .unwrap_or_else(|| home.join(".config"));
        Self::open_at(home, data_home, config_home)
    }

    #[cfg(test)]
    fn open_under(home: PathBuf) -> Result<Self> {
        Self::open_at(
            home.clone(),
            home.join(".local/share"),
            home.join(".config"),
        )
    }

    fn open_at(home: PathBuf, data_home: PathBuf, config_home: PathBuf) -> Result<Self> {
        let dir = data_home.join("shots-mayon");
        create_private_dir(&dir)?;
        let db_path = dir.join("library.sqlite3");
        if fs::symlink_metadata(&db_path).is_ok_and(|m| m.file_type().is_symlink()) {
            bail!("refusing symlinked database: {}", db_path.display());
        }
        let library = Self {
            dir,
            home,
            config_home,
            db_path,
        };
        library.with_db(|db| {
            db.execute_batch(
                "PRAGMA journal_mode=WAL;
                 PRAGMA synchronous=NORMAL;
                 CREATE TABLE IF NOT EXISTS entries (
                   path TEXT PRIMARY KEY NOT NULL,
                   name TEXT NOT NULL,
                   kind TEXT NOT NULL,
                   source TEXT NOT NULL DEFAULT '',
                   modified INTEGER NOT NULL,
                   mtime_ns INTEGER NOT NULL DEFAULT 0,
                   size INTEGER NOT NULL,
                   text TEXT NOT NULL DEFAULT '',
                   ocr_done INTEGER NOT NULL DEFAULT 0,
                   ocr_attempts INTEGER NOT NULL DEFAULT 0,
                   ocr_retry_after INTEGER NOT NULL DEFAULT 0,
                   favorite INTEGER NOT NULL DEFAULT 0
                 );
                 CREATE INDEX IF NOT EXISTS entries_modified ON entries(modified DESC);
                 CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                 INSERT OR IGNORE INTO settings(key, value) VALUES ('paused', '0');",
            )?;
            Ok(())
        })?;
        set_private_file(&library.db_path)?;
        Ok(library)
    }

    fn with_db<T>(&self, f: impl FnOnce(&Connection) -> Result<T>) -> Result<T> {
        let db = Connection::open(&self.db_path)
            .with_context(|| format!("opening index {}", self.db_path.display()))?;
        db.busy_timeout(Duration::from_secs(5))?;
        f(&db)
    }

    fn roots(&self) -> Result<Vec<PathBuf>> {
        let config = self.config_home.join("shots-mayon/config.json");
        if config.exists() {
            let bytes =
                fs::read(&config).with_context(|| format!("reading {}", config.display()))?;
            let value: serde_json::Value = serde_json::from_slice(&bytes)
                .with_context(|| format!("parsing {}", config.display()))?;
            if let Some(roots) = value.get("roots").and_then(serde_json::Value::as_array) {
                let parsed = roots
                    .iter()
                    .filter_map(serde_json::Value::as_str)
                    .map(|root| expand_root(root, &self.home))
                    .collect::<Vec<_>>();
                return Ok(deduplicate(parsed));
            }
        }

        let pictures = self.home.join("Pictures");
        Ok(deduplicate(
            [
                pictures.join("Screenshots"),
                pictures.join("截图"),
                pictures.join("MarkShot"),
                pictures.join("mark-shot"),
                pictures.join("wayscrollshot"),
                self.home.join("Videos/Recordings"),
            ]
            .into_iter()
            .collect(),
        ))
    }

    /// Index media-file metadata without opening or decoding the media itself.
    /// Screenshot contents are read only later by the explicit OCR worker.
    pub fn index(&self) -> Result<usize> {
        let roots = self.roots()?;
        let mut active_roots = Vec::new();
        let mut records = Vec::new();
        for root in roots {
            let Ok(metadata) = fs::symlink_metadata(&root) else {
                continue;
            };
            if !metadata.is_dir() || metadata.file_type().is_symlink() {
                continue;
            }
            active_roots.push(root.clone());
            walk_media(&root, &mut records)?;
        }

        self.with_db(|db| {
            let tx = db.unchecked_transaction()?;
            let mut changed = 0;
            for record in &records {
                let previous: Option<(i64, i64, i64, String)> = tx
                    .query_row(
                        "SELECT mtime_ns, size, favorite, source FROM entries WHERE path=?1",
                        [&record.path],
                        |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
                    )
                    .optional()?;
                let mtime = record.modified;
                let mtime_ns = record.mtime_ns;
                let size = i64::try_from(record.size).unwrap_or(i64::MAX);
                let same_media = previous.as_ref().is_some_and(|(old_mtime, old_size, _, _)| {
                    *old_mtime == mtime_ns && *old_size == size
                });
                if same_media
                    && previous
                        .as_ref()
                        .is_some_and(|(_, _, _, old_source)| old_source == &record.source)
                {
                    continue;
                }
                if same_media {
                    tx.execute(
                        "UPDATE entries SET name=?1,kind=?2,source=?3,modified=?4 WHERE path=?5",
                        params![record.name, record.kind, record.source, mtime, record.path],
                    )?;
                    changed += 1;
                    continue;
                }
                tx.execute(
                    "INSERT INTO entries(path,name,kind,source,modified,mtime_ns,size,text,ocr_done,ocr_attempts,ocr_retry_after,favorite)
                     VALUES (?1,?2,?3,?4,?5,?6,?7,'',0,0,0,COALESCE((SELECT favorite FROM entries WHERE path=?1),0))
                     ON CONFLICT(path) DO UPDATE SET
                       name=excluded.name, kind=excluded.kind, source=excluded.source,
                       modified=excluded.modified, mtime_ns=excluded.mtime_ns,
                       size=excluded.size, text='', ocr_done=0, ocr_attempts=0,
                       ocr_retry_after=0, favorite=entries.favorite",
                    params![record.path, record.name, record.kind, record.source, mtime, mtime_ns, size],
                )?;
                changed += 1;
            }

            // Remove only stale index rows below roots that were successfully
            // scanned. Missing/unmounted roots do not make their rows vanish.
            let mut rows = tx.prepare("SELECT path FROM entries")?;
            let known = rows
                .query_map([], |row| row.get::<_, String>(0))?
                .collect::<rusqlite::Result<Vec<_>>>()?;
            drop(rows);
            let present: HashSet<&str> = records.iter().map(|r| r.path.as_str()).collect();
            for path in known {
                let indexed_root = active_roots.iter().any(|root| {
                    Path::new(&path).starts_with(root)
                });
                if indexed_root && !present.contains(path.as_str()) {
                    tx.execute("DELETE FROM entries WHERE path=?1", [&path])?;
                }
            }
            tx.commit()?;
            Ok(changed)
        })
    }

    pub fn entries(
        &self,
        query: &str,
        kind: Option<&str>,
        source: Option<&str>,
        favorite: bool,
    ) -> Result<Vec<Entry>> {
        self.with_db(|db| {
            let mut stmt = db.prepare(
                "SELECT path,name,kind,source,modified,text,favorite
                 FROM entries ORDER BY modified DESC, path ASC",
            )?;
            let rows = stmt.query_map([], |row| {
                Ok(Entry {
                    path: row.get(0)?,
                    name: row.get(1)?,
                    kind: row.get(2)?,
                    source: row.get(3)?,
                    modified: row.get(4)?,
                    text: row.get(5)?,
                    favorite: row.get::<_, i64>(6)? != 0,
                })
            })?;
            let query = query.to_lowercase();
            let source = source.map(str::to_lowercase);
            let mut entries = Vec::new();
            for row in rows {
                let item = row?;
                if favorite && !item.favorite {
                    continue;
                }
                if kind.is_some_and(|wanted| item.kind != wanted) {
                    continue;
                }
                if source
                    .as_deref()
                    .is_some_and(|wanted| !item.source.to_lowercase().contains(wanted))
                {
                    continue;
                }
                let date = chrono::DateTime::from_timestamp(item.modified, 0)
                    .map(|dt| {
                        dt.with_timezone(&chrono::Local)
                            .format("%Y-%m-%d")
                            .to_string()
                    })
                    .unwrap_or_default();
                let fields = [
                    item.path.as_str(),
                    item.name.as_str(),
                    item.kind.as_str(),
                    item.source.as_str(),
                    item.text.as_str(),
                    date.as_str(),
                ];
                if !query.is_empty()
                    && !fields
                        .iter()
                        .any(|field| field.to_lowercase().contains(&query))
                {
                    continue;
                }
                entries.push(item);
            }
            Ok(entries)
        })
    }

    pub fn favorite(&self, path: &str) -> Result<()> {
        self.with_db(|db| {
            let changed = db.execute(
                "UPDATE entries SET favorite=1-favorite WHERE path=?1",
                [path],
            )?;
            if changed == 0 {
                bail!("file is not indexed: {path}");
            }
            Ok(())
        })
    }

    pub fn set_paused(&self, paused: bool) -> Result<()> {
        self.with_db(|db| {
            db.execute(
                "INSERT INTO settings(key,value) VALUES ('paused',?1)
                 ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                [if paused { "1" } else { "0" }],
            )?;
            Ok(())
        })
    }

    pub fn paused(&self) -> bool {
        self.with_db(|db| {
            let value: Option<String> = db
                .query_row("SELECT value FROM settings WHERE key='paused'", [], |r| {
                    r.get(0)
                })
                .optional()?;
            Ok(value.as_deref() == Some("1"))
        })
        .unwrap_or(true)
    }

    /// Run one lowest-priority OCR job. An advisory lock prevents a second
    /// process from starting another Tesseract worker at the same time.
    pub fn ocr_one(&self) -> Result<bool> {
        if self.paused() {
            return Ok(false);
        }
        let lock_path = self.dir.join("ocr.lock");
        let lock = fs::OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .mode(0o600)
            .open(&lock_path)?;
        set_private_file(&lock_path)?;
        // SAFETY: flock only observes the valid file descriptor held by `lock`.
        if unsafe { libc::flock(lock.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
            return Ok(false);
        }
        if self.paused() {
            return Ok(false);
        }
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64;
        let job: Option<(String, i64, i64, i64)> = self.with_db(|db| {
            db.query_row(
                "SELECT path,mtime_ns,size,ocr_attempts FROM entries
                 WHERE kind='image' AND ocr_done=0 AND ocr_retry_after<=?1
                 ORDER BY modified ASC,path ASC LIMIT 1",
                [now],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .optional()
            .map_err(Into::into)
        })?;
        let Some((path, expected_mtime, expected_size, attempts)) = job else {
            return Ok(false);
        };
        let file = PathBuf::from(&path);
        let metadata = match fs::symlink_metadata(&file) {
            Ok(meta) if meta.is_file() && !meta.file_type().is_symlink() => meta,
            Ok(_) => {
                self.forget(&path)?;
                return Ok(true);
            }
            Err(e) if e.kind() == io::ErrorKind::NotFound => {
                self.forget(&path)?;
                return Ok(true);
            }
            Err(e) => {
                self.record_ocr_failure(&path, expected_mtime, expected_size, attempts)?;
                return Err(e).context("reading OCR input metadata; index retained");
            }
        };
        if metadata.len() != expected_size as u64
            || modified_nanoseconds(&metadata) != expected_mtime
        {
            self.index()?;
            self.record_ocr_failure(&path, expected_mtime, expected_size, attempts)?;
            return Ok(true);
        }
        if self.paused() {
            return Ok(false);
        }

        let output_path = self.dir.join(format!("ocr-{}.txt", std::process::id()));
        let stdout = fs::OpenOptions::new()
            .create(true)
            .truncate(true)
            .write(true)
            .mode(0o600)
            .open(&output_path)?;
        let spawn_result = Command::new("ionice")
            .args(["-c3", "nice", "-n", "15", "tesseract"])
            .arg(&file)
            .arg("stdout")
            .args(["-l", "chi_sim+eng", "--psm", "6"])
            .stdout(Stdio::from(stdout))
            .stderr(Stdio::null())
            .process_group(0)
            .spawn();
        let mut child = match spawn_result {
            Ok(child) => child,
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                let stdout = fs::OpenOptions::new()
                    .write(true)
                    .truncate(true)
                    .open(&output_path)?;
                match Command::new("nice")
                    .args(["-n", "15", "tesseract"])
                    .arg(&file)
                    .arg("stdout")
                    .args(["-l", "chi_sim+eng", "--psm", "6"])
                    .stdout(Stdio::from(stdout))
                    .stderr(Stdio::null())
                    .process_group(0)
                    .spawn()
                {
                    Ok(child) => child,
                    Err(error) => {
                        let _ = fs::remove_file(&output_path);
                        self.record_ocr_failure(&path, expected_mtime, expected_size, attempts)?;
                        return Err(error).context("starting low-priority Tesseract");
                    }
                }
            }
            Err(error) => {
                let _ = fs::remove_file(&output_path);
                self.record_ocr_failure(&path, expected_mtime, expected_size, attempts)?;
                return Err(error).context("starting low-priority Tesseract");
            }
        };
        let start = Instant::now();
        let status = loop {
            if let Some(status) = child.try_wait()? {
                break status;
            }
            if self.paused() {
                terminate_child_group(&mut child);
                let _ = fs::remove_file(&output_path);
                return Ok(false);
            }
            if start.elapsed() >= OCR_TIMEOUT {
                terminate_child_group(&mut child);
                let _ = fs::remove_file(&output_path);
                self.record_ocr_failure(&path, expected_mtime, expected_size, attempts)?;
                bail!("Tesseract timed out; queued with retry backoff");
            }
            thread::sleep(Duration::from_millis(200));
        };
        if !status.success() {
            let _ = fs::remove_file(&output_path);
            self.record_ocr_failure(&path, expected_mtime, expected_size, attempts)?;
            bail!("Tesseract exited with {status}");
        }
        let text = fs::read_to_string(&output_path).context("reading OCR result")?;
        fs::remove_file(&output_path).ok();

        // Do not attach OCR output to a file that changed while recognition ran.
        let current = match fs::symlink_metadata(&file) {
            Ok(current) => current,
            Err(e) if e.kind() == io::ErrorKind::NotFound => {
                self.forget(&path)?;
                return Ok(true);
            }
            Err(e) => return Err(e.into()),
        };
        if !current.is_file()
            || current.file_type().is_symlink()
            || current.len() != expected_size as u64
            || modified_nanoseconds(&current) != expected_mtime
        {
            self.index()?;
            self.record_ocr_failure(&path, expected_mtime, expected_size, attempts)?;
            return Ok(true);
        }
        self.with_db(|db| {
            let changed = db.execute(
                "UPDATE entries SET text=?1,ocr_done=1 WHERE path=?2 AND mtime_ns=?3 AND size=?4",
                params![text.trim(), path, expected_mtime, expected_size],
            )?;
            Ok(changed > 0)
        })
    }

    fn record_ocr_failure(
        &self,
        path: &str,
        mtime_ns: i64,
        size: i64,
        attempts: i64,
    ) -> Result<()> {
        let attempts = attempts.saturating_add(1);
        let delay = (60i64 * (1i64 << attempts.clamp(1, 6) as u32)).min(3600);
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64;
        self.with_db(|db| {
            db.execute(
                "UPDATE entries SET ocr_attempts=?1,ocr_retry_after=?2
                 WHERE path=?3 AND mtime_ns=?4 AND size=?5",
                params![attempts, now.saturating_add(delay), path, mtime_ns, size],
            )?;
            Ok(())
        })
    }

    pub fn forget(&self, path: &str) -> Result<()> {
        self.with_db(|db| {
            db.execute("DELETE FROM entries WHERE path=?1", [path])?;
            Ok(())
        })
    }
}

fn create_private_dir(path: &Path) -> Result<()> {
    fs::create_dir_all(path).with_context(|| format!("creating {}", path.display()))?;
    let metadata = fs::symlink_metadata(path)?;
    if !metadata.is_dir() || metadata.file_type().is_symlink() {
        bail!(
            "data directory must be a real directory: {}",
            path.display()
        );
    }
    fs::set_permissions(path, fs::Permissions::from_mode(0o700))?;
    Ok(())
}

fn set_private_file(path: &Path) -> Result<()> {
    fs::set_permissions(path, fs::Permissions::from_mode(0o600))?;
    Ok(())
}

fn terminate_child_group(child: &mut std::process::Child) {
    if let Ok(pid) = i32::try_from(child.id()) {
        // SAFETY: CommandExt::process_group(0) made the child its process group leader.
        unsafe {
            libc::kill(-pid, libc::SIGTERM);
        }
        thread::sleep(Duration::from_millis(100));
        // SAFETY: the same process group is confined to this OCR command tree.
        unsafe {
            libc::kill(-pid, libc::SIGKILL);
        }
    }
    let _ = child.wait();
}

fn expand_root(root: &str, home: &Path) -> PathBuf {
    if root == "~" {
        home.to_path_buf()
    } else if let Some(rest) = root.strip_prefix("~/") {
        home.join(rest)
    } else if Path::new(root).is_relative() {
        home.join(root)
    } else {
        PathBuf::from(root)
    }
}

fn deduplicate(roots: Vec<PathBuf>) -> Vec<PathBuf> {
    let mut seen = HashSet::new();
    roots
        .into_iter()
        .filter(|path| seen.insert(path.clone()))
        .collect()
}

fn walk_media(root: &Path, records: &mut Vec<FileRecord>) -> Result<()> {
    let entries = match fs::read_dir(root) {
        Ok(entries) => entries,
        Err(error) => return Err(error).with_context(|| format!("scanning {}", root.display())),
    };
    for entry in entries {
        let entry = entry?;
        let path = entry.path();
        let metadata = entry.file_type()?;
        if metadata.is_symlink() {
            continue;
        }
        if metadata.is_dir() {
            walk_media(&path, records)?;
            continue;
        }
        if !metadata.is_file() {
            continue;
        }
        let extension = path
            .extension()
            .and_then(|extension| extension.to_str())
            .unwrap_or_default()
            .to_ascii_lowercase();
        let kind = if IMAGE_EXTENSIONS.contains(&extension.as_str()) {
            "image"
        } else if VIDEO_EXTENSIONS.contains(&extension.as_str()) {
            "video"
        } else {
            continue;
        };
        let metadata = fs::symlink_metadata(&path)?;
        let name = path
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or_default()
            .to_string();
        records.push(FileRecord {
            path: path.to_string_lossy().into_owned(),
            name,
            kind: kind.to_string(),
            source: sidecar_source(&path),
            modified: modified_seconds(&metadata),
            mtime_ns: modified_nanoseconds(&metadata),
            size: metadata.len(),
        });
    }
    Ok(())
}

fn sidecar_source(path: &Path) -> String {
    let mut sidecar = path.as_os_str().to_os_string();
    sidecar.push(".shots.json");
    let sidecar = PathBuf::from(sidecar);
    if fs::symlink_metadata(&sidecar)
        .map(|metadata| {
            !metadata.is_file() || metadata.file_type().is_symlink() || metadata.len() > 32 * 1024
        })
        .unwrap_or(true)
    {
        return String::new();
    }
    fs::read(sidecar)
        .ok()
        .and_then(|bytes| serde_json::from_slice::<serde_json::Value>(&bytes).ok())
        .and_then(|value| {
            value
                .get("source")
                .and_then(serde_json::Value::as_str)
                .map(str::to_string)
        })
        .unwrap_or_default()
}

fn modified_seconds(metadata: &fs::Metadata) -> i64 {
    metadata
        .modified()
        .unwrap_or(SystemTime::UNIX_EPOCH)
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
        .min(i64::MAX as u64) as i64
}

fn modified_nanoseconds(metadata: &fs::Metadata) -> i64 {
    metadata
        .modified()
        .unwrap_or(SystemTime::UNIX_EPOCH)
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos()
        .min(i64::MAX as u128) as i64
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn open_fixture() -> (TempDir, Library) {
        let home = tempfile::tempdir().unwrap();
        fs::create_dir_all(home.path().join("Pictures/mark-shot")).unwrap();
        fs::create_dir_all(home.path().join("Videos/Recordings")).unwrap();
        let library = Library::open_under(home.path().to_path_buf()).unwrap();
        (home, library)
    }

    #[test]
    fn private_storage_and_incremental_index_are_metadata_only() {
        let (_home, library) = open_fixture();
        let image = library.home.join("Pictures/mark-shot/a.png");
        fs::write(&image, b"synthetic image fixture; never decoded by index").unwrap();
        let mode = fs::metadata(&library.dir).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o700);
        assert_eq!(library.index().unwrap(), 1);
        assert_eq!(
            fs::read(&image).unwrap(),
            b"synthetic image fixture; never decoded by index"
        );
        assert_eq!(library.index().unwrap(), 0);
        let db_mode = fs::metadata(&library.db_path).unwrap().permissions().mode() & 0o777;
        assert_eq!(db_mode, 0o600);
    }

    #[test]
    fn unreadable_subtree_cannot_prune_favorites() {
        if unsafe { libc::geteuid() } == 0 {
            return;
        }
        let (_home, library) = open_fixture();
        let hidden = library.home.join("Pictures/mark-shot/restricted");
        fs::create_dir(&hidden).unwrap();
        let image = hidden.join("private.png");
        fs::write(&image, b"synthetic fixture").unwrap();
        library.index().unwrap();
        library.favorite(image.to_str().unwrap()).unwrap();
        fs::set_permissions(&hidden, fs::Permissions::from_mode(0o000)).unwrap();
        let failed = library.index().is_err();
        let ocr_failed = library.ocr_one().is_err();
        fs::set_permissions(&hidden, fs::Permissions::from_mode(0o700)).unwrap();
        assert!(failed);
        assert!(ocr_failed);
        assert_eq!(library.entries("", None, None, true).unwrap().len(), 1);
    }

    #[test]
    fn search_filters_filename_date_kind_source_and_ocr_text() {
        let (_home, library) = open_fixture();
        let image = library.home.join("Pictures/mark-shot/window.png");
        fs::write(&image, b"synthetic").unwrap();
        fs::write(
            format!("{}.shots.json", image.display()),
            br#"{"source":"Editor Window"}"#,
        )
        .unwrap();
        let video = library.home.join("Videos/Recordings/demo.mp4");
        fs::write(&video, b"synthetic").unwrap();
        library.index().unwrap();
        library
            .with_db(|db| {
                db.execute(
                    "UPDATE entries SET text='包含计划文字' WHERE path=?1",
                    [image.to_string_lossy().as_ref()],
                )?;
                Ok(())
            })
            .unwrap();
        assert_eq!(
            library
                .entries("计划文字", None, None, false)
                .unwrap()
                .len(),
            1
        );
        assert_eq!(
            library
                .entries("editor", None, Some("window"), false)
                .unwrap()
                .len(),
            1
        );
        assert_eq!(
            library
                .entries("window", Some("image"), None, false)
                .unwrap()
                .len(),
            1
        );
        assert_eq!(
            library
                .entries("2020-01-01", None, None, false)
                .unwrap()
                .len(),
            0
        );
        assert_eq!(
            library
                .entries("demo", Some("video"), None, false)
                .unwrap()
                .len(),
            1
        );
    }

    #[test]
    fn modified_files_clear_prior_ocr_and_symlinks_are_not_indexed() {
        let (_home, library) = open_fixture();
        let image = library.home.join("Pictures/mark-shot/a.png");
        fs::write(&image, b"synthetic A").unwrap();
        library.index().unwrap();
        library
            .with_db(|db| {
                db.execute(
                    "UPDATE entries SET text='stale OCR',ocr_done=1 WHERE path=?1",
                    [image.to_string_lossy().as_ref()],
                )?;
                Ok(())
            })
            .unwrap();
        thread::sleep(Duration::from_millis(10));
        fs::write(&image, b"synthetic B").unwrap();
        let link = library.home.join("Pictures/mark-shot/linked.png");
        std::os::unix::fs::symlink(&image, &link).unwrap();
        assert_eq!(library.index().unwrap(), 1);
        let entries = library.entries("", None, None, false).unwrap();
        assert_eq!(entries.len(), 1);
        assert!(entries[0].text.is_empty());
        let ocr_done = library
            .with_db(|db| {
                Ok(db.query_row(
                    "SELECT ocr_done FROM entries WHERE path=?1",
                    [image.to_string_lossy().as_ref()],
                    |row| row.get::<_, i64>(0),
                )?)
            })
            .unwrap();
        assert_eq!(ocr_done, 0);
    }

    #[test]
    fn source_sidecar_changes_without_rescanning_media_bytes() {
        let (_home, library) = open_fixture();
        let image = library.home.join("Pictures/mark-shot/a.png");
        fs::write(&image, b"synthetic").unwrap();
        let sidecar = format!("{}.shots.json", image.display());
        fs::write(&sidecar, br#"{"source":"Old Window"}"#).unwrap();
        library.index().unwrap();
        library
            .with_db(|db| {
                db.execute(
                    "UPDATE entries SET text='recognized',ocr_done=1 WHERE path=?1",
                    [image.to_string_lossy().as_ref()],
                )?;
                Ok(())
            })
            .unwrap();
        fs::write(&sidecar, br#"{"source":"New Window"}"#).unwrap();
        assert_eq!(library.index().unwrap(), 1);
        let entries = library.entries("", None, Some("new"), false).unwrap();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].text, "recognized");
    }

    #[test]
    fn pause_and_favorite_are_stored_in_index() {
        let (_home, library) = open_fixture();
        let image = library.home.join("Pictures/mark-shot/a.png");
        fs::write(&image, b"synthetic").unwrap();
        library.index().unwrap();
        assert!(!library.paused());
        library.set_paused(true).unwrap();
        assert!(library.paused());
        library.favorite(image.to_string_lossy().as_ref()).unwrap();
        assert_eq!(library.entries("", None, None, true).unwrap().len(), 1);
    }
}
