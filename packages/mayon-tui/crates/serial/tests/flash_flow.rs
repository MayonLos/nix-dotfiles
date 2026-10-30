use serial_mayon::{
    app::{explicit_device, App},
    store::Store,
    transport::{Command, Event, Worker},
};
use std::{
    sync::mpsc::{self, Receiver, SyncSender},
    thread,
    time::{Duration, Instant},
};
fn fixture() -> (tempfile::TempDir, App, Receiver<Command>, SyncSender<Event>) {
    let dir = tempfile::tempdir().unwrap();
    let mut app = App::new(Store::at(dir.path().join("config"), dir.path().join("data")).unwrap());
    let (tx, commands) = mpsc::sync_channel(64);
    let (events, rx) = mpsc::sync_channel(512);
    app.worker = Worker::from_channels(tx, rx);
    app.device = Some(explicit_device("/dev/pts/simulation-only".into()));
    app.connected = true;
    app.profile.flash = "printf original > output.txt; printf 'flash output\\n'".into();
    app.profile.flash_dir = dir.path().to_string_lossy().into_owned();
    (dir, app, commands, events)
}
fn release(commands: &Receiver<Command>) -> u64 {
    match commands.recv_timeout(Duration::from_secs(1)).unwrap() {
        Command::Release(id) => id,
        other => panic!("expected Release, got {other:?}"),
    }
}
#[test]
fn flash_waits_for_own_release_ack_and_executes_snapshotted_command() {
    let (dir, mut app, commands, events) = fixture();
    app.request_flash();
    let id = release(&commands);
    app.profile.flash = "printf wrong > output.txt".into();
    events
        .send(Event::Disconnected("old event".into()))
        .unwrap();
    app.tick();
    assert!(app.flash.is_none());
    assert!(!dir.path().join("output.txt").exists());
    events.send(Event::Released(id.wrapping_sub(1))).unwrap();
    app.tick();
    assert!(app.flash.is_none());
    events.send(Event::Released(id)).unwrap();
    app.tick();
    assert!(app.flash.is_some());
    // Parameter changes may be saved during flashing but cannot reopen the fd.
    app.apply();
    assert!(commands.try_recv().is_err());
    let until = Instant::now() + Duration::from_secs(3);
    while app.flash.is_some() && Instant::now() < until {
        app.tick();
        thread::sleep(Duration::from_millis(5));
    }
    assert!(app.flash.is_none());
    assert_eq!(
        std::fs::read_to_string(dir.path().join("output.txt")).unwrap(),
        "original"
    );
    assert!(app
        .flash_lines
        .iter()
        .any(|line| line.contains("flash output")));
    assert!(matches!(
        commands.try_recv().unwrap(),
        Command::Connect(_, _)
    ));
}
#[test]
fn cancel_waiting_flash_ignores_stale_ack_even_after_a_second_request() {
    let (dir, mut app, commands, events) = fixture();
    app.request_flash();
    let old = release(&commands);
    app.cancel_flash();
    assert!(matches!(
        commands.try_recv().unwrap(),
        Command::Connect(_, _)
    ));
    events.send(Event::Released(old)).unwrap();
    app.tick();
    assert!(app.flash.is_none());
    assert!(!dir.path().join("output.txt").exists());
    app.request_flash();
    let new = release(&commands);
    assert_ne!(old, new);
    events.send(Event::Released(old)).unwrap();
    app.tick();
    assert!(app.flash.is_none());
    app.cancel_flash();
    events.send(Event::Released(new)).unwrap();
    app.tick();
    assert!(app.flash.is_none());
    assert!(!dir.path().join("output.txt").exists());
}

#[test]
fn switching_away_while_waiting_for_release_cancels_the_pending_flash() {
    let (dir, mut app, commands, _events) = fixture();
    app.request_flash();
    release(&commands);
    assert!(app.status.starts_with("等待串口关闭确认"));
    app.suspend();
    assert!(app.status.contains("已取消烧录"));
    assert!(app.flash.is_none());
    app.resume();
    assert!(app.status.contains("已取消烧录"));
    assert!(app.command(Command::Disconnect));
    app.request_flash();
    assert!(app.status.starts_with("等待串口关闭确认"));
    app.suspend();
    assert!(app.status.contains("已取消烧录"));
    assert!(!dir.path().join("output.txt").exists());
}
