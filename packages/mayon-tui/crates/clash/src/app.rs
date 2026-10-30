//! UI-owned state; bounded streams and cancellable workers never draw or block input.
use crate::{
    api::{
        ApiError, Client, Connection, ConnectionsResponse, LogEntry, Provider, Proxy, Rule,
        RuntimeConfig, Traffic,
    },
    profiles::{self, ProfileStore, Usage},
    search,
    settings::Settings,
};
use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use futures_util::StreamExt;
use std::{
    collections::{BTreeMap, HashMap, VecDeque},
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
    pub settings: Settings,
    pub usage_proxy: Option<String>,
    pub no_verge: bool,
    pub lifecycle: crate::lifecycle::Lifecycle,
}
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
#[repr(usize)]
pub enum Page {
    Overview,
    Proxies,
    Profiles,
    Connections,
    Rules,
    Logs,
    Tools,
}
impl Page {
    pub const ALL: [Self; 7] = [
        Self::Overview,
        Self::Proxies,
        Self::Profiles,
        Self::Connections,
        Self::Rules,
        Self::Logs,
        Self::Tools,
    ];
}
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Sort {
    Default,
    Delay,
    Name,
}
impl Sort {
    pub fn label(self) -> &'static str {
        match self {
            Self::Default => "默认",
            Self::Delay => "延迟",
            Self::Name => "名称",
        }
    }
}
#[derive(Clone)]
pub enum Action {
    Stop,
    Close(Vec<String>),
    CloseAll,
    Tool(usize),
}
pub enum Dialog {
    Confirm {
        action: Action,
        body: String,
    },
    Import {
        url: String,
        name: String,
        field: bool,
    },
    Verge {
        reason: &'static str,
    },
    Detail(String),
}
struct Snapshot {
    proxies: BTreeMap<String, Proxy>,
    config: RuntimeConfig,
    version: String,
}
type Resources = (
    BTreeMap<String, Provider>,
    BTreeMap<String, Provider>,
    Vec<Rule>,
);
enum Update {
    Snapshot(Result<Snapshot, ApiError>),
    Resources(Result<Resources, ApiError>),
    Connections(ConnectionsResponse),
    ConnectionsOffline,
    Traffic(Traffic),
    TrafficOffline,
    Log(LogEntry),
    LogsState(bool),
    SystemProxy(Option<String>),
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
    pub group_names: Vec<String>,
    pub node_names: Vec<String>,
    search_keys: HashMap<String, String>,
    pub config: RuntimeConfig,
    pub connections: Vec<Connection>,
    pub connection_view: Vec<usize>,
    pub rates: HashMap<String, u64>,
    previous_connections: HashMap<String, u64>,
    connection_time: Instant,
    pub connections_live: bool,
    pub connection_sort: usize,
    pub version: String,
    pub providers: BTreeMap<String, Provider>,
    pub rule_providers: BTreeMap<String, Provider>,
    pub rules: Vec<Rule>,
    pub rule_view: Vec<usize>,
    pub provider_view: Vec<String>,
    pub provider_mode: bool,
    pub store: ProfileStore,
    pub usage: HashMap<String, Usage>,
    pub group: usize,
    pub node: usize,
    pub profile: usize,
    pub connection: usize,
    pub rule: usize,
    pub provider: usize,
    pub log: usize,
    pub tool: usize,
    pub nodes_focus: bool,
    pub filters: [String; 7],
    pub filtering: bool,
    pub dialog: Option<Dialog>,
    pub detail_scroll: u16,
    pub help: bool,
    pub help_page: usize,
    pub quit: bool,
    pub dirty: bool,
    pub status: String,
    pub online: bool,
    pub system_proxy: Option<String>,
    pub traffic: Option<Traffic>,
    pub history: VecDeque<(u64, u64)>,
    pub totals: (u64, u64),
    pub memory: u64,
    pub delays: HashMap<String, Option<u64>>,
    pub measuring: Option<(usize, usize)>,
    pub sort: Sort,
    pub hide_timeout: bool,
    pub logs: VecDeque<LogEntry>,
    pub log_view: Vec<usize>,
    pub log_level: usize,
    pub logs_paused: bool,
    pub logs_live: bool,
    tx: mpsc::Sender<Update>,
    rx: mpsc::Receiver<Update>,
    refresh: Option<JoinHandle<()>>,
    resources_job: Option<JoinHandle<()>>,
    streams: Vec<JoinHandle<()>>,
    log_job: Option<JoinHandle<()>>,
    delay_job: Option<JoinHandle<()>>,
    usage_job: Option<JoinHandle<()>>,
    command_job: Option<JoinHandle<()>>,
    pub lifecycle_pending: Option<(bool, Instant)>,
    last_click: Option<(u16, u16, Instant)>,
    generation: u64,
    last_refresh: Instant,
    last_resources: Instant,
}
impl App {
    pub fn new(opts: Options) -> Result<Self, reqwest::Error> {
        let client = Client::new(opts.socket.clone())?;
        let (tx, rx) = mpsc::channel(128);
        let page = Page::ALL[opts.settings.default_page.saturating_sub(1).min(6)];
        let sort = match opts.settings.default_sort.as_str() {
            "delay" => Sort::Delay,
            "name" => Sort::Name,
            _ => Sort::Default,
        };
        Ok(Self {
            opts,
            client,
            page,
            proxies: BTreeMap::new(),
            group_names: vec![],
            node_names: vec![],
            search_keys: HashMap::new(),
            config: RuntimeConfig::default(),
            connections: vec![],
            connection_view: vec![],
            rates: HashMap::new(),
            previous_connections: HashMap::new(),
            connection_time: Instant::now(),
            connections_live: false,
            connection_sort: 0,
            version: "--".into(),
            providers: BTreeMap::new(),
            rule_providers: BTreeMap::new(),
            rules: vec![],
            rule_view: vec![],
            provider_view: vec![],
            provider_mode: false,
            store: ProfileStore::default(),
            usage: HashMap::new(),
            group: 0,
            node: 0,
            profile: 0,
            connection: 0,
            rule: 0,
            provider: 0,
            log: 0,
            tool: 0,
            nodes_focus: true,
            filters: Default::default(),
            filtering: false,
            dialog: None,
            detail_scroll: 0,
            help: false,
            help_page: page as usize,
            quit: false,
            dirty: true,
            status: "正在连接内核…".into(),
            online: false,
            system_proxy: None,
            traffic: None,
            history: VecDeque::with_capacity(60),
            totals: (0, 0),
            memory: 0,
            delays: HashMap::new(),
            measuring: None,
            sort,
            hide_timeout: false,
            logs: VecDeque::new(),
            log_view: vec![],
            log_level: 0,
            logs_paused: false,
            logs_live: false,
            tx,
            rx,
            refresh: None,
            resources_job: None,
            streams: vec![],
            log_job: None,
            delay_job: None,
            usage_job: None,
            command_job: None,
            lifecycle_pending: None,
            last_click: None,
            generation: 0,
            last_refresh: Instant::now(),
            last_resources: Instant::now() - Duration::from_secs(31),
        })
    }
    pub fn filter(&self) -> &str {
        &self.filters[self.page as usize]
    }
    pub fn group_name(&self) -> Option<&str> {
        self.group_names.get(self.group).map(String::as_str)
    }
    pub fn current_node(&self) -> Option<&str> {
        self.group_name()
            .and_then(|g| self.proxies.get(g))
            .and_then(|p| p.now.as_deref())
    }
    pub fn delay(&self, node: &str) -> Option<Option<u64>> {
        self.delays.get(node).copied().or_else(|| {
            self.proxies
                .get(node)
                .and_then(|p| p.history.last())
                .map(|d| (d.delay > 0).then_some(d.delay))
        })
    }
    pub fn rebuild_nodes(&mut self) {
        let key = self.filters[Page::Proxies as usize].to_lowercase();
        let mut nodes: Vec<_> = self
            .group_name()
            .and_then(|g| self.proxies.get(g))
            .map(|p| {
                p.all
                    .iter()
                    .filter(|n| {
                        (!self.hide_timeout || self.delay(n) != Some(None))
                            && self
                                .search_keys
                                .get(*n)
                                .is_some_and(|s| search::matches(s, &key))
                    })
                    .cloned()
                    .collect()
            })
            .unwrap_or_default();
        match self.sort {
            Sort::Default => {}
            Sort::Name => nodes.sort_by_cached_key(|n| n.to_lowercase()),
            Sort::Delay => nodes.sort_by_key(|n| match self.delay(n) {
                Some(Some(d)) => (0, d),
                None => (1, 0),
                Some(None) => (2, 0),
            }),
        }
        self.node_names = nodes;
        self.node = self.node.min(self.node_names.len().saturating_sub(1));
    }
    fn rebuild_views(&mut self) {
        let query = self.filter().to_lowercase();
        self.rebuild_nodes();
        self.connection_view = self
            .connections
            .iter()
            .enumerate()
            .filter(|(_, c)| {
                search::matches(
                    &format!(
                        "{} {} {} {} {} {}",
                        c.metadata.host,
                        c.metadata.destination_ip,
                        c.rule,
                        c.rule_payload,
                        c.metadata.process,
                        c.chains.join(" ")
                    )
                    .to_lowercase(),
                    &self.filters[Page::Connections as usize],
                )
            })
            .map(|(i, _)| i)
            .collect();
        self.connection_view.sort_by(|a, b| {
            let (a, b) = (&self.connections[*a], &self.connections[*b]);
            let order = match self.connection_sort {
                0 => self
                    .rates
                    .get(&b.id)
                    .unwrap_or(&0)
                    .cmp(self.rates.get(&a.id).unwrap_or(&0)),
                1 => b
                    .upload
                    .saturating_add(b.download)
                    .cmp(&a.upload.saturating_add(a.download)),
                2 => a.start.cmp(&b.start),
                _ => a.metadata.host.cmp(&b.metadata.host),
            };
            order.then_with(|| a.id.cmp(&b.id))
        });
        self.connection = self
            .connection
            .min(self.connection_view.len().saturating_sub(1));
        self.rule_view = self
            .rules
            .iter()
            .enumerate()
            .filter(|(_, r)| {
                search::matches(
                    &format!("{} {} {}", r.kind, r.payload, r.proxy).to_lowercase(),
                    &self.filters[Page::Rules as usize],
                )
            })
            .map(|(i, _)| i)
            .collect();
        self.rule = self.rule.min(self.rule_view.len().saturating_sub(1));
        self.provider_view = if self.page == Page::Rules {
            &self.rule_providers
        } else {
            &self.providers
        }
        .keys()
        .filter(|n| search::matches(&search::search_key(n), &query))
        .cloned()
        .collect();
        self.provider = self
            .provider
            .min(self.provider_view.len().saturating_sub(1));
        self.rebuild_logs();
    }
    fn rebuild_logs(&mut self) {
        self.log_view = self
            .logs
            .iter()
            .enumerate()
            .filter(|(_, l)| {
                let level = match l.level.as_str() {
                    "debug" => 0,
                    "info" => 1,
                    "warning" | "warn" => 2,
                    "error" => 3,
                    _ => 1,
                };
                level >= self.log_level
                    && search::matches(
                        &l.payload.to_lowercase(),
                        &self.filters[Page::Logs as usize],
                    )
            })
            .map(|(i, _)| i)
            .collect();
        self.log = self.log.min(self.log_view.len().saturating_sub(1));
    }
    pub fn proxy_chain(&self, start: &str) -> String {
        let mut chain = vec![start.to_string()];
        for _ in 0..16 {
            let Some(next) = chain
                .last()
                .and_then(|s| self.proxies.get(s))
                .and_then(|p| p.now.clone())
            else {
                break;
            };
            if chain.contains(&next) {
                chain.push("循环链路".into());
                break;
            }
            chain.push(next);
        }
        chain.join(" → ")
    }
    pub fn chain(&self) -> String {
        match self.config.mode.as_str() {
            "direct" => "DIRECT · 直连模式".into(),
            "global" => self.proxy_chain("GLOBAL"),
            _ => "规则模式：按目标选择链路 · 4 连接查看实际出口".into(),
        }
    }
    pub fn selected_connection(&self) -> Option<&Connection> {
        self.connection_view
            .get(self.connection)
            .and_then(|i| self.connections.get(*i))
    }
    pub fn selected_rule(&self) -> Option<&Rule> {
        self.rule_view
            .get(self.rule)
            .and_then(|i| self.rules.get(*i))
    }
    pub fn start(&mut self) {
        self.reload_profiles();
        self.refresh();
        let client = self.client.clone();
        let tx = self.tx.clone();
        self.streams.push(tokio::spawn(async move {
            loop {
                if let Ok(response) = client.traffic_response().await {
                    let mut stream = response.bytes_stream();
                    let mut buffer = Vec::new();
                    while let Some(Ok(chunk)) = stream.next().await {
                        buffer.extend_from_slice(&chunk);
                        while let Some(end) = buffer.iter().position(|b| *b == b'\n') {
                            if let Ok(value) = serde_json::from_slice::<Traffic>(&buffer[..end]) {
                                if tx.send(Update::Traffic(value)).await.is_err() {
                                    return;
                                }
                            }
                            buffer.drain(..=end);
                        }
                        if buffer.len() > 65536 {
                            break;
                        }
                    }
                }
                if tx.send(Update::TrafficOffline).await.is_err() {
                    return;
                }
                tokio::time::sleep(Duration::from_secs(2)).await;
            }
        }));
        let client = self.client.clone();
        let tx = self.tx.clone();
        self.streams.push(tokio::spawn(async move {
            loop {
                if let Ok(mut stream) = client.connection_stream().await {
                    while let Ok(Some(Ok(message))) =
                        tokio::time::timeout(Duration::from_secs(5), stream.next()).await
                    {
                        if let Ok(text) = message.to_text() {
                            if let Ok(value) = serde_json::from_str::<ConnectionsResponse>(text) {
                                if tx.send(Update::Connections(value)).await.is_err() {
                                    return;
                                }
                            }
                        }
                    }
                }
                if tx.send(Update::ConnectionsOffline).await.is_err() {
                    return;
                }
                tokio::time::sleep(Duration::from_secs(2)).await;
            }
        }));
        if self.page == Page::Logs {
            self.start_logs();
        }
    }
    fn start_logs(&mut self) {
        if self.log_job.is_some() {
            return;
        }
        let client = self.client.clone();
        let tx = self.tx.clone();
        self.log_job = Some(tokio::spawn(async move {
            loop {
                if let Ok(response) = client.logs_response().await {
                    let _ = tx.send(Update::LogsState(true)).await;
                    let mut stream = response.bytes_stream();
                    let mut buffer = Vec::new();
                    while let Some(Ok(chunk)) = stream.next().await {
                        buffer.extend_from_slice(&chunk);
                        while let Some(end) = buffer.iter().position(|b| *b == b'\n') {
                            if let Ok(mut value) =
                                serde_json::from_slice::<LogEntry>(&buffer[..end])
                            {
                                value.payload = search::redact_log(&value.payload);
                                if tx.send(Update::Log(value)).await.is_err() {
                                    return;
                                }
                            }
                            buffer.drain(..=end);
                        }
                        if buffer.len() > 65536 {
                            break;
                        }
                    }
                }
                if tx.send(Update::LogsState(false)).await.is_err() {
                    return;
                }
                tokio::time::sleep(Duration::from_secs(2)).await;
            }
        }));
    }
    fn reload_profiles(&mut self) {
        match std::fs::read_to_string(&self.opts.profiles) {
            Ok(text) => match ProfileStore::from_yaml(&text) {
                Ok(mut store) => {
                    store
                        .items
                        .retain(|i| matches!(i.kind.as_deref(), Some("remote" | "local")));
                    self.store = store;
                    self.profile = self.profile.min(self.store.items.len().saturating_sub(1));
                }
                Err(_) => self.status = "订阅元数据格式无效，未修改文件".into(),
            },
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                self.store = ProfileStore::default()
            }
            Err(_) => self.status = "订阅元数据不可读，未修改文件".into(),
        }
    }
    fn refresh(&mut self) {
        if self.refresh.as_ref().is_some_and(|j| !j.is_finished()) {
            return;
        }
        self.last_refresh = Instant::now();
        let client = self.client.clone();
        let tx = self.tx.clone();
        self.refresh = Some(tokio::spawn(async move {
            let result = tokio::try_join!(client.proxies(), client.configs(), client.version())
                .map(|(proxies, config, version)| Snapshot {
                    proxies,
                    config,
                    version,
                });
            let _ = tx.send(Update::Snapshot(result)).await;
        }));
    }
    fn refresh_resources(&mut self) {
        if self
            .resources_job
            .as_ref()
            .is_some_and(|j| !j.is_finished())
        {
            return;
        }
        self.last_resources = Instant::now();
        let client = self.client.clone();
        let tx = self.tx.clone();
        self.resources_job = Some(tokio::spawn(async move {
            let data = tokio::try_join!(
                client.providers(false),
                client.providers(true),
                client.rules()
            );
            let _ = tx.send(Update::Resources(data)).await;
            // GSettings returns only proxy mode, never URLs, credentials or an environment dump.
            let output = tokio::time::timeout(
                Duration::from_secs(2),
                tokio::process::Command::new("gsettings")
                    .args(["get", "org.gnome.system.proxy", "mode"])
                    .output(),
            )
            .await;
            let mode = match output {
                Ok(Ok(o)) if o.status.success() => {
                    match String::from_utf8_lossy(&o.stdout).trim().trim_matches('\'') {
                        "none" => Some("关闭".into()),
                        "manual" => Some("开启（手动）".into()),
                        "auto" => Some("开启（PAC）".into()),
                        _ => None,
                    }
                }
                _ => None,
            };
            let _ = tx.send(Update::SystemProxy(mode)).await;
        }));
    }
    pub fn tick(&mut self) {
        // Filter a log burst once per frame, not once per incoming record.
        let follow_logs = self.log + 1 >= self.log_view.len();
        let mut logs_changed = false;
        // Cap work per frame even when the log producer is busy.
        for _ in 0..128 {
            let Ok(update) = self.rx.try_recv() else {
                break;
            };
            self.dirty = true;
            match update {
                Update::Snapshot(Ok(s)) => {
                    if !self.online {
                        self.status = "内核已连接 · ? 查看上手指引".into();
                    }
                    self.online = true;
                    if self.lifecycle_pending.is_some_and(|(on, _)| on) {
                        self.lifecycle_pending = None;
                        self.status = "Clash 已就绪".into();
                    }
                    let group = self.group_name().map(str::to_string);
                    let node = self.node_names.get(self.node).cloned();
                    self.proxies = s.proxies;
                    self.config = s.config;
                    self.version = s.version;
                    self.group_names = self
                        .proxies
                        .iter()
                        .filter(|(_, p)| !p.all.is_empty())
                        .map(|(n, _)| n.clone())
                        .collect();
                    if let Some(global) = self.proxies.get("GLOBAL") {
                        self.group_names.sort_by_key(|n| {
                            if n == "GLOBAL" {
                                0
                            } else {
                                global
                                    .all
                                    .iter()
                                    .position(|s| s == n)
                                    .map_or(usize::MAX, |i| i + 1)
                            }
                        });
                    }
                    if let Some(i) = self
                        .group_names
                        .iter()
                        .position(|g| Some(g) == group.as_ref())
                    {
                        self.group = i;
                    }
                    if group.is_none() {
                        self.group = self
                            .group_names
                            .iter()
                            .position(|g| g != "GLOBAL")
                            .unwrap_or(0);
                    }
                    self.group = self.group.min(self.group_names.len().saturating_sub(1));
                    // GLOBAL order mirrors the user's configuration, with unknown groups stable by name.
                    self.search_keys.retain(|n, _| self.proxies.contains_key(n));
                    for n in self
                        .proxies
                        .keys()
                        .chain(self.proxies.values().flat_map(|p| p.all.iter()))
                    {
                        self.search_keys
                            .entry(n.clone())
                            .or_insert_with(|| search::search_key(n));
                    }
                    self.rebuild_views();
                    if let Some(i) = self
                        .node_names
                        .iter()
                        .position(|n| Some(n) == node.as_ref())
                    {
                        self.node = i;
                    }
                }
                Update::Snapshot(Err(e)) => {
                    self.online = false;
                    self.traffic = None;
                    self.connections_live = false;
                    self.status = if self.lifecycle_pending.is_some() {
                        self.launch_progress()
                    } else if matches!(e, ApiError::Transport) {
                        "Clash 未运行 · s 启动".into()
                    } else {
                        e.to_string()
                    };
                    if self.lifecycle_pending.is_some_and(|(on, _)| !on)
                        && !self.opts.socket.exists()
                    {
                        self.lifecycle_pending = None;
                        self.status = "Clash 已关闭 · s 启动".into();
                    }
                }
                Update::Resources(Ok((providers, rules, list))) => {
                    self.providers = providers;
                    self.rule_providers = rules;
                    self.rules = list;
                    self.rebuild_views();
                }
                Update::Resources(Err(e)) => self.status = format!("规则/provider 刷新失败：{e}"),
                Update::Connections(s) => {
                    let selected = self.selected_connection().map(|c| c.id.clone());
                    let elapsed = self.connection_time.elapsed().as_secs_f64().max(0.001);
                    self.connection_time = Instant::now();
                    self.rates.clear();
                    for c in &s.connections {
                        let total = c.upload.saturating_add(c.download);
                        if let Some(old) = self.previous_connections.get(&c.id) {
                            self.rates.insert(
                                c.id.clone(),
                                (total.saturating_sub(*old) as f64 / elapsed) as u64,
                            );
                        }
                    }
                    self.previous_connections = s
                        .connections
                        .iter()
                        .map(|c| (c.id.clone(), c.upload.saturating_add(c.download)))
                        .collect();
                    self.connections = s.connections;
                    self.memory = s.memory;
                    self.totals = (s.upload_total, s.download_total);
                    self.connections_live = true;
                    self.rebuild_views();
                    if let Some(i) = self
                        .connection_view
                        .iter()
                        .position(|i| Some(&self.connections[*i].id) == selected.as_ref())
                    {
                        self.connection = i;
                    }
                }
                Update::ConnectionsOffline => {
                    self.connections_live = false;
                    self.previous_connections.clear();
                    self.rates.clear();
                }
                Update::Traffic(value) => {
                    self.totals = (value.up_total, value.down_total);
                    if self.history.len() == 60 {
                        self.history.pop_front();
                    }
                    self.history.push_back((value.up, value.down));
                    self.traffic = Some(value);
                }
                Update::TrafficOffline => {
                    self.traffic = None;
                    self.history.clear();
                }
                Update::Log(value) if !self.logs_paused => {
                    if self.logs.len() == 2000 {
                        self.logs.pop_front();
                        self.log = self.log.saturating_sub(1);
                    }
                    self.logs.push_back(value);
                    logs_changed = true;
                }
                Update::LogsState(on) => self.logs_live = on,
                Update::SystemProxy(mode) => self.system_proxy = mode,
                Update::Message(s) => {
                    self.status = s;
                    self.last_refresh = Instant::now() - Duration::from_secs(3);
                    self.last_resources = Instant::now() - Duration::from_secs(31);
                }
                Update::Delay(g, name, delay) if g == self.generation => {
                    let selected = self.node_names.get(self.node).cloned();
                    self.delays.insert(name, delay.filter(|d| *d > 0));
                    if let Some((n, _)) = self.measuring.as_mut() {
                        *n += 1;
                    }
                    self.rebuild_nodes();
                    if let Some(i) = self
                        .node_names
                        .iter()
                        .position(|n| Some(n) == selected.as_ref())
                    {
                        self.node = i;
                    }
                }
                Update::DelayDone(g) if g == self.generation => {
                    self.measuring = None;
                    if !self.status.contains("失败") {
                        self.status = "测速完成 · 延迟仅代表此测试目标".into();
                    }
                }
                Update::Usage(uid, value) => match value {
                    Ok(u) => {
                        self.usage.insert(uid, u);
                        self.status = "用量已刷新（仅内存）".into();
                    }
                    Err(e) => self.status = e,
                },
                _ => {}
            }
        }
        if logs_changed {
            self.rebuild_logs();
            if follow_logs {
                self.log = self.log_view.len().saturating_sub(1);
            }
        }
        if let Some((_, time)) = self.lifecycle_pending {
            if time.elapsed() > Duration::from_secs(30) {
                self.status = format!(
                    "启动/关闭等待超时：{}；请在 Verge 检查 helper 与内核",
                    self.launch_progress()
                );
                self.lifecycle_pending = None;
                self.dirty = true;
            }
        }
        if self.last_refresh.elapsed() >= Duration::from_secs(2) {
            self.reload_profiles();
            self.refresh();
        }
        if self.online && self.last_resources.elapsed() >= Duration::from_secs(30) {
            self.refresh_resources();
        }
    }
    pub fn launch_progress(&self) -> String {
        match self.lifecycle_pending {
            Some((false, _)) => "正在等待 Verge 清理 TUN 与内核…".into(),
            Some((true, _)) if self.opts.socket.exists() => {
                "内核 socket 已出现 → 等待 API 就绪…".into()
            }
            Some((true, _)) => "启动请求已发出 → 等待 helper / 内核 socket…".into(),
            None => "Clash 未运行 · s 启动".into(),
        }
    }
    fn command<F>(&mut self, future: F)
    where
        F: std::future::Future<Output = Result<(), ApiError>> + Send + 'static,
    {
        if self.command_job.as_ref().is_some_and(|j| !j.is_finished()) {
            self.status = "操作正在进行，请稍候".into();
            return;
        }
        self.status = "正在执行…".into();
        let tx = self.tx.clone();
        self.command_job = Some(tokio::spawn(async move {
            let message = match future.await {
                Ok(()) => "操作完成".into(),
                Err(e) => e.to_string(),
            };
            let _ = tx.send(Update::Message(message)).await;
        }));
    }
    fn cancel_measure(&mut self) {
        if let Some(job) = self.delay_job.take() {
            job.abort();
        }
        self.generation += 1;
        self.measuring = None;
    }
    fn measure(&mut self, kind: usize) {
        self.cancel_measure();
        let nodes = match kind {
            0 => self
                .node_names
                .get(self.node)
                .cloned()
                .into_iter()
                .collect::<Vec<_>>(),
            1 => self
                .group_name()
                .and_then(|g| self.proxies.get(g))
                .map(|p| p.all.clone())
                .unwrap_or_default(),
            _ => self.node_names.clone(),
        };
        if nodes.is_empty() {
            return;
        }
        let group = self.group_name().unwrap_or_default().to_string();
        let generation = self.generation;
        let client = self.client.clone();
        let tx = self.tx.clone();
        let url = self.opts.settings.test_url.clone();
        let timeout = self.opts.settings.timeout_ms;
        let concurrency = self.opts.settings.concurrency;
        self.measuring = Some((0, nodes.len()));
        self.status = if kind == 1 {
            "整组测速中（并发由内核管理；自动组可能重选出口）".into()
        } else {
            format!("测速中 · 最多 {concurrency} 并发 · Esc 取消本地队列")
        };
        self.delay_job = Some(tokio::spawn(async move {
            if kind == 1 {
                match client.group_delay(&group, &url, timeout).await {
                    Ok(result) => {
                        for name in nodes {
                            let d = result.get(&name).copied();
                            if tx.send(Update::Delay(generation, name, d)).await.is_err() {
                                return;
                            }
                        }
                    }
                    Err(e) => {
                        let _ = tx.send(Update::Message(format!("整组测速失败：{e}"))).await;
                    }
                }
            } else {
                let mut queue = nodes.into_iter();
                let mut jobs = JoinSet::new();
                loop {
                    while jobs.len() < concurrency {
                        let Some(name) = queue.next() else {
                            break;
                        };
                        let client = client.clone();
                        let url = url.clone();
                        jobs.spawn(async move {
                            let delay = client.delay(&name, &url, timeout).await.ok();
                            (name, delay)
                        });
                    }
                    match jobs.join_next().await {
                        Some(Ok((name, d))) => {
                            if tx.send(Update::Delay(generation, name, d)).await.is_err() {
                                return;
                            }
                        }
                        Some(Err(_)) => {}
                        None => break,
                    }
                }
            }
            let _ = tx.send(Update::DelayDone(generation)).await;
        }));
    }
    fn refresh_usage(&mut self) {
        if self.usage_job.as_ref().is_some_and(|j| !j.is_finished()) {
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
            self.status = "没有代理端口；可用 --usage-proxy 指定".into();
            return;
        };
        self.status = "正在经代理读取用量响应头…".into();
        let tx = self.tx.clone();
        self.usage_job = Some(tokio::spawn(async move {
            let result = usage_request(&url, &proxy).await;
            let _ = tx.send(Update::Usage(uid, result)).await;
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
                if !self.online {
                    self.lifecycle_pending = Some((true, Instant::now()));
                }
                self.status = "已交给 Verge；完成后回到 TUI，将自动刷新订阅".into();
            }
            Err(e) => self.status = e,
        }
    }
    fn confirm(&mut self, action: Action, body: String) {
        self.dialog = Some(Dialog::Confirm { action, body });
    }
    fn execute(&mut self, action: Action) {
        let client = self.client.clone();
        match action {
            Action::Stop => {
                if self.opts.no_verge {
                    self.status = "隔离模式：Verge 生命周期已禁用".into();
                    return;
                }
                let lifecycle = self.opts.lifecycle.clone();
                let tx = self.tx.clone();
                self.lifecycle_pending = Some((false, Instant::now()));
                self.streams.retain(|job| !job.is_finished());
                self.streams.push(tokio::spawn(async move {
                    let result = tokio::task::spawn_blocking(move || lifecycle.stop()).await;
                    let message = match result {
                        Ok(Ok(_)) => "已请求 Verge 退出，等待清理…".into(),
                        Ok(Err(e)) => e,
                        Err(_) => "关闭任务失败".into(),
                    };
                    let _ = tx.send(Update::Message(message)).await;
                }));
            }
            Action::Close(ids) => self.command(async move {
                for id in ids {
                    client.close(&id).await?;
                }
                Ok(())
            }),
            Action::CloseAll => self.command(async move { client.close_all().await }),
            Action::Tool(i) => self.command(async move { client.tool(i).await }),
        }
    }
    pub fn key(&mut self, key: KeyEvent) {
        self.dirty = true;
        if key.code == KeyCode::Char('c') && key.modifiers.contains(KeyModifiers::CONTROL) {
            self.quit = true;
            return;
        }
        if let Some(mut dialog) = self.dialog.take() {
            match &mut dialog {
                Dialog::Confirm { action, .. } => match key.code {
                    KeyCode::Enter | KeyCode::Char('y') => {
                        self.execute(action.clone());
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
                        if let Some(url) = reqwest::Url::parse(url)
                            .ok()
                            .filter(|u| matches!(u.scheme(), "http" | "https"))
                        {
                            if !name.is_empty() {
                                self.dialog = Some(Dialog::Verge {
                                    reason: "此版本无法可靠传递名称；将打开 Verge 完成命名导入。",
                                });
                            } else {
                                self.open_verge(Some(profiles::verge_import_link(&url)));
                            }
                            return;
                        } else {
                            self.status = "请输入有效 http(s) 订阅 URL（内容隐藏）".into();
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
                Dialog::Detail(text) => match key.code {
                    KeyCode::Esc | KeyCode::Enter | KeyCode::Char('q') => return,
                    KeyCode::Down | KeyCode::Char('j') => {
                        self.detail_scroll = self
                            .detail_scroll
                            .saturating_add(1)
                            .min(text.lines().count().saturating_sub(1) as u16)
                    }
                    KeyCode::Up | KeyCode::Char('k') => {
                        self.detail_scroll = self.detail_scroll.saturating_sub(1)
                    }
                    KeyCode::PageDown => {
                        self.detail_scroll = self
                            .detail_scroll
                            .saturating_add(10)
                            .min(text.lines().count().saturating_sub(1) as u16)
                    }
                    KeyCode::PageUp => self.detail_scroll = self.detail_scroll.saturating_sub(10),
                    KeyCode::Char('g') => self.detail_scroll = 0,
                    _ => {}
                },
            }
            self.dialog = Some(dialog);
            return;
        }
        if self.help {
            match key.code {
                KeyCode::Esc | KeyCode::Char('?' | 'q') => self.help = false,
                KeyCode::Tab | KeyCode::Right | KeyCode::Char('l') => {
                    self.help_page = (self.help_page + 1) % 7
                }
                KeyCode::Left | KeyCode::Char('h') => self.help_page = (self.help_page + 6) % 7,
                KeyCode::Char(c @ '1'..='7') => self.help_page = c as usize - '1' as usize,
                _ => {}
            }
            return;
        }
        if self.filtering {
            let filter = &mut self.filters[self.page as usize];
            match key.code {
                KeyCode::Esc => {
                    self.filtering = false;
                    filter.clear();
                }
                KeyCode::Enter => self.filtering = false,
                KeyCode::Backspace => {
                    filter.pop();
                }
                KeyCode::Char(ch) if !ch.is_control() => filter.push(ch),
                _ => {}
            }
            self.node = 0;
            self.connection = 0;
            self.rule = 0;
            self.provider = 0;
            self.log = 0;
            self.rebuild_views();
            return;
        }
        match key.code {
            KeyCode::Char('q') => self.quit = true,
            KeyCode::Char('?') => {
                self.help = true;
                self.help_page = self.page as usize;
            }
            KeyCode::Char(c @ '1'..='7') => {
                self.page = Page::ALL[c as usize - '1' as usize];
                self.provider_mode = false;
                self.rebuild_views();
                if self.page == Page::Logs {
                    self.start_logs();
                }
                self.reload_profiles();
            }
            KeyCode::Char('s') if !self.online && self.lifecycle_pending.is_none() => {
                self.open_verge(None)
            }
            KeyCode::Char('X') if self.online && self.lifecycle_pending.is_none() => self.confirm(
                Action::Stop,
                "退出本用户的 Verge GUI，由 Verge 清理系统代理、TUN 和内核。".into(),
            ),
            KeyCode::Char('r') => {
                self.reload_profiles();
                self.refresh();
                self.last_resources = Instant::now() - Duration::from_secs(31);
            }
            KeyCode::Char('i')
                if self.page == Page::Profiles || (!self.online && self.page == Page::Overview) =>
            {
                self.dialog = Some(Dialog::Import {
                    url: String::new(),
                    name: String::new(),
                    field: false,
                })
            }
            KeyCode::Char('o') => {
                self.dialog = Some(Dialog::Verge {
                    reason:
                        "将打开 Verge 设置；TUN 与系统代理由 Verge 管理。完成后返回 TUI 自动刷新。",
                })
            }
            _ if !self.online && self.page != Page::Profiles => {}
            KeyCode::Char('/')
                if matches!(
                    self.page,
                    Page::Proxies | Page::Connections | Page::Rules | Page::Logs
                ) =>
            {
                self.filtering = true
            }
            KeyCode::Esc => {
                self.cancel_measure();
                self.filters[self.page as usize].clear();
                self.rebuild_views();
            }
            KeyCode::Char('j') | KeyCode::Down => self.move_selection(1, false),
            KeyCode::Char('k') | KeyCode::Up => self.move_selection(-1, false),
            KeyCode::PageDown => self.move_selection(10, false),
            KeyCode::PageUp => self.move_selection(-10, false),
            KeyCode::Char('g') => self.move_selection(-1, true),
            KeyCode::Char('G') => self.move_selection(1, true),
            KeyCode::Tab | KeyCode::BackTab if self.page == Page::Proxies => {
                self.nodes_focus = !self.nodes_focus
            }
            KeyCode::Char('h') | KeyCode::Left if self.page == Page::Proxies => {
                self.nodes_focus = false
            }
            KeyCode::Char('l') | KeyCode::Right if self.page == Page::Proxies => {
                self.nodes_focus = true
            }
            KeyCode::Char('p') if matches!(self.page, Page::Proxies | Page::Rules) => {
                self.provider_mode = !self.provider_mode;
                self.provider = 0;
                self.rebuild_views();
            }
            KeyCode::Char('S') if self.page == Page::Proxies && !self.provider_mode => {
                self.sort = match self.sort {
                    Sort::Default => Sort::Delay,
                    Sort::Delay => Sort::Name,
                    Sort::Name => Sort::Default,
                };
                self.rebuild_nodes();
            }
            KeyCode::Char('S') if self.page == Page::Connections => {
                self.connection_sort = (self.connection_sort + 1) % 4;
                self.rebuild_views();
            }
            KeyCode::Char('H') if self.page == Page::Proxies => {
                self.hide_timeout = !self.hide_timeout;
                self.rebuild_nodes();
            }
            KeyCode::Char('c') if self.page == Page::Proxies => {
                if let Some(i) = self
                    .current_node()
                    .and_then(|n| self.node_names.iter().position(|s| s == n))
                {
                    self.node = i;
                    self.nodes_focus = true;
                } else {
                    self.status = "当前节点被过滤；Esc 清除或 H 显示超时节点".into();
                }
            }
            KeyCode::Char('t') if self.provider_mode && self.page == Page::Proxies => {
                if let Some(name) = self.provider_view.get(self.provider).cloned() {
                    let client = self.client.clone();
                    self.command(async move { client.healthcheck(&name).await });
                }
            }
            KeyCode::Char('u') if self.provider_mode => {
                if let Some(name) = self.provider_view.get(self.provider).cloned() {
                    let rules = self.page == Page::Rules;
                    let provider = if rules {
                        self.rule_providers.get(&name)
                    } else {
                        self.providers.get(&name)
                    };
                    if provider
                        .is_some_and(|p| matches!(p.vehicle_type.as_str(), "Compatible" | "Inline"))
                    {
                        self.dialog = Some(Dialog::Verge {
                            reason: "此源嵌入当前配置，没有独立远程地址；请在 Verge 更新所属订阅。",
                        });
                        return;
                    }
                    let client = self.client.clone();
                    self.command(async move { client.update_provider(&name, rules).await });
                }
            }
            KeyCode::Char('t') if self.page == Page::Proxies => self.measure(0),
            KeyCode::Char('T') if self.page == Page::Proxies => self.measure(1),
            KeyCode::Char('b') if self.page == Page::Proxies => self.measure(2),
            KeyCode::Char('m') => {
                let mode = match self.config.mode.as_str() {
                    "rule" => "global",
                    "global" => "direct",
                    _ => "rule",
                };
                let client = self.client.clone();
                self.command(async move { client.set_mode(mode).await });
            }
            KeyCode::Enter if self.page == Page::Proxies && !self.provider_mode => {
                if !self.nodes_focus {
                    self.nodes_focus = true;
                    return;
                }
                if let Some(group) = self.group_name() {
                    let kind = self
                        .proxies
                        .get(group)
                        .map(|p| p.kind.as_str())
                        .unwrap_or_default();
                    if !matches!(kind, "Selector" | "URLTest" | "Fallback") {
                        self.status = "此组由内核按策略分配，不能手动选节点".into();
                        return;
                    }
                    if let Some(node) = self.node_names.get(self.node).cloned() {
                        let group = group.to_string();
                        let client = self.client.clone();
                        self.command(async move { client.select(&group, &node).await });
                    }
                }
            }
            KeyCode::Char('v') if self.page == Page::Proxies && !self.provider_mode => {
                self.detail_scroll = 0;
                self.dialog = Some(Dialog::Detail(format!("代理组：{}\n类型：{}\n当前：{}\n所选节点：{}\n提示：自动/故障转移组可手动指定；T 测速会恢复自动选择。", self.group_name().unwrap_or("--"), self.group_name().and_then(|g| self.proxies.get(g)).map(|p| p.kind.as_str()).unwrap_or("--"), self.current_node().unwrap_or("按策略分配"), self.node_names.get(self.node).map(String::as_str).unwrap_or("--"))));
            }
            KeyCode::Enter if self.provider_mode => {
                if let Some(name) = self.provider_view.get(self.provider) {
                    if let Some(p) = if self.page == Page::Rules {
                        self.rule_providers.get(name)
                    } else {
                        self.providers.get(name)
                    } {
                        self.detail_scroll = 0;
                        self.dialog = Some(Dialog::Detail(format!("源：{name}\n类型：{} / {}\n更新：{}\n节点：{}\n规则：{}\n注意：Compatible 源来自配置，不能远程更新。", p.vehicle_type, p.kind, p.updated_at, p.proxies.len(), p.rule_count)));
                    }
                }
            }
            KeyCode::Char('f') if self.page == Page::Profiles => self.refresh_usage(),
            KeyCode::Char('u') | KeyCode::Enter if self.page == Page::Profiles => {
                self.dialog = Some(Dialog::Verge {
                    reason: "Verge 2.4.7 无外部订阅更新/切换接口；将打开 Verge，返回后自动刷新。",
                })
            }
            KeyCode::Char('x') if self.page == Page::Connections => {
                if let Some(c) = self.selected_connection() {
                    self.confirm(
                        Action::Close(vec![c.id.clone()]),
                        format!(
                            "关闭所选连接 {}:{}？",
                            c.metadata.host, c.metadata.destination_port
                        ),
                    );
                }
            }
            KeyCode::Char('d') if self.page == Page::Connections => {
                let ids = self
                    .connection_view
                    .iter()
                    .map(|i| self.connections[*i].id.clone())
                    .collect::<Vec<_>>();
                if !ids.is_empty() {
                    self.confirm(
                        Action::Close(ids.clone()),
                        format!(
                            "关闭当前过滤结果中的 {} 条连接？确认后仅操作此快照。",
                            ids.len()
                        ),
                    );
                }
            }
            KeyCode::Char('D') if self.page == Page::Connections => self.confirm(
                Action::CloseAll,
                "关闭全部连接？包括确认期间新建的连接。".into(),
            ),
            KeyCode::Enter if self.page == Page::Connections => {
                if let Some(c) = self.selected_connection().cloned() {
                    self.detail_scroll = 0;
                    self.dialog = Some(Dialog::Detail(format!("目标：{}:{}\nIP：{}\n源：{}:{} / {}\n进程：{}\n路径：{}\n规则：{} / {}\n链路：{}\n开始：{}\n上传：{}\n下载：{}\nID：{}", c.metadata.host, c.metadata.destination_port, c.metadata.destination_ip, c.metadata.source_ip, c.metadata.source_port, c.metadata.network, c.metadata.process, c.metadata.process_path, c.rule, c.rule_payload, c.chains.join(" → "), c.start, crate::theme::bytes(c.upload), crate::theme::bytes(c.download), c.id)));
                }
            }
            KeyCode::Enter if self.page == Page::Rules && !self.provider_mode => {
                if let Some(r) = self.selected_rule().cloned() {
                    self.detail_scroll = 0;
                    self.dialog = Some(Dialog::Detail(format!(
                        "规则：{}\n内容：{}\n策略：{}\n命中：{}\n上次命中：{}",
                        r.kind,
                        r.payload,
                        r.proxy,
                        r.extra
                            .as_ref()
                            .map(|e| e.hit_count.to_string())
                            .unwrap_or_else(|| "内核未提供计数".into()),
                        r.extra
                            .as_ref()
                            .map(|e| e.hit_at.as_str())
                            .unwrap_or("未知")
                    )));
                }
            }
            KeyCode::Char(' ') if self.page == Page::Logs => self.logs_paused = !self.logs_paused,
            KeyCode::Char('L') if self.page == Page::Logs => {
                self.log_level = (self.log_level + 1) % 4;
                self.rebuild_logs();
            }
            KeyCode::Enter if self.page == Page::Tools => {
                let body = match self.tool { 0 => "清空 fake-ip 缓存？已建立的映射会被丢弃。", 1 => "清空 DNS 缓存？之后的解析会重新查询。", _ => "更新 GeoIP/GeoSite 数据库？内核将联网下载并重载规则；Nix store 内资源可能只读。" };
                self.confirm(Action::Tool(self.tool), body.into());
            }
            _ => {}
        }
    }
    fn move_selection(&mut self, delta: isize, edge: bool) {
        let (index, len) = if self.provider_mode && matches!(self.page, Page::Proxies | Page::Rules)
        {
            (&mut self.provider, self.provider_view.len())
        } else {
            match self.page {
                Page::Proxies if !self.nodes_focus => {
                    self.node = 0;
                    (&mut self.group, self.group_names.len())
                }
                Page::Proxies => (&mut self.node, self.node_names.len()),
                Page::Profiles => (&mut self.profile, self.store.items.len()),
                Page::Connections => (&mut self.connection, self.connection_view.len()),
                Page::Rules => (&mut self.rule, self.rule_view.len()),
                Page::Logs => (&mut self.log, self.log_view.len()),
                Page::Tools => (&mut self.tool, 3),
                Page::Overview => return,
            }
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
        if self.page == Page::Proxies && !self.nodes_focus {
            self.rebuild_nodes();
        }
    }
    pub fn mouse(&mut self, event: crossterm::event::MouseEvent, size: ratatui::layout::Size) {
        use crossterm::event::{MouseButton, MouseEventKind};
        self.dirty = true;
        if self.help {
            if matches!(
                event.kind,
                MouseEventKind::ScrollDown | MouseEventKind::ScrollUp
            ) {
                self.help_page = (self.help_page
                    + if event.kind == MouseEventKind::ScrollDown {
                        1
                    } else {
                        6
                    })
                    % 7;
            }
            return;
        }
        if self.dialog.is_some() {
            match event.kind {
                MouseEventKind::ScrollDown => {
                    self.detail_scroll = self.detail_scroll.saturating_add(1)
                }
                MouseEventKind::ScrollUp => {
                    self.detail_scroll = self.detail_scroll.saturating_sub(1)
                }
                MouseEventKind::Down(MouseButton::Left) => {
                    if let Some(dialog) = self.dialog.as_ref() {
                        if let Some(code) =
                            crate::ui::dialog_click(size, dialog, event.column, event.row)
                        {
                            self.key(KeyEvent::new(code, KeyModifiers::NONE));
                        }
                    }
                }
                _ => {}
            }
            return;
        }
        match event.kind {
            MouseEventKind::ScrollDown => self.move_selection(3, false),
            MouseEventKind::ScrollUp => self.move_selection(-3, false),
            MouseEventKind::Down(MouseButton::Left) => {
                if event.row == 1 {
                    if let Some(page) = crate::ui::tab_at(event.column) {
                        self.key(KeyEvent::new(KeyCode::Char(page), KeyModifiers::NONE));
                    }
                    return;
                }
                if event.row < 4 || event.row >= size.height.saturating_sub(2) {
                    return;
                }
                let activate = self.last_click.is_some_and(|(x, y, time)| {
                    x == event.column
                        && y == event.row
                        && time.elapsed() < Duration::from_millis(400)
                });
                self.last_click = Some((event.column, event.row, Instant::now()));
                let y = event.row as usize - 4;
                let height = size.height.saturating_sub(7) as usize;
                if self.page == Page::Proxies && !self.provider_mode {
                    self.nodes_focus = event.column >= size.width * 32 / 100;
                }
                let (index, len, row_height) = if self.provider_mode
                    && matches!(self.page, Page::Proxies | Page::Rules)
                {
                    (&mut self.provider, self.provider_view.len(), 2)
                } else {
                    match self.page {
                        Page::Proxies if !self.nodes_focus => {
                            (&mut self.group, self.group_names.len(), 2)
                        }
                        Page::Proxies => (&mut self.node, self.node_names.len(), 1),
                        Page::Profiles => (&mut self.profile, self.store.items.len(), 5),
                        Page::Connections => (&mut self.connection, self.connection_view.len(), 2),
                        Page::Rules => (&mut self.rule, self.rule_view.len(), 2),
                        Page::Logs => (&mut self.log, self.log_view.len(), 1),
                        Page::Tools => (&mut self.tool, 3, 3),
                        _ => return,
                    }
                };
                let offset = visible_start(*index, len, height / row_height);
                *index = (offset + y / row_height).min(len.saturating_sub(1));
                if self.page == Page::Proxies && !self.nodes_focus {
                    self.node = 0;
                    self.rebuild_nodes();
                }
                if activate {
                    self.key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE));
                }
            }
            _ => {}
        }
    }
    pub fn stop(&mut self) {
        self.cancel_measure();
        for job in [
            &mut self.refresh,
            &mut self.resources_job,
            &mut self.log_job,
            &mut self.usage_job,
            &mut self.command_job,
        ]
        .into_iter()
        .filter_map(Option::take)
        {
            job.abort();
        }
        for job in self.streams.drain(..) {
            job.abort();
        }
    }
}
pub fn visible_start(selected: usize, len: usize, visible: usize) -> usize {
    selected
        .saturating_add(1)
        .saturating_sub(visible.max(1))
        .min(len.saturating_sub(visible.max(1)))
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
    pub fn fixture_app() -> App {
        let mut app = App::new(Options {
            socket: "/nonexistent.sock".into(),
            profiles: "/nonexistent.yaml".into(),
            settings: Settings::default(),
            usage_proxy: None,
            no_verge: true,
            lifecycle: Default::default(),
        })
        .unwrap();
        let value: serde_json::Value =
            serde_json::from_str(include_str!("../tests/fixtures/controller.json")).unwrap();
        app.tx
            .try_send(Update::Snapshot(Ok(Snapshot {
                proxies: serde_json::from_value(value["proxies"].clone()).unwrap(),
                config: serde_json::from_value(value["configs"].clone()).unwrap(),
                version: "1.19.24".into(),
            })))
            .unwrap();
        app.tx
            .try_send(Update::Connections(
                serde_json::from_value(value["connections"].clone()).unwrap(),
            ))
            .unwrap();
        app.tick();
        app
    }
    #[tokio::test]
    async fn replay_sorts_filters_and_cancels() {
        let mut app = fixture_app();
        app.page = Page::Proxies;
        app.group = app
            .group_names
            .iter()
            .position(|g| g == "手动选择")
            .unwrap();
        app.rebuild_nodes();
        let original = app.node_names.clone();
        app.sort = Sort::Delay;
        app.rebuild_nodes();
        assert_eq!(app.node_names.last().unwrap(), "超时节点");
        app.hide_timeout = true;
        app.rebuild_nodes();
        assert_eq!(app.node_names.len(), 2);
        app.filters[1] = "xggs".into();
        app.rebuild_nodes();
        assert_eq!(app.node_names, vec![original[0].clone()]);
        app.filters[1].clear();
        app.hide_timeout = false;
        app.sort = Sort::Default;
        app.rebuild_nodes();
        assert_eq!(app.node_names, original);
        app.sort = Sort::Name;
        app.rebuild_nodes();
        assert!(app
            .node_names
            .windows(2)
            .all(|w| w[0].to_lowercase() <= w[1].to_lowercase()));
        let old = app.generation;
        app.cancel_measure();
        app.tx
            .try_send(Update::Delay(old, "stale".into(), Some(9)))
            .unwrap();
        app.tick();
        assert!(!app.delays.contains_key("stale"));
        assert!(app.chain().contains("GLOBAL → 手动选择 → 🇭🇰"));
    }
    #[tokio::test]
    async fn connection_identity_and_confirmed_snapshot_are_stable() {
        let mut app = fixture_app();
        app.page = Page::Connections;
        app.connection_sort = 1;
        app.rebuild_views();
        assert_eq!(app.selected_connection().unwrap().id, "b");
        app.key(KeyEvent::new(KeyCode::Char('x'), KeyModifiers::NONE));
        assert!(
            matches!(&app.dialog, Some(Dialog::Confirm { action: Action::Close(ids), .. }) if ids == &vec!["b".to_string()])
        );
        app.key(KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE));
        assert!(app.command_job.is_none());
        app.filters[3] = "firefox".into();
        app.rebuild_views();
        assert_eq!(app.connection_view.len(), 1);
        app.key(KeyEvent::new(KeyCode::Char('d'), KeyModifiers::NONE));
        assert!(
            matches!(&app.dialog, Some(Dialog::Confirm { action: Action::Close(ids), .. }) if ids == &vec!["b".to_string()])
        );
        let mut snapshot = ConnectionsResponse {
            connections: app.connections.clone(),
            ..Default::default()
        };
        snapshot.connections.reverse();
        app.tx.try_send(Update::Connections(snapshot)).unwrap();
        app.tick();
        assert_eq!(app.selected_connection().unwrap().id, "b");
    }
    #[tokio::test]
    async fn large_fixture_all_pages_and_narrow_layout() {
        let mut app = fixture_app();
        for n in 0..360 {
            let name = format!("🇭🇰 香港 合成节点 {n:03} 👩‍💻");
            app.search_keys
                .insert(name.clone(), search::search_key(&name));
            app.proxies.insert(
                name.clone(),
                Proxy {
                    name: name.clone(),
                    kind: "Http".into(),
                    ..Default::default()
                },
            );
            app.proxies.get_mut("手动选择").unwrap().all.push(name);
        }
        let source = app.connections[0].clone();
        app.connections = (0..1200)
            .map(|i| Connection {
                id: format!("c{i}"),
                ..source.clone()
            })
            .collect();
        for width in [44, 90, 109, 160] {
            let mut terminal =
                ratatui::Terminal::new(ratatui::backend::TestBackend::new(width, 34)).unwrap();
            for page in Page::ALL {
                app.page = page;
                app.rebuild_views();
                terminal.draw(|f| crate::ui::draw(f, &app)).unwrap();
            }
        }
        assert_eq!(app.connection_view.len(), 1200);
        app.history = (0..60).map(|i| (i, i * 2)).collect();
        app.tx
            .try_send(Update::Traffic(Traffic::default()))
            .unwrap();
        app.tick();
        assert_eq!(app.history.len(), 60);
    }
    #[tokio::test]
    async fn log_buffer_is_bounded_and_pause_discards() {
        let mut app = fixture_app();
        for i in 0..2100 {
            app.tx
                .try_send(Update::Log(LogEntry {
                    level: "info".into(),
                    payload: format!("message {i}"),
                }))
                .unwrap();
            app.tick();
        }
        assert_eq!(app.logs.len(), 2000);
        assert_eq!(app.log, 1999);
        app.logs_paused = true;
        app.tx.try_send(Update::Log(LogEntry::default())).unwrap();
        app.tick();
        assert_eq!(app.logs.len(), 2000);
        app.log_level = 3;
        app.rebuild_logs();
        assert!(app.log_view.is_empty());
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
