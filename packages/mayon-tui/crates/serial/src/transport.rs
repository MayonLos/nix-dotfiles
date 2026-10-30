use serde::{Deserialize, Serialize};
use serialport::{DataBits, FlowControl, Parity, SerialPort, StopBits};
use std::{
    collections::VecDeque,
    fs,
    io::{Read, Write},
    os::fd::AsRawFd,
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc::{self, Receiver, SyncSender},
        Arc,
    },
    thread,
    time::{Duration, Instant},
};

const POLL: Duration = Duration::from_millis(10);
const RETRY: Duration = Duration::from_millis(400);
const MAX_TX_BYTES: usize = 1024 * 1024;
const TX_CHUNK_BYTES: usize = 4096;

#[derive(Clone, Debug)]
pub struct Device {
    pub path: String,
    pub vid: u16,
    pub pid: u16,
    pub serial: Option<String>,
    pub product: String,
    pub interface: String,
    /// Stable physical sysfs location (or a caller-provided stable alias for PTYs).
    pub topology: String,
}

impl Device {
    pub fn key(&self) -> String {
        let identity = self
            .serial
            .as_deref()
            .filter(|serial| !serial.is_empty())
            .map(str::to_owned)
            .or_else(|| (!self.topology.is_empty()).then(|| self.topology.clone()))
            .unwrap_or_else(|| self.path.clone());
        format!(
            "{:04x}:{:04x}:{identity}:{}",
            self.vid, self.pid, self.interface
        )
    }
}

fn read_trimmed(path: &Path) -> Option<String> {
    fs::read_to_string(path)
        .ok()
        .map(|value| value.trim().to_owned())
        .filter(|value| !value.is_empty())
}

fn parse_hex_file(path: &Path) -> Option<u16> {
    u16::from_str_radix(&read_trimmed(path)?, 16).ok()
}

fn sysfs_device(tty: &str) -> Option<(u16, u16, Option<String>, String, String, String)> {
    let device_link = PathBuf::from("/sys/class/tty").join(tty).join("device");
    let canonical = fs::canonicalize(device_link).ok()?;
    let mut cursor = Some(canonical.as_path());
    let mut usb_node = None;
    while let Some(path) = cursor {
        if parse_hex_file(&path.join("idVendor")).is_some()
            && parse_hex_file(&path.join("idProduct")).is_some()
        {
            usb_node = Some(path.to_path_buf());
            break;
        }
        cursor = path.parent();
    }
    let usb = usb_node?;
    let vid = parse_hex_file(&usb.join("idVendor"))?;
    let pid = parse_hex_file(&usb.join("idProduct"))?;
    let serial = read_trimmed(&usb.join("serial"));
    let identified = adapter_name(vid, pid);
    let product = match read_trimmed(&usb.join("product")) {
        Some(product) if identified != "USB Serial Adapter" => format!("{product} · {identified}"),
        Some(product) => product,
        None => identified,
    };

    // The tty device usually resolves to the USB interface node. Find the
    // nearest interface number, while topology points at the physical USB
    // device and therefore remains stable when ttyACM/ttyUSB numbering moves.
    let mut cursor = Some(canonical.as_path());
    let mut interface = String::new();
    while let Some(path) = cursor {
        if let Some(number) = read_trimmed(&path.join("bInterfaceNumber")) {
            interface = number;
            break;
        }
        if path == usb.as_path() {
            break;
        }
        cursor = path.parent();
    }
    let topology = usb
        .file_name()
        .and_then(|name| name.to_str())
        .map(str::to_owned)
        .unwrap_or_else(|| usb.to_string_lossy().into_owned());
    let driver = canonical
        .ancestors()
        .find_map(|path| fs::read_link(path.join("driver")).ok())
        .and_then(|path| {
            path.file_name()
                .map(|name| name.to_string_lossy().into_owned())
        })
        .unwrap_or_default();
    Some((
        vid,
        pid,
        serial,
        product,
        interface,
        format!("{topology}|{driver}"),
    ))
}

fn adapter_name(vid: u16, pid: u16) -> String {
    match (vid, pid) {
        (0x0483, 0x3748..=0x374f) | (0x0483, 0x3752..=0x3753) => "ST-Link VCP".into(),
        (0x0483, 0x5740) => "STM32 VCP".into(),
        (0x1a86, 0x7523 | 0x5523 | 0x55d4) => "CH340/CH341".into(),
        (0x10c4, _) => "Silicon Labs CP210x".into(),
        (0x0403, _) => "FTDI USB Serial".into(),
        (0x0483, _) => "ST USB Serial".into(),
        _ => "USB Serial Adapter".into(),
    }
}

/// Enumerate USB-backed ttyACM/ttyUSB nodes from sysfs without opening devices.
pub fn discover() -> Vec<Device> {
    let mut devices = fs::read_dir("/sys/class/tty")
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|entry| {
            let name = entry.file_name().to_string_lossy().into_owned();
            if !(name.starts_with("ttyACM") || name.starts_with("ttyUSB")) {
                return None;
            }
            let path = format!("/dev/{name}");
            let (vid, pid, serial, product, interface, topology) = sysfs_device(&name)?;
            Some(Device {
                path,
                vid,
                pid,
                serial,
                product,
                interface,
                topology,
            })
        })
        .collect::<Vec<_>>();
    devices.sort_by(|left, right| left.path.cmp(&right.path));
    devices
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Settings {
    pub baud: u32,
    pub bits: u8,
    pub parity: String,
    pub stop: u8,
    pub flow: String,
    pub dtr: bool,
    pub rts: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            baud: 115_200,
            bits: 8,
            parity: "none".into(),
            stop: 1,
            flow: "none".into(),
            dtr: false,
            rts: false,
        }
    }
}

#[derive(Debug)]
pub enum Command {
    Connect(Device, Settings),
    Disconnect,
    /// Release the port for a flash command and acknowledge only after close.
    Release(u64),
    Write(Vec<u8>),
    Lines {
        dtr: bool,
        rts: bool,
    },
    Pulse {
        dtr: bool,
        millis: u64,
    },
    Shutdown,
}

#[derive(Debug)]
pub enum Event {
    Connected(String),
    Disconnected(String),
    Released(u64),
    Rx(Vec<u8>),
    Tx(usize),
    Error(String),
}

pub struct Worker {
    pub tx: SyncSender<Command>,
    pub rx: Receiver<Event>,
    pub notify: Arc<tokio::sync::Notify>,
    stopped: Arc<AtomicBool>,
    join: Option<thread::JoinHandle<()>>,
}
impl Worker {
    pub fn start() -> Self {
        let (command_tx, command_rx) = mpsc::sync_channel(64);
        let (event_tx, event_rx) = mpsc::sync_channel(512);
        let notify = Arc::new(tokio::sync::Notify::new());
        let stopped = Arc::new(AtomicBool::new(false));
        let n = notify.clone();
        let stop = stopped.clone();
        let join = thread::Builder::new()
            .name("mayon-tools-serial".into())
            .spawn(move || run(command_rx, event_tx, n, stop))
            .expect("serial worker thread creation failed");
        Self {
            tx: command_tx,
            rx: event_rx,
            notify,
            stopped,
            join: Some(join),
        }
    }
    pub fn from_channels(tx: SyncSender<Command>, rx: Receiver<Event>) -> Self {
        Self {
            tx,
            rx,
            notify: Arc::new(tokio::sync::Notify::new()),
            stopped: Arc::new(AtomicBool::new(false)),
            join: None,
        }
    }
    pub fn parked() -> Self {
        let (tx, _commands) = mpsc::sync_channel(1);
        let (_events, rx) = mpsc::sync_channel(1);
        Self::from_channels(tx, rx)
    }
    pub fn stop(&mut self) {
        self.stopped.store(true, Ordering::Release);
        let _ = self.tx.try_send(Command::Shutdown);
        if let Some(join) = self.join.take() {
            let _ = join.join();
        }
    }
}
impl Drop for Worker {
    fn drop(&mut self) {
        self.stop();
    }
}

struct EventSink {
    tx: SyncSender<Event>,
    notify: Arc<tokio::sync::Notify>,
    pending: VecDeque<Event>,
}

impl EventSink {
    fn send(&mut self, event: Event) {
        if self.pending.is_empty() {
            match self.tx.try_send(event) {
                Ok(()) => {
                    self.notify.notify_one();
                }
                Err(mpsc::TrySendError::Full(event)) => self.pending.push_back(event),
                Err(mpsc::TrySendError::Disconnected(_)) => {}
            }
        } else {
            self.queue_pending(event);
        }
    }

    fn queue_pending(&mut self, event: Event) {
        const PENDING_LIMIT: usize = 512;
        if self.pending.len() < PENDING_LIMIT {
            self.pending.push_back(event);
            return;
        }
        match event {
            Event::Tx(bytes) => {
                if let Some(Event::Tx(total)) = self
                    .pending
                    .iter_mut()
                    .rev()
                    .find(|item| matches!(item, Event::Tx(_)))
                {
                    *total = total.saturating_add(bytes);
                }
            }
            Event::Error(message) => {
                if !self
                    .pending
                    .iter()
                    .any(|item| matches!(item, Event::Error(existing) if *existing == message))
                {
                    if let Some(index) = self
                        .pending
                        .iter()
                        .position(|item| matches!(item, Event::Error(_)))
                    {
                        self.pending.remove(index);
                    }
                    self.pending.push_back(Event::Error(message));
                }
            }
            Event::Connected(_) | Event::Disconnected(_) => {
                self.pending
                    .retain(|item| !matches!(item, Event::Connected(_) | Event::Disconnected(_)));
                self.make_room();
                self.pending.push_back(event);
            }
            Event::Released(_) => {
                self.pending
                    .retain(|item| !matches!(item, Event::Released(_)));
                self.make_room();
                self.pending.push_back(event);
            }
            // RX reads are paused whenever the pending queue is nonempty, so
            // this arm is only defensive against a future caller change.
            Event::Rx(bytes) => {
                if let Some(Event::Rx(previous)) = self.pending.back_mut() {
                    previous.extend(bytes);
                }
            }
        }
    }

    fn make_room(&mut self) {
        if self.pending.len() >= 512 {
            if let Some(index) = self
                .pending
                .iter()
                .position(|item| matches!(item, Event::Tx(_) | Event::Error(_)))
            {
                self.pending.remove(index);
            }
        }
    }

    fn flush(&mut self) {
        while let Some(event) = self.pending.pop_front() {
            match self.tx.try_send(event) {
                Ok(()) => {
                    self.notify.notify_one();
                }
                Err(mpsc::TrySendError::Full(event)) => {
                    self.pending.push_front(event);
                    break;
                }
                Err(mpsc::TrySendError::Disconnected(_)) => {
                    self.pending.clear();
                    break;
                }
            }
        }
    }
}

struct Active {
    port: Box<dyn SerialPort>,
    device: Device,
    settings: Settings,
    pending_tx: Option<PendingTx>,
    warned: bool,
    pulse: Option<(Instant, bool, bool)>,
}

struct PendingTx {
    bytes: Vec<u8>,
    offset: usize,
}

fn configure(device: &Device, settings: &Settings) -> Result<Box<dyn SerialPort>, String> {
    let data_bits = match settings.bits {
        5 => DataBits::Five,
        6 => DataBits::Six,
        7 => DataBits::Seven,
        8 => DataBits::Eight,
        _ => return Err(format!("unsupported data bits: {}", settings.bits)),
    };
    let parity = match settings.parity.to_ascii_lowercase().as_str() {
        "none" | "n" => Parity::None,
        "even" | "e" => Parity::Even,
        "odd" | "o" => Parity::Odd,
        _ => return Err(format!("unsupported parity: {}", settings.parity)),
    };
    let stop_bits = match settings.stop {
        1 => StopBits::One,
        2 => StopBits::Two,
        _ => return Err(format!("unsupported stop bits: {}", settings.stop)),
    };
    let flow_control = match settings.flow.to_ascii_lowercase().as_str() {
        "none" => FlowControl::None,
        "software" | "xon/xoff" | "xonxoff" => FlowControl::Software,
        "hardware" | "rts/cts" | "rtscts" => FlowControl::Hardware,
        _ => return Err(format!("unsupported flow control: {}", settings.flow)),
    };
    let port = serialport::new(&device.path, settings.baud)
        .data_bits(data_bits)
        .parity(parity)
        .stop_bits(stop_bits)
        .flow_control(flow_control)
        .timeout(POLL)
        .open_native()
        .map_err(|error| format!("{}: {error}", device.path))?;
    // serialport clears O_NONBLOCK when opening its native fd. Its write
    // timeout only bounds poll(), so restore nonblocking mode to ensure a
    // stalled CTS or partially writable tty cannot trap Release/Shutdown.
    let fd = port.as_raw_fd();
    // SAFETY: this live TTYPort owns fd; fcntl only changes its status flags.
    let flags = unsafe { libc::fcntl(fd, libc::F_GETFL) };
    if flags < 0 || unsafe { libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK) } < 0 {
        return Err(format!(
            "设置串口非阻塞模式失败：{}",
            std::io::Error::last_os_error()
        ));
    }
    Ok(Box::new(port))
}

fn hardware_rts_flow(settings: &Settings) -> bool {
    ["hardware", "rts/cts", "rtscts"]
        .iter()
        .any(|name| settings.flow.eq_ignore_ascii_case(name))
}

fn same_device(target: &Device, candidate: &Device) -> bool {
    target.key() == candidate.key()
}

fn resolve_device(target: &Device, candidates: &[Device]) -> Option<Device> {
    let mut matches = candidates
        .iter()
        .filter(|candidate| same_device(target, candidate));
    let candidate = (*matches.next()?).clone();
    matches.next().is_none().then_some(candidate)
}

fn locate(target: &Device) -> Option<Device> {
    // Manually supplied devices (used by isolated PTY tests) may use any
    // symlink in the repository or test directory. USB devices never take
    // this path and must continue to match their VID/PID/serial identity.
    if target.vid == 0 && target.pid == 0 {
        return Path::new(&target.path).exists().then(|| target.clone());
    }
    let candidates = discover();
    resolve_device(target, &candidates)
}

fn open_and_emit(
    device: Device,
    settings: &Settings,
    events: &mut EventSink,
    report_error: bool,
) -> Option<Active> {
    match configure(&device, settings) {
        Ok(port) => {
            let mut port = port;
            if hardware_rts_flow(settings) {
                events.send(Event::Error(
                    "RTS/CTS 硬件流控可能由驱动接管 RTS 电平".into(),
                ));
            }
            modem_lines(port.as_mut(), settings.dtr, settings.rts, events);
            events.send(Event::Connected(device.path.clone()));
            Some(Active {
                port,
                device,
                settings: settings.clone(),
                pending_tx: None,
                warned: false,
                pulse: None,
            })
        }
        Err(error) => {
            if report_error {
                events.send(Event::Error(error));
            }
            None
        }
    }
}

fn modem_lines(port: &mut dyn SerialPort, dtr: bool, rts: bool, events: &mut EventSink) {
    let mut errors = Vec::new();
    if let Err(error) = port.write_data_terminal_ready(dtr) {
        errors.push(format!("DTR: {error}"));
    }
    if let Err(error) = port.write_request_to_send(rts) {
        errors.push(format!("RTS: {error}"));
    }
    if !errors.is_empty() {
        events.send(Event::Error(format!(
            "控制线不可用（连接仍保持）：{}",
            errors.join("；")
        )));
    }
}

fn disconnect(active: &mut Option<Active>, events: &mut EventSink) -> Option<String> {
    if let Some(connection) = active.take() {
        let path = connection.device.path.clone();
        if let Some(pending) = &connection.pending_tx {
            let remaining = pending.bytes.len().saturating_sub(pending.offset);
            if remaining > 0 {
                events.send(Event::Error(format!(
                    "关闭串口时丢弃了 {remaining} 字节待发送数据"
                )));
            }
        }
        drop(connection); // Close the port before acknowledging a flash hand-off.
        events.send(Event::Disconnected(path.clone()));
        Some(path)
    } else {
        None
    }
}

fn release(
    active: &mut Option<Active>,
    reconnect: &mut Option<(Device, Settings, Instant)>,
    events: &mut EventSink,
    request_id: u64,
) {
    let path = active
        .as_ref()
        .map(|connection| connection.device.path.clone())
        .or_else(|| reconnect.as_ref().map(|(device, _, _)| device.path.clone()))
        .unwrap_or_default();
    *reconnect = None;
    if disconnect(active, events).is_none() {
        events.send(Event::Disconnected(path.clone()));
    }
    events.send(Event::Released(request_id));
}

/// Make bounded progress on a queued payload. Never wait for a complete
/// transfer or `tcdrain`, so RX and flash release remain responsive.
fn pump_tx(
    active: &mut Option<Active>,
    events: &mut EventSink,
) -> Option<(Device, Settings, String)> {
    let result = {
        let connection = active.as_mut()?;
        let pending = connection.pending_tx.as_ref()?;
        let end = pending
            .offset
            .saturating_add(TX_CHUNK_BYTES)
            .min(pending.bytes.len());
        connection.port.write(&pending.bytes[pending.offset..end])
    };

    match result {
        Ok(0) => None,
        Ok(written) => {
            events.send(Event::Tx(written));
            if let Some(connection) = active.as_mut() {
                if let Some(pending) = connection.pending_tx.as_mut() {
                    pending.offset = pending.offset.saturating_add(written);
                    if pending.offset >= pending.bytes.len() {
                        connection.pending_tx = None;
                    }
                }
            }
            None
        }
        Err(error)
            if matches!(
                error.kind(),
                std::io::ErrorKind::TimedOut
                    | std::io::ErrorKind::WouldBlock
                    | std::io::ErrorKind::Interrupted
            ) =>
        {
            None
        }
        Err(error) => active.as_ref().map(|connection| {
            (
                connection.device.clone(),
                connection.settings.clone(),
                error.to_string(),
            )
        }),
    }
}

fn run(
    commands: Receiver<Command>,
    event_tx: SyncSender<Event>,
    notify: Arc<tokio::sync::Notify>,
    stopped: Arc<AtomicBool>,
) {
    let mut events = EventSink {
        tx: event_tx,
        notify,
        pending: VecDeque::new(),
    };
    let mut active: Option<Active> = None;
    let mut reconnect: Option<(Device, Settings, Instant)> = None;
    loop {
        if stopped.load(Ordering::Acquire) {
            disconnect(&mut active, &mut events);
            return;
        }
        let command = if active.is_none() && reconnect.is_none() && events.pending.is_empty() {
            commands
                .recv()
                .map_err(|_| mpsc::RecvTimeoutError::Disconnected)
        } else {
            commands.recv_timeout(POLL)
        };
        match command {
            Ok(Command::Connect(device, settings)) => {
                disconnect(&mut active, &mut events);
                reconnect = Some((device.clone(), settings.clone(), Instant::now()));
                let current = if device.vid == 0 && device.pid == 0 {
                    Some(device.clone())
                } else {
                    resolve_device(&device, &discover())
                };
                if let Some(current) = current {
                    if let Some(opened) = open_and_emit(current, &settings, &mut events, true) {
                        active = Some(opened);
                        reconnect = None;
                    }
                } else {
                    events.send(Event::Error(format!(
                        "设备 {} 已断开或身份不唯一，等待按设备身份重连",
                        device.path
                    )));
                }
            }
            Ok(Command::Disconnect) => {
                let previous = active
                    .as_ref()
                    .map(|connection| connection.device.path.clone())
                    .or_else(|| reconnect.as_ref().map(|(device, _, _)| device.path.clone()));
                reconnect = None;
                let closed = disconnect(&mut active, &mut events);
                if closed.is_none() {
                    events.send(Event::Disconnected(previous.unwrap_or_default()));
                }
            }
            Ok(Command::Release(request_id)) => {
                release(&mut active, &mut reconnect, &mut events, request_id)
            }
            Ok(Command::Write(bytes)) => {
                if bytes.len() > MAX_TX_BYTES {
                    events.send(Event::Error(format!(
                        "发送内容超过 {} 字节上限",
                        MAX_TX_BYTES
                    )));
                } else if let Some(connection) = active.as_mut() {
                    if connection.pending_tx.is_some() {
                        events.send(Event::Error("上一条发送仍在排队".into()));
                    } else {
                        connection.pending_tx = Some(PendingTx { bytes, offset: 0 });
                    }
                } else {
                    events.send(Event::Error("串口尚未连接".into()));
                }
            }
            Ok(Command::Lines { dtr, rts }) => {
                if let Some(connection) = active.as_mut() {
                    if rts != connection.settings.rts && hardware_rts_flow(&connection.settings) {
                        events.send(Event::Error(
                            "RTS/CTS 硬件流控可能由驱动接管 RTS 电平".into(),
                        ));
                    }
                    modem_lines(connection.port.as_mut(), dtr, rts, &mut events);
                    connection.settings.dtr = dtr;
                    connection.settings.rts = rts;
                }
            }
            Ok(Command::Pulse { dtr, millis }) => {
                if let Some(connection) = active.as_mut() {
                    let old_dtr = connection.settings.dtr;
                    let old_rts = connection.settings.rts;
                    let next_dtr = if dtr { !old_dtr } else { old_dtr };
                    let next_rts = if dtr { old_rts } else { !old_rts };
                    if !dtr && hardware_rts_flow(&connection.settings) {
                        events.send(Event::Error(
                            "RTS/CTS 硬件流控可能由驱动接管 RTS 电平".into(),
                        ));
                    }
                    modem_lines(connection.port.as_mut(), next_dtr, next_rts, &mut events);
                    connection.pulse = Some((
                        Instant::now() + Duration::from_millis(millis.max(1)),
                        old_dtr,
                        old_rts,
                    ));
                }
            }
            Ok(Command::Shutdown) | Err(mpsc::RecvTimeoutError::Disconnected) => {
                disconnect(&mut active, &mut events);
                return;
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {}
        }

        if let Some((device, settings, error)) = pump_tx(&mut active, &mut events) {
            events.send(Event::Error(format!("写入失败：{error}")));
            reconnect = Some((device, settings, Instant::now() + RETRY));
            disconnect(&mut active, &mut events);
        }

        if events.pending.is_empty() {
            if let Some(connection) = active.as_mut() {
                let mut buffer = [0u8; 4096];
                match connection.port.read(&mut buffer) {
                    Ok(count) if count > 0 => {
                        events.send(Event::Rx(buffer[..count].to_vec()));
                    }
                    Ok(_) => {}
                    Err(error)
                        if matches!(
                            error.kind(),
                            std::io::ErrorKind::TimedOut
                                | std::io::ErrorKind::WouldBlock
                                | std::io::ErrorKind::Interrupted
                        ) => {}
                    Err(error) => {
                        if !connection.warned {
                            events.send(Event::Error(format!("串口断开：{error}")));
                            connection.warned = true;
                        }
                        let device = connection.device.clone();
                        let settings = connection.settings.clone();
                        disconnect(&mut active, &mut events);
                        reconnect = Some((device, settings, Instant::now() + RETRY));
                    }
                }
            }
        }

        if let Some(connection) = active.as_mut() {
            if let Some((deadline, dtr, rts)) = connection.pulse {
                if Instant::now() >= deadline {
                    modem_lines(connection.port.as_mut(), dtr, rts, &mut events);
                    connection.pulse = None;
                }
            }
        }

        if active.is_none() {
            if let Some((target, settings, retry_at)) = reconnect.as_mut() {
                if Instant::now() >= *retry_at {
                    *retry_at = Instant::now() + RETRY;
                    if let Some(device) = locate(target) {
                        if let Some(opened) = open_and_emit(device, settings, &mut events, false) {
                            active = Some(opened);
                            reconnect = None;
                        }
                    }
                }
            }
        }
        // If the UI has fallen behind, keep buffered data in this bounded
        // worker queue and stop reading until it catches up. Commands remain
        // processable, including Disconnect and Shutdown.
        events.flush();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn device(path: &str, serial: Option<&str>, topology: &str, interface: &str) -> Device {
        Device {
            path: path.into(),
            vid: 0x0483,
            pid: 0x3748,
            serial: serial.map(str::to_owned),
            product: "ST-Link".into(),
            interface: interface.into(),
            topology: topology.into(),
        }
    }

    #[test]
    fn stable_identity_prefers_serial_and_interface() {
        let first = device("/dev/ttyACM0", Some("A1"), "1-2", "00");
        let renumbered = device("/dev/ttyACM4", Some("A1"), "1-7", "00");
        let another_interface = device("/dev/ttyACM4", Some("A1"), "1-7", "01");
        assert_eq!(first.key(), renumbered.key());
        assert_ne!(first.key(), another_interface.key());
    }

    #[test]
    fn topology_fallback_survives_tty_renumbering() {
        let first = device("/dev/ttyUSB0", None, "1-2.3", "00");
        let replugged = device("/dev/ttyUSB8", None, "1-2.3", "00");
        let other_port = device("/dev/ttyUSB8", None, "1-2.4", "00");
        assert_eq!(first.key(), replugged.key());
        assert_ne!(first.key(), other_port.key());
    }

    #[test]
    fn usb_resolution_rejects_another_device_reusing_the_old_tty_path() {
        let selected = device("/dev/ttyACM0", Some("board-A"), "1-2", "00");
        let reused_path = device("/dev/ttyACM0", Some("board-B"), "1-3", "00");
        let moved_board = device("/dev/ttyACM4", Some("board-A"), "1-7", "00");
        assert!(resolve_device(&selected, &[reused_path]).is_none());
        assert_eq!(
            resolve_device(&selected, std::slice::from_ref(&moved_board)).map(|item| item.path),
            Some("/dev/ttyACM4".into())
        );
    }

    #[test]
    fn usb_resolution_rejects_duplicate_serials_on_different_ports() {
        let selected = device("/dev/ttyACM0", Some("duplicate"), "1-2", "00");
        let first = device("/dev/ttyACM1", Some("duplicate"), "1-3", "00");
        let second = device("/dev/ttyACM2", Some("duplicate"), "1-4", "00");
        assert!(resolve_device(&selected, &[first, second]).is_none());
    }

    #[test]
    fn settings_defaults_are_8n1_without_flow_control() {
        let settings = Settings::default();
        assert_eq!(settings.baud, 115_200);
        assert_eq!(
            (settings.bits, settings.parity.as_str(), settings.stop),
            (8, "none", 1)
        );
        assert_eq!(settings.flow, "none");
    }
}
