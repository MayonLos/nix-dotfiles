//! Fault-injection for lifecycle rules that real-server happy paths cannot cover.
use std::{
    fs,
    os::unix::fs::PermissionsExt,
    path::Path,
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant},
};
fn command(root: &Path, args: &[&str]) -> std::process::Output {
    Command::new(env!("CARGO_BIN_EXE_mcsrv-mayon"))
        .arg("--root")
        .arg(root.join("instances"))
        .args(args)
        .env("HOME", root)
        .env("XDG_RUNTIME_DIR", root.join("runtime"))
        .output()
        .unwrap()
}
fn fixture(root: &Path) {
    fs::create_dir_all(root.join("runtime")).unwrap();
    fs::set_permissions(root.join("runtime"), fs::Permissions::from_mode(0o700)).unwrap();
    let dir = root.join("instances/safe");
    fs::create_dir_all(dir.join("world")).unwrap();
    fs::write(dir.join("world/level.dat"), b"keep").unwrap();
    let shell = Command::new("bash")
        .args(["-c", "command -v bash"])
        .output()
        .unwrap();
    let shell = String::from_utf8(shell.stdout).unwrap();
    let java = root.join("fake-java");
    fs::write(&java,format!("#!{}\necho 'Done (0.1s)!'\nwhile IFS= read -r line; do\n case \"$line\" in\n stop) echo Stopping; sleep 6; exit 0;;\n save-off) echo 'Automatic saving is now disabled';;\n 'save-all flush'|save-all) echo 'Saved the game';;\n save-on) echo 'Automatic saving is now enabled';;\n list) echo 'There are 0 of a max of 20 players online: ';;\n esac\ndone\n",shell.trim())).unwrap();
    fs::set_permissions(&java, fs::Permissions::from_mode(0o700)).unwrap();
    let c = serde_json::json!({"name":"safe","kind":"vanilla","version":"1.21.11","memory_mb":1024,"port":25565,"online_mode":true,"whitelist":true,"java":java,"argv":[],"backup_minutes":0,"keep_last":20,"lan":false,"aikar":false,"rcon":true,"bind":"127.0.0.1"});
    fs::write(dir.join("instance.json"), serde_json::to_vec(&c).unwrap()).unwrap();
    fs::write(dir.join("server.properties"), "level-name=world\n").unwrap();
    fs::write(dir.join("rcon.secret"), "not-a-real-server-secret").unwrap();
}
fn start(root: &Path) -> std::process::Child {
    let mut p = Command::new(env!("CARGO_BIN_EXE_mcsrv-mayon"))
        .arg("--root")
        .arg(root.join("instances"))
        .args(["run", "safe"])
        .env("HOME", root)
        .env("XDG_RUNTIME_DIR", root.join("runtime"))
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .unwrap();
    let deadline = Instant::now() + Duration::from_secs(25);
    while Instant::now() < deadline {
        assert!(p.try_wait().unwrap().is_none());
        if root.join("instances/safe/java.pid").exists()
            && command(root, &["command", "safe", "list"]).status.success()
        {
            return p;
        }
        thread::sleep(Duration::from_millis(100));
    }
    let _ = p.kill();
    let _ = p.wait();
    panic!("private runner never became ready");
}
#[test]
fn stop_and_rcon_cannot_bypass_backup_guard() {
    use fs2::FileExt;
    let root = tempfile::tempdir().unwrap();
    fixture(root.path());
    let mut process = start(root.path());
    let path = root.path().join("instances/safe/operation.lock");
    let f = fs::OpenOptions::new().write(true).open(path).unwrap();
    f.lock_exclusive().unwrap();
    let output = command(root.path(), &["rcon", "safe", "save-on"]);
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("拒绝 RCON"));
    drop(f);
    assert!(command(root.path(), &["stop", "safe"]).status.success());
    let output = command(root.path(), &["backup", "safe"]);
    assert!(
        !output.status.success(),
        "backup raced a server shutting down"
    );
    let deadline = Instant::now() + Duration::from_secs(15);
    while process.try_wait().unwrap().is_none() {
        if Instant::now() > deadline {
            let _ = process.kill();
            panic!("stop did not complete");
        }
        thread::sleep(Duration::from_millis(50));
    }
    assert_eq!(
        fs::read(root.path().join("instances/safe/world/level.dat")).unwrap(),
        b"keep"
    );
}
#[test]
fn crashed_supervisor_cannot_leave_java_writing() {
    let root = tempfile::tempdir().unwrap();
    fixture(root.path());
    let mut process = start(root.path());
    let pid: i32 = fs::read_to_string(root.path().join("instances/safe/java.pid"))
        .unwrap()
        .parse()
        .unwrap();
    process.kill().unwrap();
    process.wait().unwrap();
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        match fs::read_to_string(format!("/proc/{pid}/status")) {
            Err(_) => break,
            Ok(s)
                if s.lines()
                    .any(|l| l.starts_with("State:") && l.contains('Z')) =>
            {
                break
            }
            _ => (),
        }
        assert!(Instant::now() < deadline, "Java survived its supervisor");
        thread::sleep(Duration::from_millis(50));
    }
}
