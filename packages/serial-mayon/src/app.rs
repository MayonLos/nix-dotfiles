use crate::{
    codec::{self, Encoding, Framer},
    flash::{Flash, FlashEvent},
    store::{private_file, Favorite, Profile, Store},
    transport::{self, Command, Device, Event, Worker},
};
use chrono::{DateTime, Local};
use mayon_ui::{
    input::TextInput,
    search::{Matcher, SearchText},
};
use std::{
    collections::{BTreeMap, VecDeque},
    fs::File,
    io::{self, Write},
    path::PathBuf,
    time::{Duration, Instant},
};

pub const BAUDS: &[u32] = &[
    9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600, 1_000_000, 2_000_000,
];
pub const MAX_CAPTURE_BYTES: usize = 32 * 1024 * 1024;
#[derive(Clone)]
pub struct Record {
    pub id: u64,
    pub at: DateTime<Local>,
    pub elapsed: f64,
    pub kind: &'static str,
    pub raw: Vec<u8>,
    pub text: String,
    pub search_text: SearchText,
}
pub struct Capture {
    pub records: VecDeque<Record>,
    pub next: u64,
    bytes: usize,
    pub evicted: u64,
    limit: usize,
}
impl Capture {
    pub fn reencode(&mut self, encoding: Encoding) {
        for record in &mut self.records {
            if record.kind == "RX" {
                record.text = encoding.decode(&record.raw);
                record.search_text = SearchText::new(&codec::plain(&record.text));
            }
        }
        self.bytes = self
            .records
            .iter()
            .map(|r| r.raw.len() + r.text.len())
            .sum();
        self.trim();
    }
    fn trim(&mut self) {
        while self.records.len() > self.limit || self.bytes > MAX_CAPTURE_BYTES {
            if let Some(record) = self.records.pop_front() {
                self.bytes -= record.raw.len() + record.text.len();
                self.evicted += 1;
            } else {
                break;
            }
        }
    }
    pub fn new(limit: usize) -> Self {
        Self {
            records: VecDeque::new(),
            next: 0,
            bytes: 0,
            evicted: 0,
            limit: limit.clamp(100, 1_000_000),
        }
    }
    pub fn push(
        &mut self,
        at: DateTime<Local>,
        elapsed: f64,
        kind: &'static str,
        raw: Vec<u8>,
        text: String,
    ) {
        let size = raw.len() + text.len();
        self.bytes += size;
        self.records.push_back(Record {
            id: self.next,
            at,
            elapsed,
            kind,
            raw,
            search_text: SearchText::new(&codec::plain(&text)),
            text,
        });
        self.next += 1;
        self.trim();
    }
}
pub struct Logger {
    pub path: PathBuf,
    raw: File,
    text: File,
    csv: Option<File>,
}
impl Logger {
    fn start(store: &Store, csv: bool) -> io::Result<Self> {
        let stem = Local::now().format("%Y%m%d-%H%M%S-%f").to_string();
        let path = store.data.join("logs").join(stem);
        Ok(Self {
            raw: private_file(&path.with_extension("bin"))?,
            text: private_file(&path.with_extension("log"))?,
            csv: if csv {
                let mut f = private_file(&path.with_extension("csv"))?;
                writeln!(f, "timestamp,seconds,channel,value")?;
                Some(f)
            } else {
                None
            },
            path,
        })
    }
    fn record(&mut self, r: &Record) -> io::Result<()> {
        writeln!(
            self.text,
            "{} [{}] {}",
            r.at.to_rfc3339(),
            r.kind,
            codec::plain(&r.text)
        )?;
        if r.kind == "RX" {
            if let Some(f) = &mut self.csv {
                for (key, value) in codec::parse_values(&codec::plain(&r.text)) {
                    writeln!(
                        f,
                        "{},{:.6},\"{}\",{}",
                        r.at.to_rfc3339(),
                        r.elapsed,
                        key.replace('"', "\"\""),
                        value
                    )?;
                }
            }
        }
        Ok(())
    }
}
#[derive(Clone, Copy, PartialEq, Debug)]
pub enum InputKind {
    Send,
    Search,
    Filter,
    Baud,
    Settings,
    Favorite,
    File,
    Timer,
    FlashCommand,
    FlashDir,
    Highlights,
}
pub struct Input {
    pub kind: InputKind,
    pub text: TextInput,
    pub before: String,
}
pub struct Repeat {
    pub bytes: Vec<u8>,
    pub every: Duration,
    pub next: Instant,
}
pub struct App {
    pub store: Store,
    pub worker: Worker,
    pub devices: Vec<Device>,
    pub selected: usize,
    pub device: Option<Device>,
    pub profile: Profile,
    pub connected: bool,
    pub status: String,
    pub page: usize,
    pub capture: Capture,
    pub wire: Capture,
    pub wire_anchor: Option<u64>,
    pub framer: Framer,
    pub started: Instant,
    pub disconnected: Option<Instant>,
    pub mode: usize,
    pub timestamp: usize,
    pub anchor: Option<u64>,
    pub scroll: usize,
    pub search: String,
    pub filter: String,
    pub found: Option<u64>,
    pub graph: bool,
    pub series: BTreeMap<String, VecDeque<(f64, f64)>>,
    pub input: Option<Input>,
    pub help: bool,
    pub tx_hex: bool,
    pub history_index: usize,
    pub favorite_index: usize,
    pub settings_index: usize,
    pub last_sent: Vec<u8>,
    pub repeat: Option<Repeat>,
    pub logger: Option<Logger>,
    pub csv: bool,
    pub rx_total: u64,
    pub tx_total: u64,
    pub rate: f64,
    pub rate_tx: f64,
    rate_at: Instant,
    rate_rx: u64,
    rate_tx_bytes: u64,
    refresh_at: Instant,
    pub flash: Option<Flash>,
    pub flash_lines: VecDeque<String>,
    flash_wait: bool,
    flash_seq: u64,
    pending_flash: Option<(String, String)>,
}
impl App {
    pub fn new(store: Store) -> Self {
        let limit = store.config.scrollback;
        Self {
            store,
            worker: Worker::start(),
            devices: transport::discover(),
            selected: 0,
            device: None,
            profile: Profile::default(),
            connected: false,
            status: "选择端口后 Enter 连接 · ? 查看帮助".into(),
            page: 1,
            capture: Capture::new(limit),
            wire: Capture::new(limit),
            wire_anchor: None,
            framer: Framer::default(),
            started: Instant::now(),
            disconnected: None,
            mode: 0,
            timestamp: 0,
            anchor: None,
            scroll: 0,
            search: String::new(),
            filter: String::new(),
            found: None,
            graph: true,
            series: BTreeMap::new(),
            input: None,
            help: false,
            tx_hex: false,
            history_index: 0,
            favorite_index: 0,
            settings_index: 0,
            last_sent: Vec::new(),
            repeat: None,
            logger: None,
            csv: false,
            rx_total: 0,
            tx_total: 0,
            rate: 0.0,
            rate_tx: 0.0,
            rate_at: Instant::now(),
            rate_rx: 0,
            rate_tx_bytes: 0,
            refresh_at: Instant::now(),
            flash: None,
            flash_lines: VecDeque::new(),
            flash_wait: false,
            flash_seq: 0,
            pending_flash: None,
        }
    }
    pub fn command(&mut self, command: Command) -> bool {
        if (self.flash.is_some() || self.flash_wait)
            && !matches!(command, Command::Release(_) | Command::Shutdown)
        {
            self.status = "烧录期间串口已释放，等待烧录结束".into();
            return false;
        }
        match self.worker.tx.try_send(command) {
            Ok(()) => true,
            Err(e) => {
                self.status = format!("串口队列忙：{e}");
                false
            }
        }
    }
    pub fn persist(&mut self) {
        if let Some(d) = &self.device {
            self.store
                .config
                .devices
                .insert(d.key(), self.profile.clone());
        }
        if let Err(e) = self.store.save() {
            self.status = format!("保存失败：{e}");
        }
    }
    pub fn select(&mut self, device: Device, baud: Option<u32>) {
        if self.flash.is_some() || self.flash_wait {
            self.status = "烧录期间不能切换设备".into();
            return;
        }
        self.persist();
        self.flush();
        self.profile = self
            .store
            .config
            .devices
            .get(&device.key())
            .cloned()
            .unwrap_or_default();
        if let Some(baud) = baud {
            self.profile.settings.baud = baud;
        }
        self.device = Some(device.clone());
        self.connected = false;
        self.repeat = None;
        self.series.clear();
        self.disconnected = Some(Instant::now());
        self.command(Command::Connect(device, self.profile.settings.clone()));
        self.page = 0;
        self.persist();
    }
    pub fn note(&mut self, kind: &'static str, text: String, raw: Vec<u8>) {
        let text = if kind == "RX" && raw.len() >= 16 * 1024 {
            format!("{text} [达到16KiB显示上限；完整字节见HEX/.bin]")
        } else {
            text
        };
        let elapsed = self.started.elapsed().as_secs_f64();
        if kind != "RX" {
            self.wire
                .push(Local::now(), elapsed, kind, raw.clone(), text.clone());
        }
        if kind == "RX" {
            for (key, value) in codec::parse_values(&codec::plain(&text)) {
                if self.series.len() >= 16 && !self.series.contains_key(&key) {
                    continue;
                }
                let data = self.series.entry(key).or_default();
                data.push_back((elapsed, value));
                while data.len() > 1024 {
                    data.pop_front();
                }
            }
        }
        self.capture.push(Local::now(), elapsed, kind, raw, text);
        if let Some(logger) = &mut self.logger {
            if let Err(e) = logger.record(self.capture.records.back().unwrap()) {
                self.status = format!("日志写入失败：{e}");
                self.logger = None;
            }
        }
    }
    pub fn flush(&mut self) {
        if let Some(raw) = self.framer.flush() {
            let text = self.profile.encoding.decode(&raw);
            self.note("RX", text, raw);
        }
    }
    pub fn toggle_encoding(&mut self) {
        self.flush();
        self.profile.encoding = if self.profile.encoding == Encoding::Utf8 {
            Encoding::Gbk
        } else {
            Encoding::Utf8
        };
        self.capture.reencode(self.profile.encoding);
        self.persist();
    }
    pub fn receive(&mut self, raw: Vec<u8>) {
        self.rx_total += raw.len() as u64;
        for chunk in raw.chunks(16) {
            let hex = chunk
                .iter()
                .map(|b| format!("{b:02X}"))
                .collect::<Vec<_>>()
                .join(" ");
            let ascii: String = chunk
                .iter()
                .map(|b| {
                    if (32..127).contains(b) {
                        *b as char
                    } else {
                        '.'
                    }
                })
                .collect();
            self.wire.push(
                Local::now(),
                self.started.elapsed().as_secs_f64(),
                "RX",
                chunk.to_vec(),
                format!("{hex}  {ascii}"),
            );
        }
        if let Some(logger) = &mut self.logger {
            if let Err(e) = logger.raw.write_all(&raw) {
                self.status = format!("原始日志失败：{e}");
                self.logger = None;
            }
        }
        for line in self.framer.push(&raw) {
            let text = self.profile.encoding.decode(&line);
            self.note("RX", text, line);
        }
    }
    pub fn tick(&mut self) {
        // Drain bounded batches so hot streams cannot starve keyboard/drawing.
        for _ in 0..512 {
            let Ok(event) = self.worker.rx.try_recv() else {
                break;
            };
            match event {
                Event::Rx(raw) => self.receive(raw),
                Event::Tx(n) => self.tx_total += n as u64,
                Event::Connected(path) => {
                    self.connected = true;
                    let gap = self.disconnected.take().map(|t| t.elapsed().as_secs_f64());
                    self.note(
                        "连接",
                        format!(
                            "{path} 已连接{}",
                            gap.map(|s| format!(" · 断开 {s:.2}s")).unwrap_or_default()
                        ),
                        Vec::new(),
                    );
                    self.status = format!("已连接 {path}");
                    if let Some(d) = &mut self.device {
                        d.path = path;
                    }
                }
                Event::Disconnected(reason) => {
                    self.flush();
                    self.connected = false;
                    self.repeat = None;
                    self.disconnected.get_or_insert_with(Instant::now);
                    self.note("断开", reason, Vec::new());
                    self.series.clear();
                }
                Event::Released(id) => {
                    if self.flash_wait && id == self.flash_seq {
                        self.flash_wait = false;
                        self.start_flash();
                    }
                }
                Event::Error(error) => {
                    self.note("错误", error.clone(), Vec::new());
                    self.status = error;
                }
            }
        }
        if self.refresh_at.elapsed() > Duration::from_millis(750) {
            self.replace_devices(transport::discover());
            self.refresh_at = Instant::now();
        }
        let elapsed = self.rate_at.elapsed().as_secs_f64();
        if elapsed >= 1.0 {
            self.rate = (self.rx_total - self.rate_rx) as f64 / elapsed;
            self.rate_tx = (self.tx_total - self.rate_tx_bytes) as f64 / elapsed;
            self.rate_rx = self.rx_total;
            self.rate_tx_bytes = self.tx_total;
            self.rate_at = Instant::now();
        }
        if let Some(repeat) = &mut self.repeat {
            if Instant::now() >= repeat.next && self.connected {
                let bytes = repeat.bytes.clone();
                repeat.next = Instant::now() + repeat.every;
                self.command(Command::Write(bytes));
            }
        }
        let mut done = None;
        if let Some(flash) = &self.flash {
            for _ in 0..200 {
                match flash.rx.try_recv() {
                    Ok(FlashEvent::Line(line)) => {
                        self.flash_lines.push_back(codec::plain(&line));
                        while self.flash_lines.len() > 2000 {
                            self.flash_lines.pop_front();
                        }
                    }
                    Ok(FlashEvent::Done(message)) => {
                        done = Some(message);
                        break;
                    }
                    Err(_) => break,
                }
            }
        }
        if let Some(message) = done {
            self.flash = None;
            self.flash_lines.push_back(message.clone());
            self.note("烧录", message, Vec::new());
            self.reconnect();
        }
    }
    pub fn reconnect(&mut self) {
        if self.flash.is_some() || self.flash_wait {
            return;
        }
        if let Some(device) = self.device.clone() {
            self.command(Command::Connect(device, self.profile.settings.clone()));
        }
    }
    pub fn send(&mut self, text: &str) -> Result<(), String> {
        if !self.connected {
            return Err("设备未连接".into());
        }
        let bytes = payload(
            text,
            self.tx_hex,
            self.profile.encoding,
            &self.profile.ending,
        )?;
        if bytes.len() > 1024 * 1024 {
            return Err("单次发送限制 1 MiB".into());
        }
        if !self.command(Command::Write(bytes.clone())) {
            return Err(self.status.clone());
        }
        self.last_sent = bytes.clone();
        self.store.remember(text.to_owned());
        self.persist();
        self.note(
            "TX",
            if self.tx_hex {
                format!("HEX {text}")
            } else {
                text.to_owned()
            },
            bytes,
        );
        self.status = "已排队发送".into();
        Ok(())
    }
    pub fn replace_devices(&mut self, devices: Vec<Device>) {
        let selected = self.devices.get(self.selected).map(Device::key);
        self.devices = devices;
        self.selected = selected
            .and_then(|id| self.devices.iter().position(|d| d.key() == id))
            .unwrap_or(0);
    }
    pub fn open(&mut self, kind: InputKind, text: String) {
        let before = match kind {
            InputKind::Filter => self.filter.clone(),
            InputKind::Search => self.search.clone(),
            _ => String::new(),
        };
        self.input = Some(Input {
            kind,
            text: text.into(),
            before,
        });
        self.history_index = self.store.history.len();
    }
    pub fn submit(&mut self, kind: InputKind, text: String) -> Result<(), String> {
        match kind {
            InputKind::Send => self.send(&text)?,
            InputKind::Search => {
                self.search = text;
                self.search_next();
            }
            InputKind::Filter => {
                self.filter = text;
                self.scroll = 0;
            }
            InputKind::Baud => {
                let baud = text.trim().parse::<u32>().map_err(|_| "请输入有效波特率")?;
                if baud == 0 || baud > 12_000_000 {
                    return Err("波特率范围 1–12000000".into());
                }
                self.profile.settings.baud = baud;
                self.apply();
            }
            InputKind::Settings => {
                let mut settings = self.profile.settings.clone();
                for field in text.split_whitespace() {
                    let (key, value) = field
                        .split_once('=')
                        .ok_or("使用 baud=115200 bits=8 parity=none stop=1 flow=none")?;
                    match key {
                        "baud" => settings.baud = value.parse().map_err(|_| "波特率无效")?,
                        "bits" => settings.bits = value.parse().map_err(|_| "数据位无效")?,
                        "stop" => settings.stop = value.parse().map_err(|_| "停止位无效")?,
                        "parity" => settings.parity = value.into(),
                        "flow" => settings.flow = value.into(),
                        _ => return Err(format!("未知参数 {key}")),
                    }
                }
                validate_settings(&settings)?;
                self.profile.settings = settings;
                self.apply();
            }
            InputKind::Favorite => {
                let (name, value) = text.split_once('=').ok_or("格式：名称=命令")?;
                if name.trim().is_empty() {
                    return Err("名称不能为空".into());
                }
                self.store.config.favorites.push(Favorite {
                    name: name.trim().into(),
                    value: value.into(),
                    hex: self.tx_hex,
                });
                self.persist();
            }
            InputKind::File => {
                if !self.connected {
                    return Err("设备未连接".into());
                }
                let metadata = std::fs::metadata(&text).map_err(|e| e.to_string())?;
                if !metadata.is_file() || metadata.len() > 1024 * 1024 {
                    return Err("仅支持不超过 1 MiB 的普通文件；按原字节发送".into());
                }
                let bytes = std::fs::read(&text).map_err(|e| e.to_string())?;
                let size = bytes.len();
                self.command(Command::Write(bytes));
                self.note("TX", format!("发送文件 {text} · {size} B"), Vec::new());
            }
            InputKind::Timer => {
                let ms = text
                    .trim()
                    .parse::<u64>()
                    .map_err(|_| "请输入毫秒数；0 停止")?;
                if ms == 0 {
                    self.repeat = None;
                } else {
                    if ms < 20 {
                        return Err("最短间隔 20 ms".into());
                    }
                    if self.last_sent.is_empty() || !self.connected {
                        return Err("先连接并发送一条命令".into());
                    }
                    self.repeat = Some(Repeat {
                        bytes: self.last_sent.clone(),
                        every: Duration::from_millis(ms),
                        next: Instant::now() + Duration::from_millis(ms),
                    });
                }
            }
            InputKind::FlashCommand => {
                self.profile.flash = text;
                self.persist();
            }
            InputKind::FlashDir => {
                let path = PathBuf::from(&text);
                if !text.is_empty() && !path.is_dir() {
                    return Err("目录不存在".into());
                }
                self.profile.flash_dir = text;
                self.persist();
            }
            InputKind::Highlights => {
                self.store.config.highlights = text
                    .split(',')
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .map(str::to_string)
                    .collect();
                self.persist();
            }
        }
        Ok(())
    }
    pub fn apply(&mut self) {
        self.persist();
        if self.flash.is_some() || self.flash_wait {
            self.status = "参数已保存，将在烧录结束后应用".into();
            return;
        }
        if self.device.is_some() {
            self.flush();
            self.reconnect();
        }
    }
    pub fn view_capture(&self) -> &Capture {
        if self.mode == 0 {
            &self.capture
        } else {
            &self.wire
        }
    }
    pub fn view_anchor(&self) -> Option<u64> {
        if self.mode == 0 {
            self.anchor
        } else {
            self.wire_anchor
        }
    }
    pub fn pause(&mut self) {
        if self.anchor.is_some() {
            self.anchor = None;
            self.wire_anchor = None;
            self.scroll = 0;
        } else {
            self.anchor = self.capture.records.back().map(|r| r.id).or(Some(0));
            self.wire_anchor = self.wire.records.back().map(|r| r.id).or(Some(0));
        }
    }
    pub fn scroll_up(&mut self, n: usize) {
        if self.anchor.is_none() {
            self.pause();
        }
        self.scroll = self
            .scroll
            .saturating_add(n)
            .min(self.view_capture().records.len().saturating_sub(1));
    }
    pub fn search_matches(&self) -> Vec<u64> {
        if self.search.trim().is_empty() {
            return Vec::new();
        }
        let matcher = Matcher::new(&self.search);
        let filter = Matcher::new(&self.filter);
        self.view_capture()
            .records
            .iter()
            .filter(|r| {
                (r.kind != "RX" || filter.matches_in(&r.search_text))
                    && matcher.matches_in(&r.search_text)
            })
            .map(|r| r.id)
            .collect()
    }
    pub fn search_next(&mut self) {
        self.search_move(false);
    }
    pub fn search_previous(&mut self) {
        self.search_move(true);
    }
    fn search_move(&mut self, reverse: bool) {
        let matches = self.search_matches();
        self.found = if reverse {
            matches
                .iter()
                .rev()
                .copied()
                .find(|id| self.found.is_none_or(|last| *id < last))
                .or_else(|| matches.last().copied())
        } else {
            matches
                .iter()
                .copied()
                .find(|id| self.found.is_none_or(|last| *id > last))
                .or_else(|| matches.first().copied())
        };
        if let Some(id) = self.found {
            if self.mode == 0 {
                self.anchor = Some(id);
            } else {
                self.wire_anchor = Some(id);
                self.anchor = self.capture.records.back().map(|r| r.id).or(Some(0));
            }
            self.scroll = 0;
            self.status = format!(
                "第 {}/共 {} 个 · n 下一个 · N 上一个",
                matches.iter().position(|n| *n == id).unwrap_or(0) + 1,
                matches.len()
            );
        } else {
            self.status = "没有匹配 · Esc 清除".into();
        }
    }
    pub fn logging(&mut self) {
        if self.logger.is_some() {
            self.flush();
            self.logger = None;
            self.status = "日志已关闭".into();
            return;
        }
        match Logger::start(&self.store, self.csv) {
            Ok(logger) => {
                self.status = format!("日志 → {}.*", logger.path.display());
                self.logger = Some(logger);
            }
            Err(e) => self.status = format!("无法创建日志：{e}"),
        }
    }
    pub fn request_flash(&mut self) {
        if self.flash.is_some() || self.flash_wait {
            self.status = "烧录正在执行".into();
            return;
        }
        if self.device.is_none() {
            self.status = "先选择监视设备".into();
            return;
        }
        if self.profile.flash.trim().is_empty() {
            self.status = "先在 5 烧录 页设置命令与工作目录；不猜芯片型号".into();
            self.page = 4;
            return;
        }
        self.repeat = None;
        self.flash_wait = true;
        self.status = "等待串口关闭确认 · Esc 取消".into();
        self.flash_seq = self.flash_seq.wrapping_add(1);
        self.pending_flash = Some((self.profile.flash.clone(), self.profile.flash_dir.clone()));
        self.page = 4;
        if !self.command(Command::Release(self.flash_seq)) {
            self.flash_wait = false;
            self.pending_flash = None;
        }
    }
    fn start_flash(&mut self) {
        self.flash_lines.clear();
        let Some((command, directory)) = self.pending_flash.take() else {
            return;
        };
        match Flash::start(&command, &directory) {
            Ok(flash) => {
                self.flash = Some(flash);
                self.status = "串口已释放，烧录中 · Esc 取消".into();
            }
            Err(e) => {
                self.status = format!("无法启动烧录：{e}");
                self.reconnect();
            }
        }
    }
    pub fn cancel_flash(&mut self) {
        if self.flash_wait {
            self.flash_wait = false;
            self.pending_flash = None;
            self.status = "已取消待执行的烧录".into();
            self.reconnect();
        }
        if let Some(mut flash) = self.flash.take() {
            flash.cancel();
            self.note("烧录", "已取消烧录".into(), Vec::new());
            self.reconnect();
        }
    }
}
impl Drop for App {
    fn drop(&mut self) {
        self.flush();
        if let Some(flash) = &mut self.flash {
            flash.cancel();
        }
        let _ = self.worker.tx.try_send(Command::Shutdown);
        self.persist();
    }
}
pub fn payload(text: &str, hex: bool, encoding: Encoding, ending: &str) -> Result<Vec<u8>, String> {
    if hex {
        return codec::parse_hex(text);
    }
    let mut bytes = encoding.encode(text)?;
    bytes.extend_from_slice(match ending {
        "CR" => b"\r",
        "LF" => b"\n",
        "CRLF" => b"\r\n",
        _ => b"",
    });
    Ok(bytes)
}
pub fn validate_settings(s: &transport::Settings) -> Result<(), String> {
    if s.baud == 0
        || s.baud > 12_000_000
        || !(5..=8).contains(&s.bits)
        || !(1..=2).contains(&s.stop)
        || !["none", "odd", "even"].contains(&s.parity.as_str())
        || !["none", "hardware", "software"].contains(&s.flow.as_str())
    {
        Err("参数无效：bits=5..8 parity=none/odd/even stop=1/2 flow=none/hardware/software".into())
    } else {
        Ok(())
    }
}
pub fn explicit_device(path: String) -> Device {
    Device {
        path,
        vid: 0,
        pid: 0,
        serial: None,
        product: "手动端口".into(),
        interface: String::new(),
        topology: String::new(),
    }
}
pub fn detected_flash() -> Vec<&'static str> {
    ["probe-rs", "openocd", "st-flash"]
        .into_iter()
        .filter(|name| {
            std::env::split_paths(&std::env::var_os("PATH").unwrap_or_default())
                .any(|dir| dir.join(name).is_file())
        })
        .collect()
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn payload_endings_and_binary() {
        for (ending, suffix) in [
            ("CR", b"\r".as_slice()),
            ("LF", b"\n"),
            ("CRLF", b"\r\n"),
            ("无", b""),
        ] {
            assert_eq!(
                payload("a", false, Encoding::Utf8, ending).unwrap(),
                [b"a", suffix].concat()
            );
        }
        assert_eq!(
            payload("00 ff", true, Encoding::Gbk, "CRLF").unwrap(),
            vec![0, 255]
        );
    }
    #[test]
    fn capture_pause_anchor_survives_new_data_and_reports_eviction() {
        let mut capture = Capture::new(100);
        for n in 0..150 {
            capture.push(Local::now(), n as f64, "RX", vec![1], n.to_string());
        }
        assert_eq!(capture.evicted, 50);
        assert_eq!(capture.records.front().unwrap().id, 50);
        assert_eq!(capture.records.back().unwrap().id, 149);
    }
    #[test]
    fn invalid_settings_are_atomic() {
        let mut s = transport::Settings::default();
        assert!(validate_settings(&s).is_ok());
        s.bits = 9;
        assert!(validate_settings(&s).is_err());
    }
}
