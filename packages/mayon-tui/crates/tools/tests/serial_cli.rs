use std::process::Command;
#[test]
fn cli_help_list_and_errors_do_not_create_state() {
    let temp = tempfile::tempdir().unwrap();
    for (args, success) in [
        (vec!["--help"], true),
        (vec!["list"], true),
        (vec!["--bad-option"], false),
        (vec!["list", "extra"], false),
        (vec!["/dev/pts/not-opened", "-b", "0"], false),
    ] {
        let output = Command::new(env!("CARGO_BIN_EXE_mayon-tools"))
            .arg("serial")
            .args(&args)
            .env("HOME", temp.path())
            .env("XDG_CONFIG_HOME", temp.path().join("config"))
            .env("XDG_DATA_HOME", temp.path().join("data"))
            .output()
            .unwrap();
        assert_eq!(
            output.status.success(),
            success,
            "{args:?}: {}",
            String::from_utf8_lossy(&output.stderr)
        );
    }
    assert!(!temp.path().join("config").exists());
    assert!(!temp.path().join("data").exists());
}
