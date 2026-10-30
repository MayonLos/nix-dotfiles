//! A hostile frpc fixture tries to print its token: the manager must discard it.
use std::{
    fs,
    os::unix::fs::PermissionsExt,
    path::Path,
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant},
};
fn cli(root: &Path, args: &[&str]) -> std::process::Output {
    Command::new(env!("CARGO_BIN_EXE_mcsrv-mayon"))
        .arg("--root")
        .arg(root.join("data"))
        .args(args)
        .env("HOME", root)
        .env("XDG_RUNTIME_DIR", root.join("runtime"))
        .output()
        .unwrap()
}
#[test]
fn token_never_reaches_argv_or_logs_and_owned_child_exits() {
    let tmp = tempfile::tempdir().unwrap();
    let root = tmp.path();
    for dir in ["data/friends", "bin", "runtime"] {
        fs::create_dir_all(root.join(dir)).unwrap();
    }
    fs::set_permissions(root.join("runtime"), fs::Permissions::from_mode(0o700)).unwrap();
    let shell = Command::new("bash")
        .args(["-c", "command -v bash"])
        .output()
        .unwrap();
    let shell = String::from_utf8(shell.stdout).unwrap();
    let script=format!("#!{}\n[ -z \"${{http_proxy+x}}\" ] || exit 13\nprintf '%s\\n' \"$@\" > {}/argv\nprintf '%s' \"$$\" > {}/pid\nstat -c %a \"$2\" > {}/mode\ncat \"$2\"\ncat \"$2\" >&2\nexec sleep 120\n",shell.trim(),root.display(),root.display(),root.display());
    fs::write(root.join("bin/frpc"), script).unwrap();
    fs::set_permissions(root.join("bin/frpc"), fs::Permissions::from_mode(0o700)).unwrap();
    let java = root.join("bin/java");
    fs::write(
        &java,
        format!(
            "#!{}\nwhile IFS= read -r line; do case \"$line\" in stop) exit 0;; esac; done\n",
            shell.trim()
        ),
    )
    .unwrap();
    fs::set_permissions(&java, fs::Permissions::from_mode(0o700)).unwrap();
    let dir = root.join("data/friends");
    fs::write(dir.join("instance.json"),serde_json::to_vec(&serde_json::json!({"name":"friends","kind":"vanilla","version":"1.21.1","memory_mb":1024,"port":25565,"online_mode":true,"whitelist":true,"java":java,"argv":[],"backup_minutes":0,"keep_last":20,"lan":false,"aikar":false,"rcon":false,"bind":""})).unwrap()).unwrap();
    fs::write(dir.join("rcon.secret"), "rcon-fixture").unwrap();
    fs::write(dir.join("server.properties"), "level-name=world\n").unwrap();
    let token = root.join("token");
    let secret = "fixture-secret-never-in-output";
    fs::write(&token, secret).unwrap();
    fs::set_permissions(&token, fs::Permissions::from_mode(0o600)).unwrap();
    let setup = cli(
        root,
        &[
            "frp",
            "set",
            "friends",
            "--server",
            "127.0.0.1",
            "--remote-port",
            "25570",
            "--token-file",
            token.to_str().unwrap(),
        ],
    );
    assert!(setup.status.success());
    assert!(!String::from_utf8_lossy(&setup.stdout).contains(secret));
    let mut runner = Command::new(env!("CARGO_BIN_EXE_mcsrv-mayon"))
        .arg("--root")
        .arg(root.join("data"))
        .args(["run", "friends"])
        .env(
            "PATH",
            format!(
                "{}:{}",
                root.join("bin").display(),
                std::env::var("PATH").unwrap()
            ),
        )
        .env("XDG_RUNTIME_DIR", root.join("runtime"))
        .env("http_proxy", "http://invalid-fixture-proxy:1")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let deadline = Instant::now() + Duration::from_secs(10);
    while !root.join("mode").exists() {
        assert!(runner.try_wait().unwrap().is_none());
        assert!(Instant::now() < deadline);
        thread::sleep(Duration::from_millis(50));
    }
    assert_eq!(fs::read_to_string(root.join("mode")).unwrap().trim(), "600");
    assert!(!fs::read_to_string(root.join("argv"))
        .unwrap()
        .contains(secret));
    let pid = fs::read_to_string(root.join("pid")).unwrap();
    assert!(!fs::read(format!("/proc/{pid}/cmdline"))
        .unwrap()
        .windows(secret.len())
        .any(|w| w == secret.as_bytes()));
    assert!(cli(root, &["stop", "friends"]).status.success());
    let output = runner.wait_with_output().unwrap();
    assert!(output.status.success());
    assert!(!String::from_utf8_lossy(&output.stdout).contains(secret));
    assert!(!String::from_utf8_lossy(&output.stderr).contains(secret));
    assert!(!fs::read_to_string(dir.join("console.log"))
        .unwrap()
        .contains(secret));
    assert!(!Path::new(&format!("/proc/{pid}")).exists());
    assert_eq!(
        fs::read_dir(root.join("runtime/mcsrv-frp"))
            .unwrap()
            .count(),
        0
    );
}
