use mayon_voice::runtime;
use serde::{Deserialize, Serialize};
use std::{
    fs,
    io::{Read, Write},
    os::unix::fs::OpenOptionsExt,
    path::{Path, PathBuf},
    process::{Command, Output, Stdio},
    sync::{mpsc, OnceLock},
    thread,
    time::{Duration, Instant},
};

#[derive(Clone, Debug, Deserialize, Serialize)]
struct NotificationId {
    owner: String,
    id: u32,
}

impl NotificationId {
    fn for_owner(&self, owner: &str) -> u32 {
        if self.owner == owner {
            self.id
        } else {
            0
        }
    }
}

enum Notice {
    Show(&'static str),
    Close(mpsc::Sender<()>),
}

static NOTICES: OnceLock<Option<mpsc::SyncSender<Notice>>> = OnceLock::new();

fn bounded_output(program: &str, args: &[&str]) -> Option<Output> {
    let mut child = Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .ok()?;
    let deadline = Instant::now() + Duration::from_millis(300);
    loop {
        if child.try_wait().ok()?.is_some() {
            return child.wait_with_output().ok().filter(|o| o.status.success());
        }
        if Instant::now() >= deadline {
            let _ = child.kill();
            let _ = child.wait();
            return None;
        }
        thread::sleep(Duration::from_millis(5));
    }
}

fn notification_owner() -> Option<String> {
    let result = bounded_output(
        "busctl",
        &[
            "--user",
            "--timeout=250ms",
            "call",
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "GetNameOwner",
            "s",
            "org.freedesktop.Notifications",
        ],
    )?;
    let output = std::str::from_utf8(&result.stdout)
        .ok()?
        .trim()
        .strip_prefix("s ")?;
    let owner: String = serde_json::from_str(output).ok()?;
    owner.starts_with(':').then_some(owner)
}

fn close_id(state: &NotificationId) -> bool {
    if notification_owner().as_deref() != Some(state.owner.as_str()) {
        return false;
    }
    bounded_output(
        "busctl",
        &[
            "--user",
            "--timeout=250ms",
            "call",
            "org.freedesktop.Notifications",
            "/org/freedesktop/Notifications",
            "org.freedesktop.Notifications",
            "CloseNotification",
            "u",
            &state.id.to_string(),
        ],
    )
    .is_some()
}

fn read_id(path: &Path) -> Option<NotificationId> {
    let input = fs::OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NOFOLLOW)
        .open(path)
        .ok()?;
    let mut value = String::new();
    input.take(1024).read_to_string(&mut value).ok()?;
    let state: NotificationId = serde_json::from_str(&value).ok()?;
    (state.id != 0 && state.owner.starts_with(':')).then_some(state)
}

fn save_id(path: &Path, state: &NotificationId) {
    let temporary = path.with_extension(format!("{}.tmp", std::process::id()));
    let result = (|| -> std::io::Result<()> {
        let mut file = fs::OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .mode(0o600)
            .custom_flags(libc::O_NOFOLLOW)
            .open(&temporary)?;
        serde_json::to_writer(&mut file, state)?;
        file.flush()?;
        fs::rename(&temporary, path)
    })();
    if result.is_err() {
        let _ = fs::remove_file(temporary);
    }
}

struct Notifications {
    path: PathBuf,
    state: Option<NotificationId>,
}
impl Notifications {
    fn new(path: PathBuf) -> Self {
        let mut state = read_id(&path);
        if let Some(old) = &state {
            match notification_owner() {
                Some(owner) if owner != old.owner => state = None,
                Some(_) if close_id(old) => state = None,
                _ => {}
            }
        }
        if state.is_none() {
            let _ = fs::remove_file(&path);
        }
        Self { path, state }
    }

    fn show(&mut self, body: &'static str) {
        let owner = notification_owner();
        let replaces = owner
            .as_deref()
            .and_then(|o| self.state.as_ref().map(|state| state.for_owner(o)))
            .unwrap_or(0);
        let timeout = if body.starts_with("录音中")
            || body.starts_with("识别中")
            || body.starts_with("正在识别")
        {
            "900000"
        } else {
            "4000"
        };
        let Some(output) = bounded_output(
            "notify-send",
            &[
                "-a",
                "mayon-voice",
                "-p",
                "-r",
                &replaces.to_string(),
                "-h",
                "boolean:transient:true",
                "-t",
                timeout,
                "语音输入",
                body,
            ],
        ) else {
            return;
        };
        let Some(id) = std::str::from_utf8(&output.stdout)
            .ok()
            .and_then(|s| s.trim().parse::<u32>().ok())
            .filter(|id| *id != 0)
        else {
            return;
        };
        if let Some(owner) = owner.or_else(notification_owner) {
            let state = NotificationId { owner, id };
            save_id(&self.path, &state);
            self.state = Some(state);
        }
    }

    fn close(&mut self) {
        if self.state.as_ref().is_some_and(|state| !close_id(state)) {
            return;
        }
        self.state = None;
        let _ = fs::remove_file(&self.path);
    }
}

fn sender() -> Option<&'static mpsc::SyncSender<Notice>> {
    NOTICES
        .get_or_init(|| {
            let path = runtime().ok()?.join("notification.json");
            let (tx, rx) = mpsc::sync_channel(8);
            thread::spawn(move || {
                let mut notifications = Notifications::new(path);
                for notice in rx {
                    match notice {
                        Notice::Show(body) => notifications.show(body),
                        Notice::Close(done) => {
                            notifications.close();
                            let _ = done.send(());
                            break;
                        }
                    }
                }
            });
            Some(tx)
        })
        .as_ref()
}

pub fn startup() {
    let _ = sender();
}

pub fn notify(body: &'static str) {
    if let Some(sender) = sender() {
        let _ = sender.try_send(Notice::Show(body));
    }
}

pub fn shutdown() {
    if let Some(sender) = sender() {
        let (done, rx) = mpsc::channel();
        if sender.try_send(Notice::Close(done)).is_ok() {
            let _ = rx.recv_timeout(Duration::from_millis(650));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn notification_ids_are_scoped_to_the_server_owner() {
        let state = NotificationId {
            owner: ":1.9".into(),
            id: 42,
        };
        assert_eq!(state.for_owner(":1.9"), 42);
        assert_eq!(state.for_owner(":1.10"), 0);
    }
    #[test]
    fn stored_state_is_private_bounded_and_never_follows_a_symlink() {
        let dir = std::env::temp_dir().join(format!("mayon-voice-id-test-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("notification.json");
        let state = NotificationId {
            owner: ":1.9".into(),
            id: 42,
        };
        save_id(&path, &state);
        assert_eq!(read_id(&path).unwrap().id, 42);
        use std::os::unix::fs::{symlink, PermissionsExt};
        assert_eq!(
            fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o600
        );
        fs::remove_file(&path).unwrap();
        let target = dir.join("other.json");
        fs::write(&target, serde_json::to_string(&state).unwrap()).unwrap();
        symlink(&target, &path).unwrap();
        assert!(read_id(&path).is_none());
        fs::remove_dir_all(dir).unwrap();
    }
}
