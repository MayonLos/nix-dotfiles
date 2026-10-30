//! Real local-restic tests: no network, user services or user data.
use fs2::FileExt;
use std::{
    fs,
    os::unix::fs::PermissionsExt,
    path::Path,
    process::{Command, Output},
};
fn cli(root: &Path, args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_mcsrv-mayon"))
        .arg("--root")
        .arg(root)
        .args(args)
        .env("HOME", root)
        .output()
        .unwrap()
}
fn ok(out: Output) -> String {
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8(out.stdout).unwrap()
}
fn fixture(root: &Path) {
    let dir = root.join("safe");
    fs::create_dir_all(dir.join("world")).unwrap();
    fs::write(dir.join("world/level.dat"), b"original-world").unwrap();
    fs::write(dir.join("server.properties"), "level-name=world\n").unwrap();
    let config = serde_json::json!({"name":"safe","kind":"vanilla","version":"1.21.11","memory_mb":1024,"port":25565,"online_mode":true,"whitelist":true,"java":"/not-run/java","argv":["-jar","server.jar"],"backup_minutes":30,"keep_last":20,"lan":false,"aikar":false,"rcon":false,"bind":"127.0.0.1"});
    fs::write(
        dir.join("instance.json"),
        serde_json::to_vec(&config).unwrap(),
    )
    .unwrap();
}
#[test]
fn backup_restore_preserves_replaced_world_and_old_dimensions() {
    let root = tempfile::tempdir().unwrap();
    fixture(root.path());
    ok(cli(root.path(), &["backup", "safe"]));
    let snapshots: serde_json::Value =
        serde_json::from_str(&ok(cli(root.path(), &["backups", "safe"]))).unwrap();
    let id = snapshots[0]["id"].as_str().unwrap();
    let dir = root.path().join("safe");
    fs::write(dir.join("world/level.dat"), b"new-world").unwrap();
    fs::create_dir(dir.join("world_nether")).unwrap();
    fs::write(dir.join("world_nether/region"), b"new-dimension").unwrap();
    assert!(
        !cli(root.path(), &["restore", "safe", id, "--confirm", "bad"])
            .status
            .success()
    );
    assert_eq!(fs::read(dir.join("world/level.dat")).unwrap(), b"new-world");
    let lock = fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(false)
        .open(dir.join("run.lock"))
        .unwrap();
    lock.lock_exclusive().unwrap();
    assert!(!cli(root.path(), &["restore", "safe", id, "--confirm", id])
        .status
        .success());
    drop(lock);
    ok(cli(root.path(), &["restore", "safe", id, "--confirm", id]));
    assert_eq!(
        fs::read(dir.join("world/level.dat")).unwrap(),
        b"original-world"
    );
    assert!(!dir.join("world_nether").exists());
    let old = fs::read_dir(dir.join("rollback-preserved"))
        .unwrap()
        .next()
        .unwrap()
        .unwrap()
        .path();
    assert_eq!(fs::read(old.join("world/level.dat")).unwrap(), b"new-world");
    assert_eq!(
        fs::read(old.join("world_nether/region")).unwrap(),
        b"new-dimension"
    );
    assert_eq!(
        fs::metadata(dir.join("backups/password"))
            .unwrap()
            .permissions()
            .mode()
            & 0o777,
        0o600
    );
    assert_eq!(
        fs::metadata(dir.join("backups"))
            .unwrap()
            .permissions()
            .mode()
            & 0o777,
        0o700
    );
}
#[test]
fn paths_and_external_world_symlink_are_rejected() {
    let root = tempfile::tempdir().unwrap();
    fixture(root.path());
    let outside = tempfile::tempdir().unwrap();
    fs::write(outside.path().join("sentinel"), b"keep").unwrap();
    std::os::unix::fs::symlink(outside.path(), root.path().join("safe/world_the_end")).unwrap();
    assert!(!cli(root.path(), &["backup", "safe"]).status.success());
    assert!(!cli(
        root.path(),
        &["restore", "../safe", "deadbeef", "--confirm", "deadbeef"]
    )
    .status
    .success());
    assert_eq!(fs::read(outside.path().join("sentinel")).unwrap(), b"keep");
}

#[test]
fn effective_properties_override_creation_flags_and_decode_java_ipv6() {
    let root = tempfile::tempdir().unwrap();
    fixture(root.path());
    fs::write(root.path().join("safe/server.properties"),"level-name=world\nwhite-list=false\nonline-mode=false\nserver-ip=\\:\\:1\nserver-port=25566\n").unwrap();
    let list: serde_json::Value = serde_json::from_str(&ok(cli(root.path(), &["list"]))).unwrap();
    assert_eq!(list[0]["bind"], "::1");
    assert_eq!(list[0]["port"], 25566);
    assert_eq!(list[0]["whitelist"], false);
    assert_eq!(list[0]["online_mode"], false);
}

#[test]
fn mod_writer_rejects_external_directory_before_network() {
    let root = tempfile::tempdir().unwrap();
    fixture(root.path());
    fs::write(
        root.path().join("safe/installed.json"),
        r#"{"loader":"fabric"}"#,
    )
    .unwrap();
    let outside = tempfile::tempdir().unwrap();
    fs::write(outside.path().join("keep.jar"), b"keep").unwrap();
    std::os::unix::fs::symlink(outside.path(), root.path().join("safe/mods")).unwrap();
    for args in [
        vec!["mods", "safe", "install", "should-never-contact-network"],
        vec!["mods", "safe", "update"],
    ] {
        let out = cli(root.path(), &args);
        assert!(!out.status.success());
        assert!(String::from_utf8_lossy(&out.stderr).contains("符号链接"));
    }
    assert_eq!(fs::read(outside.path().join("keep.jar")).unwrap(), b"keep");
    assert_eq!(fs::read_dir(outside.path()).unwrap().count(), 1);
}
