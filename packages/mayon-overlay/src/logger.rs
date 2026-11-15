//! Append-only JSON-lines event log.
//!
//! The overlay is normally started from a key binding, so its stdout/stderr are
//! invisible. Everything a user or a test needs to verify (copy result, paste
//! injection result, launch result) is written here as one JSON object per
//! line. The file is optional: without `--log` the logger is a no-op.

use std::fs::{File, OpenOptions};
use std::io::Write;
use std::path::Path;
use std::sync::{Arc, Mutex};

#[derive(Clone)]
pub struct Logger {
    file: Option<Arc<Mutex<File>>>,
}

impl Logger {
    pub fn open(path: Option<&Path>) -> Logger {
        let file = path.and_then(|path| {
            if let Some(parent) = path.parent() {
                let _ = std::fs::create_dir_all(parent);
            }
            OpenOptions::new().create(true).append(true).open(path).ok()
        });
        Logger {
            file: file.map(|file| Arc::new(Mutex::new(file))),
        }
    }

    pub fn event(&self, name: &str, fields: &[(&str, String)]) {
        let Some(file) = &self.file else {
            return;
        };
        let ts = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis())
            .unwrap_or(0);
        let mut line = format!("{{\"ts\":{},\"event\":\"{}\"", ts, escape(name));
        for (key, value) in fields {
            line.push_str(&format!(",\"{}\":{}", escape(key), value));
        }
        line.push('}');
        if let Ok(mut file) = file.lock() {
            let _ = writeln!(file, "{}", line);
            let _ = file.flush();
        }
    }
}

/// JSON string encoder for the subset of text this program logs.
pub fn escape(text: &str) -> String {
    let mut out = String::with_capacity(text.len() + 2);
    for ch in text.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            ch if (ch as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", ch as u32)),
            ch => out.push(ch),
        }
    }
    out
}

pub fn json_string(text: &str) -> String {
    format!("\"{}\"", escape(text))
}
