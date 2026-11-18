//! 【应用设置】【故障修复】先保存原始备份，再修复可定位的无效字段，禁止无备份覆盖
use std::{
    io,
    path::{Path, PathBuf},
};

/// 【应用设置】【备份修复】按 path 在共享锁内备份原文并移除非法字段，JSON 语法损坏恢复空对象，返回备份路径
pub fn repair(path: &Path) -> io::Result<PathBuf> {
    use io::Write;
    super::persistence::update(path, |text| {
        let parent = path.parent().unwrap_or(Path::new("."));
        let mut backup = tempfile::Builder::new()
            .prefix("config-broken-")
            .suffix(".bak")
            .tempfile_in(parent)?;
        backup.write_all(text.as_bytes())?;
        backup.as_file().sync_all()?;
        let (_, backup_path) = backup.keep().map_err(|error| error.error)?;
        let repaired = if super::document::is_json(path, text) {
            json_repaired(path, text)?
        } else {
            repair_toml(text)?
        };
        Ok((repaired, backup_path))
    })
}

/// 【应用设置】【JSON 修复】按 path、text 只删除类型解码拒绝的字段；语法无法解析时才恢复空对象
fn json_repaired(path: &Path, text: &str) -> io::Result<String> {
    let Ok(root) = super::document::root(path, text) else {
        return Ok("{}\n".into());
    };
    let (cleaned, removed) = super::legacy::recover_root(&root)
        .map_err(|error| io::Error::other(format!("无法定位无效字段：{error}；原文已备份")))?;
    if removed.is_empty() {
        return Ok(text.into());
    }
    for (field, value) in &removed {
        log::warn!("config: repaired by removing invalid `{field}` ({value})");
    }
    Ok(serde_json::to_string_pretty(&cleaned).map_err(io::Error::other)? + "\n")
}

/// 【应用设置】【语法修复】按 text 逐行移除解析错误，保留合法字段、注释与未知键；无法定位返回错误
fn repair_toml(text: &str) -> io::Result<String> {
    let mut text = text.to_owned();
    for _ in 0..super::loading::MAX_BAD_LINES {
        let error = match toml::from_str::<super::Config>(&text) {
            Ok(_) => return Ok(text),
            Err(error) => error,
        };
        let span = error
            .span()
            .ok_or_else(|| io::Error::other(error.to_string()))?;
        let position = span.start.min(text.len());
        let start = text[..position].rfind('\n').map_or(0, |index| index + 1);
        let end = text[position..]
            .find('\n')
            .map_or(text.len(), |index| position + index);
        if start == end {
            return Err(io::Error::other("无法定位错误行；原文已备份"));
        }
        text.replace_range(start..end, "");
    }
    Err(io::Error::other("配置错误过多；原文已备份，请检查备份文件"))
}

#[cfg(test)]
mod tests {
    use super::*;
    /// 【应用设置】【修复回归】无参数，语法错误修复保留原文备份、合法设置与未知字段
    #[test]
    fn repair_keeps_original_and_valid_settings() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("config.toml");
        let text =
            "# kept\n[save]\ndirectory=\"unfinished\nfilename_format=\"%Y\"\n[custom]\nnumber=7\n";
        std::fs::write(&path, text).unwrap();
        let backup = repair(&path).unwrap();
        assert_eq!(std::fs::read_to_string(backup).unwrap(), text);
        let repaired = std::fs::read_to_string(&path).unwrap();
        assert!(repaired.contains("# kept") && repaired.contains("number=7"));
        assert_eq!(
            super::super::preferences::load(&path)
                .unwrap()
                .save
                .filename_format,
            "%Y"
        );
    }

    /// 【应用设置】【JSON 修复】无参数，只移除类型无效字段，保留其他设置、未知键和原文件备份
    #[test]
    fn json_repair_removes_only_invalid_fields() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("config.json");
        let text = r#"{"toolbar":{"fontSize":"middle","iconSize":"middle"},"save":{"directory":"shots"},"custom":{"keep":"yes"}}"#;
        std::fs::write(&path, text).unwrap();
        let backup = repair(&path).unwrap();
        assert_eq!(std::fs::read_to_string(backup).unwrap(), text);
        let repaired = std::fs::read_to_string(&path).unwrap();
        super::super::legacy::decode(&repaired).unwrap();
        let root: serde_json::Value = serde_json::from_str(&repaired).unwrap();
        assert_eq!(root["save"]["directory"], "shots");
        assert_eq!(root["custom"]["keep"], "yes");
        assert!(root["toolbar"].get("fontSize").is_none());
        assert!(root["toolbar"].get("iconSize").is_none());
    }

    /// 【应用设置】【JSON 语法】无参数，语法损坏无法定位字段时备份后恢复空对象
    #[test]
    fn unparseable_json_repair_resets_to_empty_object() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("config.json");
        let text = "{\"save\": {\"directory\": unfinished";
        std::fs::write(&path, text).unwrap();
        let backup = repair(&path).unwrap();
        assert_eq!(std::fs::read_to_string(backup).unwrap(), text);
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "{}\n");
    }
}
