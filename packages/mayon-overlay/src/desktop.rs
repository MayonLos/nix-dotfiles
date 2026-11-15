//! Freedesktop desktop-entry index and launch path.
//!
//! The launcher deliberately ignores icons: entries are plain text. Launching
//! always goes through `gio launch <desktop-file>`, which is the same code path
//! a file manager uses: it resolves the desktop ID, `TryExec`, the working
//! directory and any D-Bus activation declared by the entry. Tests start a
//! private `XDG_DATA_DIRS` tree containing one entry whose `Exec` writes a
//! marker file, so the launch contract is observable without inventing a
//! private launcher-only execution format.

use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

pub struct AppEntry {
    pub name: String,
    pub generic_name: String,
    pub comment: String,
    pub keywords: Vec<String>,
    pub desktop_path: PathBuf,
    pub categories: String,
}

impl AppEntry {
    pub fn haystack(&self) -> String {
        let mut text = String::new();
        text.push_str(&self.name);
        text.push(' ');
        text.push_str(&self.generic_name);
        text.push(' ');
        text.push_str(&self.comment);
        text.push(' ');
        text.push_str(&self.keywords.join(" "));
        text.push(' ');
        text.push_str(&self.categories);
        text.to_lowercase()
    }

    pub fn subtitle(&self) -> String {
        if !self.generic_name.is_empty() {
            self.generic_name.clone()
        } else if !self.comment.is_empty() {
            self.comment.clone()
        } else {
            let categories = self.categories.replace(';', " ");
            categories.trim().to_string()
        }
    }
}

/// Directory list used by the launcher, in XDG precedence order. Entries in
/// earlier directories win when two files declare the same desktop ID.
pub fn data_dirs(extra: &[PathBuf]) -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    for extra_dir in extra {
        dirs.push(extra_dir.clone());
    }
    if let Some(home) = std::env::var_os("XDG_DATA_HOME") {
        dirs.push(PathBuf::from(home));
    } else if let Some(home) = std::env::var_os("HOME") {
        dirs.push(PathBuf::from(home).join(".local/share"));
    }
    let defaults = std::env::var("XDG_DATA_DIRS")
        .unwrap_or_else(|_| "/usr/local/share:/usr/share".to_string());
    for dir in defaults.split(':') {
        if !dir.is_empty() {
            dirs.push(PathBuf::from(dir));
        }
    }
    dirs
}

/// Scan every `applications` directory and return launchable entries sorted by
/// name. Hidden/NoDisplay entries and non-Application types are skipped; a
/// missing `Exec` also makes the entry unlaunchable.
pub fn load_apps(extra_dirs: &[PathBuf]) -> Vec<AppEntry> {
    let mut seen = std::collections::HashSet::new();
    let mut apps = Vec::new();
    for dir in data_dirs(extra_dirs) {
        let applications = dir.join("applications");
        let Ok(read_dir) = std::fs::read_dir(&applications) else {
            continue;
        };
        let mut files: Vec<PathBuf> = read_dir
            .filter_map(|entry| entry.ok())
            .map(|entry| entry.path())
            .filter(|path| path.extension().is_some_and(|ext| ext == "desktop"))
            .collect();
        files.sort();
        for path in files {
            let Some(id) = path.file_name().and_then(|name| name.to_str()) else {
                continue;
            };
            if !seen.insert(id.to_string()) {
                continue;
            }
            if let Some(app) = parse_entry(&path) {
                apps.push(app);
            }
        }
    }
    apps.sort_by(|a, b| {
        a.name
            .to_lowercase()
            .cmp(&b.name.to_lowercase())
            .then_with(|| a.desktop_path.cmp(&b.desktop_path))
    });
    apps
}

fn parse_entry(path: &Path) -> Option<AppEntry> {
    let content = std::fs::read_to_string(path).ok()?;
    let mut in_main = false;
    let mut name = String::new();
    let mut generic_name = String::new();
    let mut comment = String::new();
    let mut keywords = Vec::new();
    let mut exec = String::new();
    let mut categories = String::new();
    let mut entry_type = String::new();
    let mut hidden = false;
    let mut no_display = false;
    let mut try_exec = String::new();

    for raw_line in content.lines() {
        let line = raw_line.trim();
        if line.starts_with('[') {
            in_main = line == "[Desktop Entry]";
            continue;
        }
        if !in_main || line.starts_with('#') {
            continue;
        }
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let key = key.trim();
        let value = value.trim();
        match key {
            "Type" => entry_type = value.to_string(),
            "Name" => name = unescape_desktop(value),
            "GenericName" => generic_name = unescape_desktop(value),
            "Comment" => comment = unescape_desktop(value),
            "Keywords" => {
                keywords = value
                    .split(';')
                    .map(|word| unescape_desktop(word))
                    .filter(|word| !word.is_empty())
                    .collect()
            }
            "Exec" => exec = value.to_string(),
            "Categories" => categories = value.to_string(),
            "Hidden" => hidden = value.eq_ignore_ascii_case("true"),
            "NoDisplay" => no_display = value.eq_ignore_ascii_case("true"),
            "TryExec" => try_exec = value.to_string(),
            _ => {}
        }
    }

    if entry_type != "Application" || hidden || no_display || exec.is_empty() {
        return None;
    }
    if !try_exec.is_empty() && !binary_in_path(&try_exec) {
        return None;
    }
    Some(AppEntry {
        name: if name.is_empty() {
            path.file_stem()
                .and_then(|stem| stem.to_str())
                .unwrap_or("application")
                .to_string()
        } else {
            name
        },
        generic_name,
        comment,
        keywords,
        desktop_path: path.to_path_buf(),
        categories,
    })
}

fn binary_in_path(binary: &str) -> bool {
    let candidate = Path::new(binary);
    if candidate.is_absolute() || binary.contains('/') {
        return candidate.is_file();
    }
    let path = std::env::var_os("PATH").unwrap_or_default();
    std::env::split_paths(&path).any(|dir| dir.join(binary).is_file())
}

/// Freedesktop desktop-entry escapes (`\s`, `\n`, `\\`, ...).
fn unescape_desktop(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    let mut chars = value.chars();
    while let Some(ch) = chars.next() {
        if ch != '\\' {
            out.push(ch);
            continue;
        }
        match chars.next() {
            Some('s') => out.push(' '),
            Some('n') => out.push('\n'),
            Some('t') => out.push('\t'),
            Some('r') => out.push('\r'),
            Some('\\') => out.push('\\'),
            Some(';') => out.push(';'),
            Some(other) => out.push(other),
            None => out.push('\\'),
        }
    }
    out
}

/// Launch through the freedesktop handler. Detached stdio keeps the overlay
/// from holding the application's output pipe open.
pub fn launch(app: &AppEntry) -> Result<(), String> {
    let mut command = Command::new("gio");
    command.arg("launch").arg(&app.desktop_path);
    command.stdin(Stdio::null());
    command.stdout(Stdio::null());
    command.stderr(Stdio::null());
    let mut child = command
        .spawn()
        .map_err(|err| format!("cannot run gio launch: {}", err))?;
    // `gio launch` returns once the application has been spawned; waiting keeps
    // failures observable (a bad Exec line makes it exit non-zero).
    match child.wait() {
        Ok(status) if status.success() => Ok(()),
        Ok(status) => Err(format!("gio launch failed with {}", status)),
        Err(err) => Err(format!("wait for gio launch failed: {}", err)),
    }
}

/// Stable search ranking shared by IPC tests and the launcher:
/// 0 = name starts with the query, 1 = name contains it, 2 = generic name or
/// comment contains it, 3 = a keyword or category contains it, 4 = all query
/// tokens appear somewhere in the haystack. `None` means no match.
pub fn rank(app: &AppEntry, query: &str) -> Option<u8> {
    let query = query.trim().to_lowercase();
    if query.is_empty() {
        return Some(0);
    }
    let name = app.name.to_lowercase();
    if name.starts_with(&query) {
        return Some(0);
    }
    if name.contains(&query) {
        return Some(1);
    }
    if app.generic_name.to_lowercase().contains(&query)
        || app.comment.to_lowercase().contains(&query)
    {
        return Some(2);
    }
    if app
        .keywords
        .iter()
        .any(|keyword| keyword.to_lowercase().contains(&query))
        || app.categories.to_lowercase().contains(&query)
    {
        return Some(3);
    }
    let haystack = app.haystack();
    let tokens: Vec<&str> = query.split_whitespace().collect();
    if !tokens.is_empty() && tokens.iter().all(|token| haystack.contains(token)) {
        return Some(4);
    }
    None
}
