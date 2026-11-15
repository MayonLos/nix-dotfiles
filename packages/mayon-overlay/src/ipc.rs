//! Unix-socket control channel.
//!
//! The overlay is a keyboard-grabbing layer surface: tests and scripts cannot
//! reach it through the compositor. A small newline-delimited JSON protocol on
//! `$XDG_RUNTIME_DIR/mayon-overlay-<mode>.sock` exposes exactly the operations
//! the UI itself performs (`state`, `query`, `select`, `activate`, `click`,
//! `close`, `toggle`). The same socket is used for single-instance toggling: a
//! second invocation of `mayon-clipboard` connects and sends `toggle`.

use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::time::Duration;

pub struct IpcServer {
    listener: UnixListener,
    path: PathBuf,
}

impl IpcServer {
    pub fn bind(path: &Path) -> Result<IpcServer, String> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|err| format!("cannot create socket directory {:?}: {}", parent, err))?;
        }
        // A stale socket from a crashed instance must not block startup; only
        // remove the path after proving nothing is listening on it.
        if path.exists() && UnixStream::connect(path).is_err() {
            let _ = std::fs::remove_file(path);
        }
        let listener = UnixListener::bind(path)
            .map_err(|err| format!("cannot bind {}: {}", path.display(), err))?;
        listener
            .set_nonblocking(true)
            .map_err(|err| format!("cannot make control socket non-blocking: {}", err))?;
        Ok(IpcServer {
            listener,
            path: path.to_path_buf(),
        })
    }

    /// Accept one pending connection, if any.
    pub fn accept(&self) -> Result<Option<UnixStream>, String> {
        match self.listener.accept() {
            Ok((stream, _)) => Ok(Some(stream)),
            Err(err) if err.kind() == std::io::ErrorKind::WouldBlock => Ok(None),
            Err(err) => Err(format!("control socket accept failed: {}", err)),
        }
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    /// Raw file descriptor for `poll(2)` integration in the Wayland loop.
    pub fn listener_fd(&self) -> std::os::fd::RawFd {
        use std::os::fd::AsRawFd;
        self.listener.as_raw_fd()
    }

    /// Serve one request and write the newline-terminated reply.
    pub fn serve(&self, mut stream: UnixStream, handler: impl FnOnce(&str) -> String) -> Result<(), String> {
        stream
            .set_read_timeout(Some(Duration::from_secs(2)))
            .map_err(|err| format!("control socket timeout: {}", err))?;
        let mut reader = BufReader::new(stream.try_clone().map_err(|err| err.to_string())?);
        let mut request = String::new();
        reader
            .read_line(&mut request)
            .map_err(|err| format!("control socket read failed: {}", err))?;
        let reply = handler(request.trim());
        stream
            .write_all(reply.as_bytes())
            .and_then(|_| stream.write_all(b"\n"))
            .and_then(|_| stream.flush())
            .map_err(|err| format!("control socket write failed: {}", err))
    }
}

impl Drop for IpcServer {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
    }
}

/// Send one command to a running overlay and return the reply line.
pub fn client_request(socket: &Path, command: &str) -> Result<String, String> {
    let mut stream = UnixStream::connect(socket).map_err(|err| {
        format!(
            "cannot connect to overlay control socket {}: {}",
            socket.display(),
            err
        )
    })?;
    stream
        .set_read_timeout(Some(Duration::from_secs(5)))
        .map_err(|err| format!("cannot set control socket timeout: {}", err))?;
    stream
        .write_all(command.as_bytes())
        .and_then(|_| stream.write_all(b"\n"))
        .and_then(|_| stream.flush())
        .map_err(|err| format!("control socket write failed: {}", err))?;
    let mut reader = BufReader::new(stream);
    let mut reply = String::new();
    reader
        .read_line(&mut reply)
        .map_err(|err| format!("control socket read failed: {}", err))?;
    Ok(reply.trim().to_string())
}

/// Try to toggle an already-running overlay of the same mode. Returns true when
/// a running instance acknowledged the toggle.
pub fn toggle_if_running(socket: &Path) -> bool {
    match client_request(socket, "toggle") {
        Ok(reply) => {
            eprintln!("mayon-overlay: running instance: {}", reply);
            true
        }
        Err(_) => false,
    }
}
