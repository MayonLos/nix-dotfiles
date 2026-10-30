use serial_mayon::{
    app::{payload, App, InputKind},
    codec::Encoding,
    store::Store,
};
use std::{fs, os::unix::fs::PermissionsExt, time::Duration};
use tempfile::tempdir;

fn app_at(root: &std::path::Path) -> App {
    let store = Store::at(root.join("config"), root.join("data")).unwrap();
    App::new(store)
}

#[test]
fn app_startup_discovers_without_connecting_and_receive_survives_pause() {
    let root = tempdir().unwrap();
    let mut app = app_at(root.path());

    assert!(!app.connected);
    assert!(app.device.is_none());
    assert!(app.disconnected.is_none());

    app.receive(b"sensor=1.25,x=2.5\r\n".to_vec());
    assert_eq!(app.capture.records.len(), 1);
    app.pause();
    let anchor = app.anchor;
    app.receive(b"sensor=3.5,x=4.5\n".to_vec());

    assert_eq!(app.anchor, anchor);
    assert_eq!(app.capture.records.len(), 2);
    assert_eq!(
        app.rx_total,
        (b"sensor=1.25,x=2.5\r\n".len() + b"sensor=3.5,x=4.5\n".len()) as u64
    );
    assert_eq!(app.capture.records.back().unwrap().text, "sensor=3.5,x=4.5");
}

#[test]
fn search_and_filter_submission_follow_captured_records() {
    let root = tempdir().unwrap();
    let mut app = app_at(root.path());
    app.receive(b"boot=1\nWARN sensor=2\nready=1\n".to_vec());

    app.submit(InputKind::Search, "WARN".into()).unwrap();
    assert_eq!(app.capture.records.get(1).map(|r| r.id), app.found);
    assert_eq!(app.anchor, app.found);

    app.submit(InputKind::Filter, "sensor".into()).unwrap();
    assert_eq!(app.filter, "sensor");
    assert_eq!(app.scroll, 0);
    app.search_next();
    assert_eq!(app.found, Some(1));
}

#[test]
fn logging_keeps_raw_bytes_timestamps_csv_quoting_and_private_permissions() {
    let root = tempdir().unwrap();
    let mut app = app_at(root.path());
    app.csv = true;
    app.logging();
    assert!(app.logger.is_some());
    let stem = app.logger.as_ref().unwrap().path.clone();
    let input = b"sen\"sor=1.25,x=2.5\r\nsen\"sor=3,x=4\n";
    app.pause();
    app.receive(input.to_vec());
    assert_eq!(app.capture.records.len(), 2);
    assert_eq!(app.rx_total, input.len() as u64);
    app.logging();
    assert!(app.logger.is_none());

    let raw = fs::read(stem.with_extension("bin")).unwrap();
    assert_eq!(raw, input);
    let log_path = stem.with_extension("log");
    let log = fs::read_to_string(&log_path).unwrap();
    assert!(log
        .lines()
        .all(|line| line.contains("T") && line.contains("[RX]")));
    assert!(log.contains("sen\"sor=1.25"));
    assert_eq!(
        fs::metadata(log_path).unwrap().permissions().mode() & 0o777,
        0o600
    );

    let csv = fs::read_to_string(stem.with_extension("csv")).unwrap();
    let rows: Vec<_> = csv.lines().map(parse_csv_row).collect();
    assert_eq!(rows[0], vec!["timestamp", "seconds", "channel", "value"]);
    assert_eq!(rows.len(), 5); // header plus two numeric channels on each line
    assert_eq!(rows[1][2], "sen\"sor");
    assert_eq!(rows[1][3], "1.25");
    assert_eq!(rows[2][2], "x");
    assert_eq!(rows[2][3], "2.5");
}

#[test]
fn invalid_settings_are_atomic_and_timer_requires_connection_and_last_send() {
    let root = tempdir().unwrap();
    let mut app = app_at(root.path());
    let original = serde_json::to_value(&app.profile).unwrap();
    assert!(app
        .submit(InputKind::Settings, "baud=230400 bits=9".into())
        .is_err());
    assert_eq!(serde_json::to_value(&app.profile).unwrap(), original);

    assert!(app.submit(InputKind::Timer, "100".into()).is_err());
    assert!(app.repeat.is_none());

    app.connected = true;
    app.last_sent = vec![0x41, 0x0d, 0x0a];
    app.submit(InputKind::Timer, "100".into()).unwrap();
    let repeat = app.repeat.as_ref().unwrap();
    assert_eq!(repeat.bytes, [0x41, 0x0d, 0x0a]);
    assert_eq!(repeat.every, Duration::from_millis(100));
    app.submit(InputKind::Timer, "0".into()).unwrap();
    assert!(app.repeat.is_none());
}

#[test]
fn oversized_file_is_rejected_before_queueing_and_payload_modes_are_exact() {
    let root = tempdir().unwrap();
    let mut app = app_at(root.path());
    let file = root.path().join("too-large.bin");
    fs::write(&file, vec![0x5a; 1024 * 1024 + 1]).unwrap();
    app.connected = true;
    assert!(app
        .submit(InputKind::File, file.to_string_lossy().into_owned())
        .is_err());
    assert!(app.capture.records.is_empty());
    assert!(app.last_sent.is_empty());
    assert_eq!(app.tx_total, 0);

    assert_eq!(
        payload("41 42", true, Encoding::Gbk, "CRLF").unwrap(),
        b"AB"
    );
    assert_eq!(
        payload("中文", false, Encoding::Gbk, "无").unwrap(),
        [0xd6, 0xd0, 0xce, 0xc4]
    );
}

/// Minimal RFC 4180 row reader used to verify quoting without another crate.
fn parse_csv_row(line: &str) -> Vec<String> {
    let mut fields = Vec::new();
    let mut field = String::new();
    let mut chars = line.chars().peekable();
    let mut quoted = false;
    while let Some(ch) = chars.next() {
        match ch {
            '"' if quoted && chars.peek() == Some(&'"') => {
                field.push('"');
                chars.next();
            }
            '"' => quoted = !quoted,
            ',' if !quoted => fields.push(std::mem::take(&mut field)),
            _ => field.push(ch),
        }
    }
    assert!(!quoted, "unterminated CSV quote: {line}");
    fields.push(field);
    fields
}

#[test]
fn hex_capture_preserves_line_delimiters_and_encoding_switch_keeps_eviction_valid() {
    let root = tempdir().unwrap();
    let mut store = Store::at(root.path().join("config"), root.path().join("data")).unwrap();
    store.config.scrollback = 100;
    let mut app = App::new(store);
    let bytes = b"A\r\nB\x00\xff\n";
    app.receive(bytes.to_vec());
    assert_eq!(
        app.wire
            .records
            .iter()
            .flat_map(|r| r.raw.iter().copied())
            .collect::<Vec<_>>(),
        bytes
    );
    app.profile.encoding = Encoding::Gbk;
    for _ in 0..110 {
        app.receive(vec![0xd6, 0xd0, b'\n']);
    }
    app.toggle_encoding();
    // Exercise eviction after decoded strings grow, then shrink, then grow.
    for _ in 0..110 {
        app.receive(vec![0xd6, 0xd0, b'\n']);
    }
    app.toggle_encoding();
    for _ in 0..110 {
        app.receive(vec![0xd6, 0xd0, b'\n']);
    }
    assert_eq!(app.capture.records.len(), 100);
    assert!(app.capture.evicted > 200);
}
