//! GUI ownership is verified through /proc and pidfds; never signal by name.
use std::{
    fs,
    os::{
        fd::{AsRawFd, FromRawFd, OwnedFd},
        unix::fs::MetadataExt,
    },
    path::{Path, PathBuf},
    process::{Command, Stdio},
};

#[derive(Clone, Default)]
pub struct Lifecycle {
    /// Explicit pair for an isolated executable fixture. Never inferred from env.
    pub test_executable: Option<PathBuf>,
    pub test_launcher: Option<PathBuf>,
}
impl Lifecycle {
    pub fn launch(&self, link: Option<&str>) -> Result<(), String> {
        let mut cmd = if let Some(launcher) = &self.test_launcher {
            Command::new(launcher)
        } else if link.is_some() {
            // URL deep links are handled by Verge's documented singleton endpoint.
            Command::new("clash-verge")
        } else {
            // Use exactly the native provider, including systemd app.slice and the
            // shell's environment / activation policy. Do not duplicate its code.
            let mut c = Command::new("noctalia");
            c.args(["msg", "app-launch"]);
            c.arg(std::env::var_os("MAYON_CLASH_DESKTOP").unwrap_or_else(|| {
                "/run/current-system/sw/share/applications/clash-verge.desktop".into()
            }));
            c
        };
        if let Some(link) = link {
            cmd.arg(link);
        }
        let child = cmd
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|_| "无法启动 Verge 启动器".to_string())?;
        std::thread::spawn(move || {
            let mut child = child;
            let _ = child.wait();
        });
        Ok(())
    }
    fn allowed(&self, path: &Path) -> bool {
        if let Some(test) = &self.test_executable {
            return fs::canonicalize(test).is_ok_and(|p| p == path);
        }
        let name = path
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or_default();
        path.starts_with("/nix/store")
            && path.to_string_lossy().contains("-clash-verge-rev-")
            && matches!(name, "clash-verge" | ".clash-verge-wrapped")
    }
    pub fn stop(&self) -> Result<usize, String> {
        let mut count = 0;
        for entry in fs::read_dir("/proc")
            .map_err(|_| "无法读取进程表")?
            .flatten()
        {
            let Some(pid) = entry
                .file_name()
                .to_str()
                .and_then(|s| s.parse::<i32>().ok())
            else {
                continue;
            };
            // Pin identity before validation so a recycled PID can never receive
            // the signal. Unsupported pidfd kernels fail closed.
            let fd = unsafe { libc::syscall(libc::SYS_pidfd_open, pid, 0) };
            if fd < 0 {
                continue;
            }
            let fd = unsafe { OwnedFd::from_raw_fd(fd as i32) };
            let dir = entry.path();
            if !fs::metadata(&dir).is_ok_and(|m| m.uid() == unsafe { libc::geteuid() }) {
                continue;
            }
            if !fs::read_link(dir.join("exe")).is_ok_and(|p| self.allowed(&p)) {
                continue;
            }
            let result = unsafe {
                libc::syscall(
                    libc::SYS_pidfd_send_signal,
                    fd.as_raw_fd(),
                    libc::SIGTERM,
                    std::ptr::null::<libc::siginfo_t>(),
                    0,
                )
            };
            if result == 0 {
                count += 1;
            }
        }
        if count == 0 {
            Err("没有找到本用户且可执行路径匹配的 Verge GUI；未发送信号".into())
        } else {
            Ok(count)
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_names_and_services() {
        let l = Lifecycle::default();
        assert!(!l.allowed(Path::new("/tmp/clash-verge")));
        assert!(!l.allowed(Path::new(
            "/nix/store/abc-clash-verge-rev-2.4.7/bin/clash-verge-service"
        )));
        assert!(l.allowed(Path::new(
            "/nix/store/abc-clash-verge-rev-2.4.7/bin/.clash-verge-wrapped"
        )));
    }
}
