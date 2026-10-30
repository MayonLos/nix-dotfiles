#![cfg(target_os = "linux")]

use serial_mayon::{
    codec::{parse_hex, Encoding, Framer},
    transport::{Command, Device, Event, Settings, Worker},
};
use std::{
    ffi::{CStr, OsStr},
    fs,
    io::{self, Read, Write},
    os::{
        fd::{FromRawFd, OwnedFd},
        unix::{ffi::OsStrExt, fs::symlink, io::AsRawFd},
    },
    path::{Path, PathBuf},
    time::{Duration, Instant},
};

#[link(name = "util")]
unsafe extern "C" {
    fn openpty(
        master: *mut libc::c_int,
        slave: *mut libc::c_int,
        name: *mut libc::c_char,
        termios: *const libc::termios,
        winsize: *const libc::winsize,
    ) -> libc::c_int;
}

fn pty() -> (OwnedFd, PathBuf) {
    let mut master = -1;
    let mut slave = -1;
    let mut name = [0 as libc::c_char; 256];
    // SAFETY: all output pointers refer to writable local storage. Optional
    // termios/winsize pointers are null as allowed by openpty(3).
    let result = unsafe {
        openpty(
            &mut master,
            &mut slave,
            name.as_mut_ptr(),
            std::ptr::null(),
            std::ptr::null(),
        )
    };
    assert_eq!(result, 0, "openpty failed: {}", io::Error::last_os_error());
    // SAFETY: openpty returned two owned file descriptors.
    let master = unsafe { OwnedFd::from_raw_fd(master) };
    // SAFETY: openpty returned two owned file descriptors.
    let slave = unsafe { OwnedFd::from_raw_fd(slave) };
    // SAFETY: openpty writes a nul-terminated pathname into `name`.
    let name = unsafe { CStr::from_ptr(name.as_ptr()) };
    let path = PathBuf::from(OsStr::from_bytes(name.to_bytes()));
    drop(slave);
    (master, path)
}

fn device(path: &Path) -> Device {
    Device {
        path: path.to_string_lossy().into_owned(),
        vid: 0,
        pid: 0,
        serial: None,
        product: "PTY test device".into(),
        interface: String::new(),
        topology: path.to_string_lossy().into_owned(),
    }
}

fn await_event(
    worker: &Worker,
    timeout: Duration,
    mut predicate: impl FnMut(&Event) -> bool,
) -> Event {
    let deadline = Instant::now() + timeout;
    loop {
        let remaining = deadline.saturating_duration_since(Instant::now());
        assert!(
            !remaining.is_zero(),
            "timed out waiting for serial worker event"
        );
        let event = worker
            .rx
            .recv_timeout(remaining)
            .expect("timed out waiting for serial worker event");
        if predicate(&event) {
            return event;
        }
    }
}

fn await_connected(worker: &Worker, expected_path: &Path) {
    let expected = expected_path.to_string_lossy().into_owned();
    await_event(
        worker,
        Duration::from_secs(3),
        |event| matches!(event, Event::Connected(path) if path == &expected),
    );
}

fn await_rx(worker: &Worker, expected: &[u8]) {
    let deadline = Instant::now() + Duration::from_secs(3);
    let mut received = Vec::new();
    while received.len() < expected.len() {
        let remaining = deadline.saturating_duration_since(Instant::now());
        assert!(!remaining.is_zero(), "timed out waiting for RX bytes");
        if let Event::Rx(bytes) = worker
            .rx
            .recv_timeout(remaining)
            .expect("timed out waiting for RX")
        {
            received.extend(bytes);
        }
    }
    received.truncate(expected.len());
    assert_eq!(received, expected);
}

fn read_master(file: &mut fs::File, count: usize, timeout: Duration) -> Vec<u8> {
    let deadline = Instant::now() + timeout;
    let mut received = Vec::with_capacity(count);
    while received.len() < count {
        let remaining = deadline.saturating_duration_since(Instant::now());
        assert!(!remaining.is_zero(), "timed out reading PTY master");
        let mut poll_fd = libc::pollfd {
            fd: file.as_raw_fd(),
            events: libc::POLLIN,
            revents: 0,
        };
        let millis = remaining.as_millis().clamp(1, i32::MAX as u128) as i32;
        // SAFETY: poll receives one initialized pollfd and a finite timeout.
        let ready = unsafe { libc::poll(&mut poll_fd, 1, millis) };
        assert!(ready > 0, "timed out waiting for PTY data");
        let mut buffer = vec![0; count - received.len()];
        match file.read(&mut buffer) {
            Ok(0) => panic!("PTY master closed while reading"),
            Ok(read) => received.extend_from_slice(&buffer[..read]),
            Err(error) if error.kind() == io::ErrorKind::WouldBlock => {}
            Err(error) => panic!("PTY master read failed: {error}"),
        }
    }
    received
}

fn link_pty(alias: &Path, slave: &Path) {
    let _ = fs::remove_file(alias);
    symlink(slave, alias).expect("create PTY symlink");
}

#[test]
fn utf8_gbk_and_hex_survive_chunked_streams() {
    let mut utf8 = Framer::default();
    let line = "串口温度=23.5".as_bytes();
    assert!(utf8.push(&line[..3]).is_empty());
    assert!(utf8.push(&line[3..]).is_empty());
    let complete = utf8.push(b"\r\n");
    assert_eq!(complete.len(), 1);
    assert_eq!(Encoding::Utf8.decode(&complete[0]), "串口温度=23.5");
    assert!(utf8.push(b"next\r").len() == 1);
    assert!(
        utf8.push(b"\n").is_empty(),
        "CRLF split across chunks is one delimiter"
    );

    let gbk = Encoding::Gbk.encode("温度=23.5").unwrap();
    let mut framer = Framer::default();
    let mut frames = Vec::new();
    for byte in &gbk {
        frames.extend(framer.push(std::slice::from_ref(byte)));
    }
    assert!(frames.is_empty());
    frames.extend(framer.push(b"\r"));
    assert_eq!(frames.len(), 1);
    assert_eq!(Encoding::Gbk.decode(&frames[0]), "温度=23.5");
    assert_eq!(
        parse_hex("0xDE AD, 00 ff").unwrap(),
        [0xde, 0xad, 0x00, 0xff]
    );
}

#[test]
fn worker_round_trips_raw_hex_and_reports_unsupported_control_lines() {
    let temp = tempfile::tempdir().unwrap();
    let (master, slave) = pty();
    let master = fs::File::from(master);
    let alias = temp.path().join("board-uart");
    link_pty(&alias, &slave);
    let worker = Worker::start();
    let settings = Settings::default();
    worker
        .tx
        .send(Command::Connect(device(&alias), settings))
        .unwrap();
    await_connected(&worker, &alias);

    let raw = parse_hex("DE AD 00 FF").unwrap();
    let mut master = master;
    master.write_all(&raw).unwrap();
    await_rx(&worker, &raw);
    worker.tx.send(Command::Write(raw.clone())).unwrap();
    assert_eq!(
        read_master(&mut master, raw.len(), Duration::from_secs(2)),
        raw
    );

    worker
        .tx
        .send(Command::Lines {
            dtr: true,
            rts: true,
        })
        .unwrap();
    await_event(
        &worker,
        Duration::from_secs(2),
        |event| matches!(event, Event::Error(message) if message.contains("DTR") || message.contains("RTS")),
    );
    worker
        .tx
        .send(Command::Pulse {
            dtr: true,
            millis: 30,
        })
        .unwrap();
    await_event(
        &worker,
        Duration::from_secs(2),
        |event| matches!(event, Event::Error(message) if message.contains("DTR") || message.contains("RTS")),
    );
    // The deadline path makes a second restore attempt. PTYs cannot expose
    // line voltage, but they must report that ioctl failure and stay usable.
    await_event(
        &worker,
        Duration::from_secs(2),
        |event| matches!(event, Event::Error(message) if message.contains("DTR") || message.contains("RTS")),
    );
    worker.tx.send(Command::Write(vec![0xA5])).unwrap();
    assert_eq!(read_master(&mut master, 1, Duration::from_secs(2)), [0xA5]);

    worker.tx.send(Command::Disconnect).unwrap();
    let expected_alias = alias.to_string_lossy().into_owned();
    await_event(
        &worker,
        Duration::from_secs(2),
        |event| matches!(event, Event::Disconnected(path) if path == &expected_alias),
    );
    let reopened = serialport::new(alias.to_string_lossy(), 115_200)
        .timeout(Duration::from_millis(100))
        .open()
        .expect("Disconnect must release the slave fd");
    drop(reopened);

    worker
        .tx
        .send(Command::Connect(device(&alias), Settings::default()))
        .unwrap();
    await_connected(&worker, &alias);
    worker.tx.send(Command::Release(41)).unwrap();
    await_event(&worker, Duration::from_secs(2), |event| {
        matches!(event, Event::Released(41))
    });
}

#[test]
fn worker_reconnects_repointed_test_symlink_and_release_stays_responsive() {
    let temp = tempfile::tempdir().unwrap();
    let alias = temp.path().join("uart-current");
    let (master_one, slave_one) = pty();
    link_pty(&alias, &slave_one);
    let worker = Worker::start();
    worker
        .tx
        .send(Command::Connect(device(&alias), Settings::default()))
        .unwrap();
    await_connected(&worker, &alias);

    drop(master_one);
    let expected_alias = alias.to_string_lossy().into_owned();
    await_event(
        &worker,
        Duration::from_secs(3),
        |event| matches!(event, Event::Disconnected(path) if path == &expected_alias),
    );
    let (master_two, slave_two) = pty();
    link_pty(&alias, &slave_two);
    await_connected(&worker, &alias);
    let mut master_two = fs::File::from(master_two);
    master_two.write_all(b"reconnected\n").unwrap();
    await_rx(&worker, b"reconnected\n");

    // Do not read the PTY master: its output buffer fills. Release must still
    // close the fd, discard the unsent tail, and acknowledge promptly.
    worker
        .tx
        .send(Command::Write(vec![0x5a; 1024 * 1024]))
        .unwrap();
    // Reach actual backpressure: multiple chunks entered the unread master,
    // then TX makes no progress for 100ms. An immediate Release only tests
    // queue ordering and misses blocking writes into a nearly full tty.
    let deadline = Instant::now() + Duration::from_secs(3);
    let mut written = 0;
    loop {
        assert!(
            Instant::now() < deadline,
            "PTY output did not reach backpressure"
        );
        match worker.rx.recv_timeout(Duration::from_millis(100)) {
            Ok(Event::Tx(bytes)) => written += bytes,
            Err(std::sync::mpsc::RecvTimeoutError::Timeout) if written >= 8192 => break,
            Ok(_) | Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {}
            Err(error) => panic!("worker stopped: {error}"),
        }
    }
    let started = Instant::now();
    worker.tx.send(Command::Release(99)).unwrap();
    await_event(&worker, Duration::from_millis(900), |event| {
        matches!(event, Event::Released(99))
    });
    assert!(started.elapsed() < Duration::from_secs(1));
    let reopened = serialport::new(alias.to_string_lossy(), 115_200)
        .timeout(Duration::from_millis(100))
        .open()
        .expect("Release must close the tty despite backlogged TX");
    drop(reopened);
}
