use super::*;
use serde_json::json;
use std::collections::BTreeMap;

/// 【上传测试】【配置别名】验证原版顶层和字段别名、对象存在性、非法类型及环境覆盖优先级
#[test]
fn aliases_and_environment_priority_match_original() {
    for key in ["upload", "imageUpload", "uploader", "imageHost"] {
        let upload = Upload::from_root(
            &json!({key: {"path":"  program {image}  ", "timeoutMs":-5,"variables":{" TOKEN ":"value", "":"skip", "number":7}}}),
        );
        assert_eq!(upload.command, "program {image}");
        assert_eq!(upload.timeout_ms, 1000);
        assert_eq!(
            upload.env,
            BTreeMap::from([("TOKEN".into(), "value".into())])
        );
    }
    assert_eq!(
        Upload::from_root(&json!({"upload":{},"uploader":{"command":"later"}})),
        Upload::default()
    );
    let config = Upload::from_value(
        &json!({"command":false,"helper":"helper", "env":{"TOKEN":"configured", "MARK_SHOT_UPLOAD_COMMAND":"child-only"}}),
    );
    let system = BTreeMap::from([
        ("TOKEN".into(), "system".into()),
        ("MARK_SHOT_UPLOAD_COMMAND".into(), " override ".into()),
        ("MARK_SHOT_UPLOAD_TIMEOUT_MS".into(), " 3000 ".into()),
    ]);
    let effective = config.effective(&system);
    assert_eq!(effective.command, "override");
    assert_eq!(effective.timeout_ms, 3000);
    assert_eq!(effective.env["TOKEN"], "configured");
    assert_eq!(effective.env["MARK_SHOT_UPLOAD_COMMAND"], "child-only");
    let debug = format!("{effective:?}");
    assert!(
        !debug.contains("configured")
            && !debug.contains("override")
            && !debug.contains("child-only")
    );
}

/// 【上传测试】【独立读取】验证 TOML 与原版 JSON 上传配置相同，文件完整保留，配置读取不修改凭据或未知字段
#[test]
fn json_and_toml_upload_files_remain_unchanged() {
    let directory = tempfile::tempdir().unwrap();
    for (name, text) in [
        (
            "config.json",
            r#"{"imageUpload":{"command":"upload {image}","timeoutMs":2500,"environment":{"TOKEN":"secret"}},"other":"keep"}"#,
        ),
        (
            "config.toml",
            "[upload]\ncommand='upload {image}'\ntimeout_ms=2500\n[upload.env]\nTOKEN='secret'\n",
        ),
    ] {
        let path = directory.path().join(name);
        std::fs::write(&path, text).unwrap();
        let config = mark_shot::config::upload::read_at(&path).unwrap();
        assert_eq!(config.command, "upload {image}");
        assert_eq!(config.timeout_ms, 2500);
        assert_eq!(config.env["TOKEN"], "secret");
        assert_eq!(std::fs::read_to_string(path).unwrap(), text);
    }
}

/// 【上传测试】【设置保存】设置窗口写入 upload.env 后，原生 TOML 与原版 JSON 兼容分组都必须能被上传配置读取
#[test]
fn settings_window_environment_edits_persist_for_both_config_formats() {
    let directory = tempfile::tempdir().unwrap();
    let environment = serde_json::json!({
        "MARK_SHOT_UPLOAD_URL":"https://images.example/upload",
        "MARK_SHOT_UPLOAD_API_KEY":"local-token"
    });

    let toml = directory.path().join("config.toml");
    std::fs::write(&toml, "[history]\nlimit = 50\n").unwrap();
    mark_shot::config::preferences::write(&toml, "upload", "env", environment.clone()).unwrap();
    let text = std::fs::read_to_string(&toml).unwrap();
    assert!(
        text.contains("MARK_SHOT_UPLOAD_URL") && text.contains("[history]"),
        "{text}"
    );
    let upload = mark_shot::config::upload::read_at(&toml).unwrap();
    assert_eq!(
        upload.env["MARK_SHOT_UPLOAD_URL"],
        "https://images.example/upload"
    );
    assert_eq!(upload.env["MARK_SHOT_UPLOAD_API_KEY"], "local-token");

    for group in ["imageUpload", "uploader", "imageHost"] {
        let path = directory.path().join(format!("{group}.json"));
        std::fs::write(
            &path,
            format!(r#"{{"{group}":{{"command":"old {{image}}","timeoutMs":2500}},"other":7}}"#),
        )
        .unwrap();
        mark_shot::config::preferences::write(&path, "upload", "env", environment.clone()).unwrap();
        let text = std::fs::read_to_string(&path).unwrap();
        let root: serde_json::Value = serde_json::from_str(&text).unwrap();
        assert_eq!(root["other"], 7, "{text}");
        let upload = mark_shot::config::upload::read_at(&path).unwrap();
        assert_eq!(
            upload.env["MARK_SHOT_UPLOAD_URL"], "https://images.example/upload",
            "{group}: {text}"
        );
        assert_eq!(upload.command, "old {image}", "{group}: {text}");
        assert_eq!(upload.timeout_ms, 2500, "{group}: {text}");
    }
}

/// 【上传测试】【设置校验】设置窗口拒绝不是字符串映射的环境，失败时不修改原文件
#[test]
fn settings_window_rejects_invalid_environment_without_writing() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("config.toml");
    let original = "[upload]\ncommand = 'old'\n";
    std::fs::write(&path, original).unwrap();
    for value in [
        serde_json::json!("not-an-object"),
        serde_json::json!({"MARK_SHOT_UPLOAD_URL":7}),
        serde_json::json!(["MARK_SHOT_UPLOAD_URL", "https://images.example/upload"]),
    ] {
        assert!(
            mark_shot::config::preferences::write(&path, "upload", "env", value).is_err(),
            "invalid upload environment was accepted"
        );
        assert_eq!(std::fs::read_to_string(&path).unwrap(), original);
    }
}

/// 【上传测试】【真实容错】无关字段类型错误不能再阻止保存上传环境，其余配置与未知键保持原样
#[test]
fn stale_invalid_unrelated_json_field_does_not_block_upload_environment_save() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("config.json");
    std::fs::write(
        &path,
        r#"{"toolbar":{"fontSize":"middle","iconSize":"middle"},"save":{"directory":"shots"},"custom":{"keep":"yes"}}"#,
    )
    .unwrap();
    mark_shot::config::preferences::write(
        &path,
        "upload",
        "env",
        serde_json::json!({"MARK_SHOT_UPLOAD_URL":"https://images.example/recovered"}),
    )
    .unwrap();
    let text = std::fs::read_to_string(&path).unwrap();
    let root: serde_json::Value = serde_json::from_str(&text).unwrap();
    assert_eq!(root["custom"]["keep"], "yes", "{text}");
    assert_eq!(root["save"]["directory"], "shots", "{text}");
    assert!(root["toolbar"].get("fontSize").is_none(), "{text}");
    let upload = mark_shot::config::upload::read_at(&path).unwrap();
    assert_eq!(
        upload.env["MARK_SHOT_UPLOAD_URL"],
        "https://images.example/recovered"
    );
}

/// 【上传测试】【通知合并】验证后台通知唤醒真实描述符，消费后恢复无事件，不依赖周期计时器
#[test]
fn overlay_wake_blocks_without_work_and_drains_notifications() {
    let source = mark_shot::backend::task_wake::Source::new().unwrap();
    let wake = source.wake();
    #[cfg(target_os = "linux")]
    {
        use rustix::event::{PollFd, PollFlags, poll};
        let mut fds = [PollFd::new(&source, PollFlags::IN)];
        assert_eq!(poll(&mut fds, Some(&Default::default())).unwrap(), 0);
        for _ in 0..10 {
            wake.notify();
        }
        assert_eq!(poll(&mut fds, Some(&Default::default())).unwrap(), 1);
        source.drain().unwrap();
        assert_eq!(poll(&mut fds, Some(&Default::default())).unwrap(), 0);
    }
    #[cfg(target_os = "windows")]
    {
        use mark_shot::backend::windows::native::{Wait, dispatch};
        let handles = [source.handle()];
        let timeout = Some(std::time::Duration::ZERO);
        assert_eq!(dispatch(&handles, timeout).unwrap(), Wait::Timeout);
        for _ in 0..10 {
            wake.notify();
        }
        assert_eq!(dispatch(&handles, timeout).unwrap(), Wait::Source(0));
        assert_eq!(dispatch(&handles, timeout).unwrap(), Wait::Timeout);
    }
}
