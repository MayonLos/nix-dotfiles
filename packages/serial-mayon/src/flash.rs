//! Capture a user-configured flash command without blocking the TUI event loop.
//!
//! Reader threads use `try_send`: when the bounded 256-event queue is full,
//! complete output lines are dropped so a slow UI cannot block the child on a
//! full stdout/stderr pipe. The final `Done` event is sent after the child has
//! been waited for and may wait for the UI to drain the queue. Its message
//! reports how many output lines were dropped.

use std::{
    env,
    io::{self, Read},
    process::{Command, Stdio},
    sync::{
        atomic::{AtomicUsize, Ordering},
        mpsc::{self, Receiver, SyncSender, TrySendError},
        Arc,
    },
    thread::{self, JoinHandle},
    time::{Duration, Instant},
};
use std::{os::unix::process::CommandExt, process::ExitStatus};

const EVENT_CAPACITY: usize = 256;
const MAX_LINE: usize = 16 * 1024;
const LINE_TRUNCATION: &str = " … [输出行已截断]";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FlashEvent {
    Line(String),
    Done(String),
}

pub struct Flash {
    pub rx: Receiver<FlashEvent>,
    pid: i32,
    worker: Option<JoinHandle<()>>,
}

impl Flash {
    pub fn start(command: &str, directory: &str) -> io::Result<Self> {
        if command.trim().is_empty() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "烧录命令不能为空",
            ));
        }
        let shell = env::var("SERIAL_MAYON_SHELL")
            .ok()
            .filter(|shell| !shell.trim().is_empty())
            .unwrap_or_else(|| "sh".into());
        let mut cmd = Command::new(shell);
        cmd.arg("-c")
            .arg(command)
            .current_dir(if directory.trim().is_empty() {
                "."
            } else {
                directory
            })
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        // A private session/process group lets cancel and Drop terminate the
        // shell plus its foreground children without signaling the TUI.
        unsafe {
            cmd.pre_exec(|| {
                if libc::setsid() == -1 {
                    return Err(io::Error::last_os_error());
                }
                Ok(())
            });
        }
        let mut child = cmd.spawn()?;
        let pid = child.id() as i32;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| io::Error::other("无法捕获烧录命令 stdout"))?;
        let stderr = child
            .stderr
            .take()
            .ok_or_else(|| io::Error::other("无法捕获烧录命令 stderr"))?;

        let (tx, rx) = mpsc::sync_channel(EVENT_CAPACITY);
        let dropped = Arc::new(AtomicUsize::new(0));
        let out_tx = tx.clone();
        let out_dropped = Arc::clone(&dropped);
        let out_reader = thread::spawn(move || read_lines(stdout, out_tx, out_dropped));
        let err_tx = tx.clone();
        let err_dropped = Arc::clone(&dropped);
        let err_reader = thread::spawn(move || read_lines(stderr, err_tx, err_dropped));

        let worker = thread::spawn(move || {
            let status = child.wait();
            // A command may leave background descendants holding the pipes.
            // Terminate the private group before joining readers so they exit.
            terminate_group(pid, libc::SIGTERM);
            thread::sleep(Duration::from_millis(30));
            terminate_group(pid, libc::SIGKILL);
            let _ = out_reader.join();
            let _ = err_reader.join();

            let lost = dropped.load(Ordering::Relaxed);
            let message = match status {
                Ok(status) => status_message(status),
                Err(error) => format!("等待烧录命令失败：{error}"),
            };
            let message = if lost == 0 {
                message
            } else {
                format!("{message}（输出队列已丢弃 {lost} 行）")
            };
            // The child has already been waited for, so this can never stall
            // the process itself. Drop drains the receiver while joining.
            let _ = tx.send(FlashEvent::Done(message));
        });

        Ok(Self {
            rx,
            pid,
            worker: Some(worker),
        })
    }

    /// Stop the full process group, reap the child, and drain captured events.
    pub fn cancel(&mut self) {
        if self.worker.is_some() {
            terminate_group(self.pid, libc::SIGTERM);
        }
        self.finish_worker();
    }

    fn finish_worker(&mut self) {
        let Some(worker) = self.worker.take() else {
            return;
        };
        let grace_end = Instant::now() + Duration::from_millis(500);
        while !worker.is_finished() && Instant::now() < grace_end {
            let _ = self.rx.recv_timeout(Duration::from_millis(10));
        }
        if !worker.is_finished() {
            terminate_group(self.pid, libc::SIGKILL);
        }
        while !worker.is_finished() {
            let _ = self.rx.recv_timeout(Duration::from_millis(10));
        }
        while self.rx.try_recv().is_ok() {}
        let _ = worker.join();
        self.pid = 0;
    }
}

impl Drop for Flash {
    fn drop(&mut self) {
        if self.worker.is_some() {
            terminate_group(self.pid, libc::SIGTERM);
        }
        self.finish_worker();
    }
}

fn terminate_group(pid: i32, signal: i32) {
    if pid > 1 {
        // Negative pid targets the private process group created by setsid.
        unsafe {
            libc::kill(-pid, signal);
        }
    }
}

fn status_message(status: ExitStatus) -> String {
    match status.code() {
        Some(code) => format!("烧录命令退出，状态码 {code}"),
        None => "烧录命令被信号终止".into(),
    }
}

fn read_lines<R: Read>(mut reader: R, tx: SyncSender<FlashEvent>, dropped: Arc<AtomicUsize>) {
    let mut chunk = [0u8; 4096];
    let mut line = Vec::with_capacity(MAX_LINE);
    let mut truncated = false;
    loop {
        let count = match reader.read(&mut chunk) {
            Ok(0) | Err(_) => break,
            Ok(count) => count,
        };
        for &byte in &chunk[..count] {
            if byte == b'\n' {
                emit_line(&tx, &dropped, &line, truncated);
                line.clear();
                truncated = false;
            } else if line.len() < MAX_LINE {
                line.push(byte);
            } else {
                truncated = true;
            }
        }
    }
    if !line.is_empty() || truncated {
        emit_line(&tx, &dropped, &line, truncated);
    }
}

fn emit_line(tx: &SyncSender<FlashEvent>, dropped: &AtomicUsize, bytes: &[u8], truncated: bool) {
    let mut line = String::from_utf8_lossy(bytes).into_owned();
    if let Some(stripped) = line.strip_suffix('\r') {
        line = stripped.to_owned();
    }
    if truncated {
        line.push_str(LINE_TRUNCATION);
    }
    match tx.try_send(FlashEvent::Line(line)) {
        Ok(()) | Err(TrySendError::Disconnected(_)) => {}
        Err(TrySendError::Full(_)) => {
            dropped.fetch_add(1, Ordering::Relaxed);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn next_event(flash: &Flash) -> FlashEvent {
        flash.rx.recv_timeout(Duration::from_secs(3)).unwrap()
    }

    #[test]
    fn captures_both_streams_and_completion() {
        let mut flash = Flash::start("printf 'one\\n'; printf 'two\\n' >&2", ".").unwrap();
        let mut lines = Vec::new();
        let mut done = false;
        while !done {
            match next_event(&flash) {
                FlashEvent::Line(line) => lines.push(line),
                FlashEvent::Done(message) => {
                    assert!(message.contains("状态码 0"));
                    done = true;
                }
            }
        }
        assert!(lines.contains(&"one".to_string()));
        assert!(lines.contains(&"two".to_string()));
        flash.finish_worker();
    }

    #[test]
    fn rejects_empty_command_and_uses_current_directory_by_default() {
        assert!(matches!(
            Flash::start("  ", "."),
            Err(error) if error.kind() == io::ErrorKind::InvalidInput
        ));
        let mut flash = match Flash::start("true", " ") {
            Ok(flash) => flash,
            Err(error) => panic!("empty directory should use current directory: {error}"),
        };
        flash.cancel();
    }

    #[test]
    fn cancel_terminates_a_long_running_command() {
        let mut flash = Flash::start("sleep 30", ".").unwrap();
        flash.cancel();
        assert!(flash.worker.is_none());
    }

    #[test]
    fn output_line_is_bounded_and_marked_when_truncated() {
        let (tx, rx) = mpsc::sync_channel(4);
        let dropped = AtomicUsize::new(0);
        emit_line(&tx, &dropped, &vec![b'x'; MAX_LINE], true);
        match rx.recv().unwrap() {
            FlashEvent::Line(line) => {
                assert!(line.ends_with(LINE_TRUNCATION));
                assert!(line.len() <= MAX_LINE + LINE_TRUNCATION.len());
            }
            FlashEvent::Done(_) => panic!("expected line"),
        }
    }
}
