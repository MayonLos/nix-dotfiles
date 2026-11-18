//! 【配置恢复测试】【JSON 容错】验证非法字段不拖垮整份配置，保存与修复都只丢弃非法值

use crate::config::{legacy, loading, recovery, settings_store};

const BROKEN: &str = r#"{
  "toolbar": {"fontSize": "middle", "iconSize": "middle"},
  "save": {"directory": "shots", "filename_format": "%Y-%m-%d"},
  "translation": {"targetLanguage": "English", "apiKey": "local-test-value"},
  "custom": {"keep": "yes"}
}"#;

/// 【配置恢复测试】【启动容错】无参数，非法工具栏值回退默认，其他合法分组与未知键照常生效
#[test]
fn startup_keeps_valid_settings_around_invalid_fields() {
    let config = loading::parse(BROKEN, "config.json");
    assert_eq!(
        config.toolbar.font_size,
        crate::config::Toolbar::default().font_size
    );
    assert_eq!(
        config.toolbar.icon_size,
        crate::config::Toolbar::default().icon_size
    );
    assert_eq!(config.save.directory, "shots");
    assert_eq!(config.translation.target_language, "English");
}

/// 【配置恢复测试】【字段报告】无参数，容错解码报告具体路径而不是整份回退
#[test]
fn tolerant_decode_reports_removed_fields() {
    let recovered = legacy::decode_recovering(BROKEN).unwrap();
    let fields: Vec<&str> = recovered
        .removed
        .iter()
        .map(|(field, _)| field.as_str())
        .collect();
    assert!(fields.contains(&"toolbar.fontSize"), "{fields:?}");
    assert!(fields.contains(&"toolbar.iconSize"), "{fields:?}");
    assert_eq!(recovered.config.save.directory, "shots");
}

/// 【配置恢复测试】【保存容错】无参数，无关非法字段不阻塞保存，保存后文件可被严格解码
#[test]
fn settings_save_repairs_unrelated_invalid_fields() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("config.json");
    std::fs::write(&path, BROKEN).unwrap();
    settings_store::write(&path, &[("ui.language".into(), "chinese".into())]).unwrap();
    let text = std::fs::read_to_string(&path).unwrap();
    let config = legacy::decode(&text).unwrap();
    assert_eq!(config.ui.language, "chinese");
    assert_eq!(config.save.directory, "shots");
    assert_eq!(config.translation.target_language, "English");
    let root = settings_store::source(&path).unwrap();
    assert_eq!(root["custom"]["keep"], "yes");
    assert_eq!(root["translation"]["apiKey"], "local-test-value");
    assert!(root["toolbar"].get("fontSize").is_none());
}

/// 【配置恢复测试】【修复边界】无参数，多个非法字段可一次剔除，未知键与旧分组保持原样
#[test]
fn recovery_removes_every_invalid_field_in_original_shape() {
    let text = r#"{"toolbar":{"fontSize":"middle"},"ocr":{"mode":"bogus"},"captureHistory":{"limit":23},"unknown":{"a":1}}"#;
    let root: serde_json::Value = serde_json::from_str(text).unwrap();
    let (cleaned, removed) = legacy::recover_root(&root).unwrap();
    assert_eq!(removed.len(), 2, "{removed:?}");
    assert!(legacy::decode(&cleaned.to_string()).is_ok());
    assert_eq!(cleaned["captureHistory"]["limit"], 23);
    assert_eq!(cleaned["unknown"]["a"], 1);
    assert!(cleaned["toolbar"].get("fontSize").is_none());
}

/// 【配置恢复测试】【修复写入】无参数，配置修复入口对 JSON 只删非法字段并保留备份
#[test]
fn repair_keeps_file_shape_and_other_sections() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("config.json");
    std::fs::write(&path, BROKEN).unwrap();
    recovery::repair(&path).unwrap();
    let text = std::fs::read_to_string(&path).unwrap();
    assert!(!text.contains("middle"));
    let config = legacy::decode(&text).unwrap();
    assert_eq!(config.save.directory, "shots");
    assert_eq!(config.translation.target_language, "English");
    let root = settings_store::source(&path).unwrap();
    assert_eq!(root["custom"]["keep"], "yes");
}
