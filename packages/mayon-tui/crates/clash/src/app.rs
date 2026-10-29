//! Interaction state and background jobs. No network request blocks drawing.
use crate::{
    api::{ApiError, Client, Connection, Proxy, RuntimeConfig},
    profiles::{self, ProfileStore, Usage},
};
use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use futures_util::StreamExt;
use std::{
    collections::{BTreeMap, HashMap},
    path::PathBuf,
    time::{Duration, Instant},
};
use tokio::{
    sync::mpsc,
    task::{JoinHandle, JoinSet},
};

pub struct Options {
    pub socket: PathBuf,
    pub profiles: PathBuf,
    pub test_url: String,
    pub usage_proxy: Option<String>,
    pub no_verge: bool,
    pub lifecycle: crate::lifecycle::Lifecycle,
}
#[derive(Clone, Copy, PartialEq)]
pub enum Page {
    Proxies,
    Profiles,
    Connections,
}
pub enum Dialog {
    Stop,
    Import {
        url: String,
        name: String,
        field: bool,
    },
    Verge {
        reason: &'static str,
    },
}
struct Snapshot {
    proxies: BTreeMap<String, Proxy>,
    config: RuntimeConfig,
    connections: Vec<Connection>,
    version: String,
}
enum Update {
    Snapshot(Result<Snapshot, ApiError>),
    Traffic(u64, u64),
    TrafficOffline,
    Message(String),
    Delay(u64, String, Option<u64>),
    DelayDone(u64),
    Usage(String, Result<Usage, String>),
}

pub struct App {
    pub opts: Options,
    client: Client,
    pub page: Page,
    pub proxies: BTreeMap<String, Proxy>,
    pub config: RuntimeConfig,
    pub connections: Vec<Connection>,
    pub version: String,
    pub store: ProfileStore,
    pub usage: HashMap<String, Usage>,
    pub group: usize,
    pub node: usize,
    pub profile: usize,
    pub connection: usize,
    pub nodes_focus: bool,
    pub filter: String,
    pub filtering: bool,
    pub dialog: Option<Dialog>,
    pub help: bool,
    pub quit: bool,
    pub status: String,
    pub online: bool,
    pub traffic: Option<(u64, u64)>,
    pub delays: HashMap<String, Option<u64>>,
    pub measuring: Option<(usize, usize)>,
    tx: mpsc::UnboundedSender<Update>,
    rx: mpsc::UnboundedReceiver<Update>,
    refresh: Option<JoinHandle<()>>,
    traffic_job: Option<JoinHandle<()>>,
    delay_job: Option<JoinHandle<()>>,
    usage_job: Option<JoinHandle<()>>,
    command_job: Option<JoinHandle<()>>,
    lifecycle_job: Option<JoinHandle<()>>,
    pub lifecycle_pending: Option<(bool, Instant)>,
    generation: u64,
    last_refresh: Instant,
}
impl App {
    pub fn new(opts: Options) -> Result<Self, reqwest::Error> {
        let client = Client::new(opts.socket.clone())?;
        let (tx, rx) = mpsc::unbounded_channel();
        Ok(Self {
            opts,
            client,
            page: Page::Proxies,
            proxies: BTreeMap::new(),
            config: RuntimeConfig::default(),
            connections: vec![],
            version: "--".into(),
            store: ProfileStore::default(),
            usage: HashMap::new(),
            group: 0,
            node: 0,
            profile: 0,
            connection: 0,
            nodes_focus: true,
            filter: String::new(),
            filtering: false,
            dialog: None,
            help: false,
            quit: false,
            status: "正在连接私有控制接口…".into(),
            online: false,
            traffic: None,
            delays: HashMap::new(),
            measuring: None,
            tx,
            rx,
            refresh: None,
            traffic_job: None,
            delay_job: None,
            usage_job: None,
            command_job: None,
            lifecycle_job: None,
            lifecycle_pending: None,
            generation: 0,
            last_refresh: Instant::now(),
        })
    }
    pub fn groups(&self) -> Vec<String> {
        self.proxies
            .iter()
            .filter(|(_, proxy)| !proxy.all.is_empty())
            .map(|(name, _)| name.clone())
            .collect()
    }
    pub fn group_name(&self) -> Option<String> {
        self.groups().get(self.group).cloned()
    }
    pub fn nodes(&self) -> Vec<String> {
        self.group_name()
            .and_then(|g| self.proxies.get(&g))
            .map(|g| {
                g.all
                    .iter()
                    .filter(|n| n.to_lowercase().contains(&self.filter.to_lowercase()))
                    .cloned()
                    .collect()
            })
            .unwrap_or_default()
    }
    pub fn delay(&self, node: &str) -> Option<Option<u64>> {
        self.delays.get(node).copied().or_else(|| {
            self.proxies
                .get(node)
                .and_then(|p| p.history.last())
                .map(|d| (d.delay > 0).then_some(d.delay))
        })
    }
    pub fn start(&mut self) {
        self.reload_profiles();
        self.refresh();
        let client = self.client.clone();
        let tx = self.tx.clone();
        self.traffic_job = Some(tokio::spawn(async move {
            loop {
                if let Ok(response) = client.traffic_response().await {
                    let mut stream = response.bytes_stream();
                    let mut buffer = Vec::new();
                    while let Some(Ok(chunk)) = stream.next().await {
                        buffer.extend_from_slice(&chunk);
                        while let Some(end) = buffer.iter().position(|b| *b == b'\n') {
                            #[derive(serde::Deserialize)]
                            struct Traffic {
                                up: u64,
                                down: u64,
                            }
                            if let Ok(value) = serde_json::from_slice::<Traffic>(&buffer[..end]) {
                                let _ = tx.send(Update::Traffic(value.up, value.down));
                            }
                            buffer.drain(..=end);
                        }
                        if buffer.len() > 65536 {
                            break;
                        }
                    }
                }
                let _ = tx.send(Update::TrafficOffline);
                tokio::time::sleep(Duration::from_secs(1)).await;
            }
        }));
    }
    fn reload_profiles(&mut self) {
        match std::fs::read_to_string(&self.opts.profiles)
            .ok()
            .and_then(|s| ProfileStore::from_yaml(&s).ok())
        {
            Some(mut store) => {
                store
                    .items
                    .retain(|i| matches!(i.kind.as_deref(), Some("remote" | "local")));
                self.store = store;
                self.profile = self.profile.min(self.store.items.len().saturating_sub(1));
            }
            None => {
                self.status = "订阅文件不可读或格式无效（只读，不修改）".into();
            }
        }
    }
    fn refresh(&mut self) {
        if self.refresh.as_ref().is_some_and(|job| !job.is_finished()) {
            return;
        }
        let client = self.client.clone();
        let tx = self.tx.clone();
        self.last_refresh = Instant::now();
        self.refresh = Some(tokio::spawn(async move {
            let result = tokio::try_join!(
                client.proxies(),
                client.configs(),
                client.connections(),
                client.version()
            );
            let snapshot = result.map(|(proxies, config, connections, version)| Snapshot {
                proxies,
                config,
                connections,
                version,
            });
            let _ = tx.send(Update::Snapshot(snapshot));
        }));
    }
    pub fn tick(&mut self) {
        while let Ok(update) = self.rx.try_recv() {
            match update {
                Update::Snapshot(Ok(snapshot)) => {
                    if !self.online {
                        self.status = "已连接 · 1 节点  2 订阅  3 连接  ? 帮助".into();
                    }
                    self.online = true;
                    if self.lifecycle_pending.is_some_and(|(running, _)| running) {
                        self.lifecycle_pending = None;
                        self.status = "Clash 已启动".into();
                    }
                    let group_name = self.group_name();
                    let node_name = self.nodes().get(self.node).cloned();
                    let connection_id = self.connections.get(self.connection).map(|c| c.id.clone());
                    self.proxies = snapshot.proxies;
                    self.config = snapshot.config;
                    self.connections = snapshot.connections;
                    self.connections.sort_by(|a, b| a.id.cmp(&b.id));
                    if let Some(index) = self
                        .groups()
                        .iter()
                        .position(|g| Some(g) == group_name.as_ref())
                    {
                        self.group = index;
                    }
                    if let Some(index) = self
                        .nodes()
                        .iter()
                        .position(|n| Some(n) == node_name.as_ref())
                    {
                        self.node = index;
                    }
                    if let Some(index) = self
                        .connections
                        .iter()
                        .position(|c| Some(&c.id) == connection_id.as_ref())
                    {
                        self.connection = index;
                    }
                    self.version = snapshot.version;
                    self.group = self.group.min(self.groups().len().saturating_sub(1));
                    self.node = self.node.min(self.nodes().len().saturating_sub(1));
                    self.connection = self
                        .connection
                        .min(self.connections.len().saturating_sub(1));
                }
                Update::Snapshot(Err(ApiError::Transport)) => {
                    self.online = false;
                    self.status = if self.lifecycle_pending.is_some_and(|(running, _)| running) {
                        "正在启动 Verge，等待内核…"
                    } else {
                        "Clash 未运行 · s 启动"
                    }
                    .into();
                    if self.lifecycle_pending.is_some_and(|(running, _)| !running)
                        && !self.opts.socket.exists()
                    {
                        self.lifecycle_pending = None;
                        self.status = "Clash 已关闭 · s 启动".into();
                    }
                }
                Update::Snapshot(Err(error)) => {
                    self.online = true;
                    self.status = match error {
                        ApiError::Rejected => "Clash 运行中 · 控制接口拒绝操作",
                        ApiError::InvalidResponse => "Clash 运行中 · 控制接口响应格式无效",
                        _ => "Clash 运行中 · 控制接口地址无效",
                    }
                    .into();
                }
                Update::Traffic(up, down) => self.traffic = Some((up, down)),
                Update::TrafficOffline => self.traffic = None,
                Update::Message(message) => {
                    self.status = message;
                    self.last_refresh = Instant::now() - Duration::from_secs(3);
                }
                Update::Delay(generation, name, delay) if generation == self.generation => {
                    self.delays.insert(name, delay.filter(|d| *d > 0));
                    if let Some((done, _)) = self.measuring.as_mut() {
                        *done += 1;
                    }
                }
                Update::DelayDone(generation) if generation == self.generation => {
                    self.measuring = None;
                    self.status = "测速完成".into();
                }
                Update::Usage(uid, result) => match result {
                    Ok(usage) => {
                        self.usage.insert(uid, usage);
                        self.status = "用量已刷新 · 仅内存中显示，未写回 Verge".into();
                    }
                    Err(message) => self.status = message,
                },
                _ => {}
            }
        }
        if self
            .lifecycle_pending
            .is_some_and(|(_, time)| time.elapsed() > Duration::from_secs(30))
        {
            self.lifecycle_pending = None;
            self.status = "Verge 操作等待超时；请检查 GUI 状态".into();
        }
        if self.last_refresh.elapsed() > Duration::from_secs(2) {
            self.refresh();
        }
    }
    fn command<F>(&mut self, future: F)
    where
        F: std::future::Future<Output = Result<(), crate::api::ApiError>> + Send + 'static,
    {
        if self
            .command_job
            .as_ref()
            .is_some_and(|job| !job.is_finished())
        {
            self.status = "操作正在进行，请稍候".into();
            return;
        }
        let tx = self.tx.clone();
        self.command_job = Some(tokio::spawn(async move {
            let message = match future.await {
                Ok(()) => "操作成功".into(),
                Err(e) => e.to_string(),
            };
            let _ = tx.send(Update::Message(message));
        }));
    }
    fn measure(&mut self, all: bool) {
        self.cancel_measure();
        let nodes = self.nodes();
        let nodes: Vec<String> = if all {
            // Whole group ignores the current text filter.
            self.group_name()
                .and_then(|g| self.proxies.get(&g))
                .map(|g| g.all.clone())
                .unwrap_or_default()
        } else {
            nodes.get(self.node).cloned().into_iter().collect()
        };
        if nodes.is_empty() {
            return;
        }
        self.measuring = Some((0, nodes.len()));
        self.status = "测速中 · Esc 取消（最多 4 个并发请求）".into();
        let client = self.client.clone();
        let tx = self.tx.clone();
        let url = self.opts.test_url.clone();
        let generation = self.generation;
        self.delay_job = Some(tokio::spawn(async move {
            let mut queue = nodes.into_iter();
            let mut jobs = JoinSet::new();
            loop {
                while jobs.len() < 4 {
                    let Some(name) = queue.next() else {
                        break;
                    };
                    let client = client.clone();
                    let url = url.clone();
                    jobs.spawn(async move {
                        let delay = client.delay(&name, &url, 5000).await.ok();
                        (name, delay)
                    });
                }
                match jobs.join_next().await {
                    Some(Ok((name, delay))) => {
                        let _ = tx.send(Update::Delay(generation, name, delay));
                    }
                    Some(Err(_)) => {}
                    None => break,
                }
            }
            let _ = tx.send(Update::DelayDone(generation));
        }));
    }
    fn cancel_measure(&mut self) {
        if let Some(job) = self.delay_job.take() {
            job.abort();
        }
        self.generation += 1; // Ignore results queued immediately before abort.
        self.measuring = None;
    }
    fn refresh_usage(&mut self) {
        if self
            .usage_job
            .as_ref()
            .is_some_and(|job| !job.is_finished())
        {
            self.status = "用量请求正在进行".into();
            return;
        }
        let Some(item) = self.store.items.get(self.profile) else {
            return;
        };
        let Some(url) = item.url.clone() else {
            self.status = "本地订阅没有远程用量".into();
            return;
        };
        let Some(uid) = item.uid.clone() else {
            return;
        };
        let proxy = self.opts.usage_proxy.clone().or_else(|| {
            self.config
                .mixed_port
                .filter(|p| *p > 0)
                .map(|p| format!("http://127.0.0.1:{p}"))
        });
        let Some(proxy) = proxy else {
            self.status = "没有可用代理端口；可通过 --usage-proxy 指定".into();
            return;
        };
        self.status = "正在经代理请求订阅用量…".into();
        let tx = self.tx.clone();
        self.usage_job = Some(tokio::spawn(async move {
            let result = usage_request(&url, &proxy).await;
            let _ = tx.send(Update::Usage(uid, result));
        }));
    }
    fn open_verge(&mut self, link: Option<reqwest::Url>) {
        if self.opts.no_verge {
            self.status = "隔离模式：外部 Verge 启动已禁用".into();
            return;
        }
        match self
            .opts
            .lifecycle
            .launch(link.as_ref().map(|l| l.as_str()))
        {
            Ok(()) => {
                self.lifecycle_pending = Some((true, Instant::now()));
                self.status = "正在启动 Verge，等待内核…".into();
            }
            Err(message) => self.status = message,
        }
    }
    fn stop_verge(&mut self) {
        if self.opts.no_verge {
            self.status = "隔离模式：Verge 生命周期已禁用".into();
            return;
        }
        let lifecycle = self.opts.lifecycle.clone();
        let tx = self.tx.clone();
        self.lifecycle_pending = Some((false, Instant::now()));
        self.lifecycle_job = Some(tokio::spawn(async move {
            let message = tokio::task::spawn_blocking(move || lifecycle.stop()).await;
            let message = match message {
                Ok(Ok(_)) => "已发送 SIGTERM，等待内核关闭…".into(),
                Ok(Err(e)) => e,
                Err(_) => "关闭任务失败".into(),
            };
            let _ = tx.send(Update::Message(message));
        }));
    }
    pub fn key(&mut self, key: KeyEvent) {
        if key.code == KeyCode::Char('c') && key.modifiers.contains(KeyModifiers::CONTROL) {
            self.quit = true;
            return;
        }
        if let Some(mut dialog) = self.dialog.take() {
            match &mut dialog {
                Dialog::Stop => match key.code {
                    KeyCode::Enter | KeyCode::Char('y') => {
                        self.stop_verge();
                        return;
                    }
                    KeyCode::Esc | KeyCode::Char('n') => return,
                    _ => {}
                },
                Dialog::Import { url, name, field } => match key.code {
                    KeyCode::Esc => return,
                    KeyCode::Tab | KeyCode::BackTab => *field = !*field,
                    KeyCode::Backspace => {
                        if *field {
                            name.pop();
                        } else {
                            url.pop();
                        }
                    }
                    KeyCode::Char(ch) if !ch.is_control() => {
                        if *field {
                            name.push(ch);
                        } else {
                            url.push(ch);
                        }
                    }
                    KeyCode::Enter => {
                        match reqwest::Url::parse(url)
                            .ok()
                            .filter(|u| matches!(u.scheme(), "http" | "https"))
                        {
                            Some(url) => {
                                if !name.is_empty() {
                                    self.dialog = Some(Dialog::Verge {
                                        reason: "该版本无法可靠传递名称；请在 Verge 导入命名，或清空名称后重试。",
                                    });
                                } else {
                                    self.open_verge(Some(profiles::verge_import_link(&url)));
                                }
                                return;
                            }
                            None => self.status = "请输入有效的 http(s) 订阅 URL".into(),
                        }
                    }
                    _ => {}
                },
                Dialog::Verge { .. } => match key.code {
                    KeyCode::Esc => return,
                    KeyCode::Enter | KeyCode::Char('o') => {
                        self.open_verge(None);
                        return;
                    }
                    _ => {}
                },
            }
            self.dialog = Some(dialog);
            return;
        }
        if self.help {
            if matches!(key.code, KeyCode::Esc | KeyCode::Char('?' | 'q')) {
                self.help = false;
            }
            return;
        }
        if self.filtering {
            match key.code {
                KeyCode::Esc => {
                    self.filtering = false;
                    self.filter.clear();
                    self.node = 0;
                }
                KeyCode::Enter => self.filtering = false,
                KeyCode::Backspace => {
                    self.filter.pop();
                    self.node = 0;
                }
                KeyCode::Char(ch) if !ch.is_control() => {
                    self.filter.push(ch);
                    self.node = 0;
                }
                _ => {}
            }
            return;
        }
        if !self.online && !matches!(key.code, KeyCode::Char('q' | '?' | 's' | 'r')) {
            return;
        }
        match key.code {
            KeyCode::Char('s') if !self.online && self.lifecycle_pending.is_none() => {
                self.open_verge(None)
            }
            KeyCode::Char('X') if self.online && self.lifecycle_pending.is_none() => {
                self.dialog = Some(Dialog::Stop)
            }
            KeyCode::Char('q') => self.quit = true,
            KeyCode::Char('?') => self.help = true,
            KeyCode::Char('1') => self.page = Page::Proxies,
            KeyCode::Char('2') => {
                self.page = Page::Profiles;
                self.reload_profiles();
            }
            KeyCode::Char('3') => self.page = Page::Connections,
            KeyCode::Tab | KeyCode::BackTab => self.nodes_focus = !self.nodes_focus,
            KeyCode::Char('h') | KeyCode::Left => self.nodes_focus = false,
            KeyCode::Char('l') | KeyCode::Right => self.nodes_focus = true,
            KeyCode::Char('j') | KeyCode::Down => self.move_selection(1, false),
            KeyCode::Char('k') | KeyCode::Up => self.move_selection(-1, false),
            KeyCode::Char('g') => self.move_selection(-1, true),
            KeyCode::Char('G') => self.move_selection(1, true),
            KeyCode::Char('/') if self.page == Page::Proxies => {
                self.filtering = true;
                self.nodes_focus = true;
            }
            KeyCode::Esc => {
                self.cancel_measure();
                self.filter.clear();
                self.status = "测速已取消 / 过滤已清除".into();
            }
            KeyCode::Char('t') if self.page == Page::Proxies => self.measure(false),
            KeyCode::Char('T') if self.page == Page::Proxies => self.measure(true),
            KeyCode::Char('m') => {
                let mode = match self.config.mode.as_str() {
                    "rule" => "global",
                    "global" => "direct",
                    _ => "rule",
                };
                let client = self.client.clone();
                self.command(async move { client.set_mode(mode).await });
            }
            KeyCode::Enter if self.page == Page::Proxies => {
                if !self.nodes_focus {
                    self.nodes_focus = true;
                    return;
                }
                if let (Some(group), Some(node)) =
                    (self.group_name(), self.nodes().get(self.node).cloned())
                {
                    let client = self.client.clone();
                    self.command(async move { client.select(&group, &node).await });
                }
            }
            KeyCode::Char('i') if self.page == Page::Profiles => {
                self.dialog = Some(Dialog::Import {
                    url: String::new(),
                    name: String::new(),
                    field: false,
                })
            }
            KeyCode::Char('f') if self.page == Page::Profiles => self.refresh_usage(),
            KeyCode::Char('u') if self.page == Page::Profiles => {
                self.dialog = Some(Dialog::Verge {
                    reason: "Verge 2.4.7 未提供外部更新接口，请在 Verge 更新订阅。",
                })
            }
            KeyCode::Enter if self.page == Page::Profiles => {
                self.dialog = Some(Dialog::Verge {
                    reason: "Verge 2.4.7 未提供外部切换接口，请在 Verge 选择订阅。",
                })
            }
            KeyCode::Char('o') if self.page == Page::Profiles => {
                self.dialog = Some(Dialog::Verge {
                    reason: "打开 Clash Verge Rev 管理订阅。",
                })
            }
            KeyCode::Char('r') => {
                self.reload_profiles();
                self.refresh();
            }
            KeyCode::Char('x') if self.page == Page::Connections => {
                if let Some(connection) = self.connections.get(self.connection) {
                    let id = connection.id.clone();
                    let client = self.client.clone();
                    self.command(async move { client.close(&id).await });
                }
            }
            _ => {}
        }
    }
    fn move_selection(&mut self, delta: isize, edge: bool) {
        let (index, len) = match self.page {
            Page::Proxies if self.nodes_focus => {
                let len = self.nodes().len();
                (&mut self.node, len)
            }
            Page::Proxies => {
                let len = self.groups().len();
                self.node = 0;
                (&mut self.group, len)
            }
            Page::Profiles => (&mut self.profile, self.store.items.len()),
            Page::Connections => (&mut self.connection, self.connections.len()),
        };
        *index = if edge {
            if delta > 0 {
                len.saturating_sub(1)
            } else {
                0
            }
        } else {
            index
                .saturating_add_signed(delta)
                .min(len.saturating_sub(1))
        };
    }
    pub fn mouse(&mut self, event: crossterm::event::MouseEvent, size: ratatui::layout::Size) {
        use crossterm::event::{MouseButton, MouseEventKind};
        if self.dialog.is_some() || self.help || !self.online {
            return;
        }
        match event.kind {
            MouseEventKind::ScrollDown => self.move_selection(1, false),
            MouseEventKind::ScrollUp => self.move_selection(-1, false),
            MouseEventKind::Down(MouseButton::Left) => {
                if event.row == 1 {
                    if let Some(page) = crate::ui::tab_at(event.column) {
                        self.key(KeyEvent::new(KeyCode::Char(page), KeyModifiers::NONE));
                    }
                    return;
                }
                if event.row < 4 || event.row >= size.height.saturating_sub(3) {
                    return;
                }
                let (index, len, height) = match self.page {
                    Page::Proxies if event.column < size.width * 32 / 100 => {
                        self.nodes_focus = false;
                        (
                            &mut self.group,
                            self.proxies.values().filter(|p| !p.all.is_empty()).count(),
                            2,
                        )
                    }
                    Page::Proxies => {
                        self.nodes_focus = true;
                        let n = self.nodes().len();
                        (&mut self.node, n, 1)
                    }
                    Page::Profiles => (&mut self.profile, self.store.items.len(), 5),
                    Page::Connections => (&mut self.connection, self.connections.len(), 2),
                };
                let visible = size.height.saturating_sub(7) as usize / height;
                let offset = index.saturating_add(1).saturating_sub(visible);
                *index = (offset + (event.row as usize - 4) / height).min(len.saturating_sub(1));
            }
            _ => {}
        }
    }
    pub fn stop(&mut self) {
        self.cancel_measure();
        for job in [
            &mut self.refresh,
            &mut self.traffic_job,
            &mut self.usage_job,
            &mut self.command_job,
            &mut self.lifecycle_job,
        ]
        .into_iter()
        .filter_map(Option::take)
        {
            job.abort();
        }
    }
}

/// HEAD first, GET fallback without reading/storing the subscription body.
/// Redirects are disabled: subscription credentials must not be forwarded to a
/// different host silently. Explicit proxies are used even for loopback URLs.
async fn usage_request(url: &str, proxy: &str) -> Result<Usage, String> {
    let url = reqwest::Url::parse(url)
        .ok()
        .filter(|u| matches!(u.scheme(), "http" | "https"))
        .ok_or("订阅 URL 无效")?;
    let proxy = reqwest::Proxy::all(proxy).map_err(|_| "代理地址无效")?;
    let http = reqwest::Client::builder()
        .no_proxy()
        .proxy(proxy)
        .timeout(Duration::from_secs(15))
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .map_err(|_| "无法创建用量客户端")?;
    for method in [reqwest::Method::HEAD, reqwest::Method::GET] {
        let response = http
            .request(method, url.clone())
            .send()
            .await
            .map_err(|_| "用量请求失败（URL 已隐藏）")?;
        if response.status().is_success() {
            if let Some(value) = response.headers().get("subscription-userinfo") {
                return value
                    .to_str()
                    .ok()
                    .and_then(|s| Usage::from_header(s).ok())
                    .ok_or_else(|| "用量响应头格式无效".into());
            }
        }
    }
    Err("服务器未返回 subscription-userinfo；未修改本地订阅".into())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    fn app() -> App {
        let mut app = App::new(Options {
            socket: "/nonexistent.sock".into(),
            profiles: "/nonexistent.yaml".into(),
            test_url: "http://example.invalid".into(),
            usage_proxy: None,
            no_verge: true,
            lifecycle: crate::lifecycle::Lifecycle::default(),
        })
        .unwrap();
        app.online = true;
        app
    }

    #[test]
    fn filter_and_cancel_ignore_old_results() {
        let mut app = app();
        app.proxies.insert(
            "选择".into(),
            Proxy {
                all: vec!["香港 HK".into(), "日本 JP".into()],
                ..Default::default()
            },
        );
        app.filter = "香港".into();
        assert_eq!(app.nodes(), vec!["香港 HK"]);
        let old = app.generation;
        app.cancel_measure();
        app.tx
            .send(Update::Delay(old, "香港 HK".into(), Some(12)))
            .unwrap();
        app.tick();
        assert!(!app.delays.contains_key("香港 HK"));
    }

    #[test]
    fn connection_refresh_keeps_selected_id() {
        let mut app = app();
        app.connections = vec![
            Connection {
                id: "b".into(),
                ..Default::default()
            },
            Connection {
                id: "a".into(),
                ..Default::default()
            },
        ];
        app.connection = 0;
        app.tx
            .send(Update::Snapshot(Ok(Snapshot {
                proxies: BTreeMap::new(),
                config: RuntimeConfig::default(),
                version: "test".into(),
                connections: vec![
                    Connection {
                        id: "a".into(),
                        ..Default::default()
                    },
                    Connection {
                        id: "b".into(),
                        ..Default::default()
                    },
                ],
            })))
            .unwrap();
        app.tick();
        assert_eq!(app.connections[app.connection].id, "b");
    }

    #[tokio::test]
    async fn usage_uses_proxy_and_get_fallback_without_downloading_body() {
        // The origin is intentionally unresolvable. Only the local proxy below
        // can answer, proving the request did not bypass the configured proxy.
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let proxy = format!("http://{}", listener.local_addr().unwrap());
        let server = tokio::spawn(async move {
            for method in ["HEAD", "GET"] {
                let (mut socket, _) = listener.accept().await.unwrap();
                let mut buffer = [0; 4096];
                let count = socket.read(&mut buffer).await.unwrap();
                let request = std::str::from_utf8(&buffer[..count]).unwrap();
                assert!(request.starts_with(&format!("{method} http://unresolvable.invalid/sub")));
                let response = if method == "HEAD" {
                    "HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                } else {
                    // Deliberately never send a 1GB body. Only headers are used.
                    "HTTP/1.1 200 OK\r\nSubscription-Userinfo: upload=5; download=10; total=100\r\nContent-Length: 1000000000\r\nConnection: close\r\n\r\n"
                };
                socket.write_all(response.as_bytes()).await.unwrap();
            }
        });
        let usage = usage_request("http://unresolvable.invalid/sub", &proxy)
            .await
            .unwrap();
        assert_eq!(usage.used_bytes(), 15);
        assert_eq!(usage.remaining_bytes(), Some(85));
        server.await.unwrap();
    }
}
