use crate::api::{
    drain_log_frames, drain_raw_log_lines, Container, Disk, Engine, Image, Info, StatView, Volume,
};
use crate::cleanup::{self, Entry, Flow, Kind, Report};
use crate::vm;
use crossterm::event::{KeyCode, KeyEvent, MouseEvent, MouseEventKind};
use futures_util::StreamExt;
use mayon_ui::{
    self as ui,
    input::TextInput,
    search::{Matcher, SearchCache},
    theme::*,
};
use ratatui::{
    layout::Constraint,
    text::Line,
    widgets::{Paragraph, Wrap},
    Frame,
};
use std::{
    collections::{HashMap, HashSet},
    process::Command,
    time::{Duration, Instant},
};
use tokio::{sync::mpsc, task::JoinHandle};
#[derive(Clone, Copy, PartialEq)]
enum Page {
    Containers,
    Images,
    Volumes,
    Overview,
    Cleanup,
}
#[derive(Clone)]
enum Confirm {
    StopDaemon,
    ProjectRestart(String, Vec<String>),
}
enum Update {
    Data(u64, Result<Data, String>),
    Stats(u64, String, Result<StatView, String>),
    Message(String),
    Cleaned(Report),
    Vm(vm::Inventory),
    Log(u64, String),
    LogEnded(u64, String),
}
struct Data {
    containers: Vec<Container>,
    images: Vec<Image>,
    volumes: Vec<Volume>,
    info: Info,
    disk: Disk,
}
struct ApiJobs {
    handles: Vec<JoinHandle<()>>,
    stats: tokio::task::JoinSet<()>,
}
impl ApiJobs {
    async fn stop_and_join(mut self) {
        for handle in self.handles.drain(..) {
            let _ = handle.await;
        }
        self.stats.abort_all();
        while self.stats.join_next().await.is_some() {}
    }
}
pub struct App {
    engine: Engine,
    page: Page,
    pub quit: bool,
    selected: usize,
    filter: TextInput,
    filter_before: TextInput,
    search_cache: SearchCache,
    filtering: bool,
    sort: usize,
    containers: Vec<Container>,
    images: Vec<Image>,
    volumes: Vec<Volume>,
    info: Info,
    disk: Disk,
    stats: HashMap<String, StatView>,
    stats_pending: HashSet<String>,
    stats_jobs: tokio::task::JoinSet<()>,
    api_epoch: u64,
    message: String,
    message_until: Option<Instant>,
    online: bool,
    load_error: Option<String>,
    confirm: Option<Confirm>,
    help: bool,
    details: bool,
    logs: Option<String>,
    log_lines: Vec<String>,
    log_filter: TextInput,
    log_scroll: usize,
    log_follow: bool,
    log_job: Option<JoinHandle<()>>,
    tx: mpsc::Sender<Update>,
    rx: mpsc::Receiver<Update>,
    pending_update: Option<Update>,
    refresh: Option<JoinHandle<()>>,
    last_refresh: Instant,
    action: Option<JoinHandle<()>>,
    exec_job: Option<JoinHandle<()>>,
    stopped_by_user: bool,
    picked: HashSet<String>,
    cleanup_flow: Option<Flow>,
    cleanup_report: Option<Report>,
    report_scroll: u16,
    cleaning: bool,
    vm: vm::Inventory,
    vm_section: bool,
    vm_details: Option<vm::Row>,
    vm_scroll: u16,
    vm_job: Option<JoinHandle<()>>,
    last_vm: Instant,
}
impl App {
    pub fn new(host: Option<String>) -> Result<Self, String> {
        let engine = Engine::new(host.or_else(|| std::env::var("DOCKER_HOST").ok()))?;
        let (tx, rx) = mpsc::channel(256);
        Ok(Self {
            engine,
            page: Page::Containers,
            quit: false,
            selected: 0,
            filter: TextInput::default(),
            filter_before: TextInput::default(),
            search_cache: SearchCache::default(),
            filtering: false,
            sort: 0,
            containers: vec![],
            images: vec![],
            volumes: vec![],
            info: Info {
                version: String::new(),
            },
            disk: Disk {
                images: vec![],
                containers: vec![],
                volumes: vec![],
                build_cache: vec![],
                layers_size: 0,
            },
            stats: HashMap::new(),
            stats_pending: HashSet::new(),
            stats_jobs: tokio::task::JoinSet::new(),
            api_epoch: 0,
            message: "Docker 启动中…".into(),
            message_until: None,
            online: false,
            load_error: None,
            confirm: None,
            help: false,
            details: false,
            logs: None,
            log_lines: vec![],
            log_filter: TextInput::default(),
            log_scroll: 0,
            log_follow: true,
            log_job: None,
            tx,
            rx,
            pending_update: None,
            refresh: None,
            last_refresh: Instant::now() - Duration::from_secs(5),
            action: None,
            exec_job: None,
            stopped_by_user: false,
            picked: HashSet::new(),
            cleanup_flow: None,
            cleanup_report: None,
            report_scroll: 0,
            cleaning: false,
            vm: vm::Inventory::pending(),
            vm_section: false,
            vm_details: None,
            vm_scroll: 0,
            vm_job: None,
            last_vm: Instant::now() - Duration::from_secs(31),
        })
    }
    fn selected_container(&self) -> Option<&Container> {
        self.filtered_containers().get(self.selected).copied()
    }
    fn filtered_containers(&self) -> Vec<&Container> {
        let matcher = Matcher::new(&self.filter);
        let mut xs: Vec<_> = self
            .containers
            .iter()
            .filter(|c| {
                let n = c.names.first().map(String::as_str).unwrap_or(&c.id);
                self.search_cache.matches(
                    &matcher,
                    &format!(
                        "{n} {} {}",
                        c.image,
                        c.labels
                            .get("com.docker.compose.project")
                            .map(String::as_str)
                            .unwrap_or("")
                    ),
                )
            })
            .collect();
        if self.sort == 1 {
            xs.sort_by(|a, b| a.image.cmp(&b.image))
        } else if self.sort == 2 {
            xs.sort_by(|a, b| a.status.cmp(&b.status))
        }
        xs
    }
    fn filtered_images(&self) -> Vec<&Image> {
        let matcher = Matcher::new(&self.filter);
        self.images
            .iter()
            .filter(|i| {
                self.search_cache
                    .matches(&matcher, &format!("{} {}", i.id, i.tags.join(" ")))
            })
            .collect()
    }
    fn filtered_volumes(&self) -> Vec<&Volume> {
        let matcher = Matcher::new(&self.filter);
        self.volumes
            .iter()
            .filter(|v| self.search_cache.matches(&matcher, &v.name))
            .collect()
    }
    fn keep_selection(&mut self, id: Option<String>) {
        self.selected = id
            .and_then(|id| self.ids().iter().position(|x| x == &id))
            .unwrap_or(0);
    }
    fn move_logs(&mut self, delta: i32) {
        let matcher = Matcher::new(&self.log_filter);
        let len = self
            .log_lines
            .iter()
            .filter(|s| self.search_cache.matches(&matcher, s))
            .count();
        self.log_scroll =
            (self.log_scroll as i64 + delta as i64).clamp(0, len.saturating_sub(1) as i64) as usize;
        self.log_follow = self.log_scroll == 0;
    }
    fn begin_filter(&mut self) {
        self.filter_before = if self.logs.is_some() {
            self.log_filter.clone()
        } else {
            self.filter.clone()
        };
        self.filtering = true;
    }
    pub fn paste(&mut self, value: &str) {
        if let Some(flow) = &mut self.cleanup_flow {
            if flow.stage == cleanup::Stage::Volumes {
                flow.input.paste(value);
            }
        } else if self.filtering {
            let id = self.selected_id();
            if self.logs.is_some() {
                self.log_filter.paste(value);
            } else {
                self.filter.paste(value);
            }
            self.keep_selection(id);
            self.log_scroll = 0;
        }
    }
    fn selected_id(&self) -> Option<String> {
        match self.page {
            Page::Containers => self.selected_container().map(|c| c.id.clone()),
            Page::Images => self
                .filtered_images()
                .get(self.selected)
                .map(|x| x.id.clone()),
            Page::Volumes => self
                .filtered_volumes()
                .get(self.selected)
                .map(|x| x.name.clone()),
            Page::Overview => None,
            Page::Cleanup if self.vm_section => self.vm_rows().get(self.selected).map(|r| r.key()),
            Page::Cleanup => self.cleanup_entries().get(self.selected).map(Entry::key),
        }
    }
    fn refresh(&mut self) {
        if self.stopped_by_user || self.refresh.as_ref().is_some_and(|j| !j.is_finished()) {
            return;
        }
        let e = self.engine.clone();
        let tx = self.tx.clone();
        let epoch = self.api_epoch;
        self.last_refresh = Instant::now();
        self.refresh = Some(tokio::spawn(async move {
            let result = async {
                e.ping().await?;
                let (containers, images, mut volumes, info, disk) =
                    tokio::try_join!(e.containers(), e.images(), e.volumes(), e.info(), e.disk())?;
                crate::api::merge_volume_usage(&mut volumes, &disk);
                Ok::<Data, String>(Data {
                    containers,
                    images,
                    volumes,
                    info,
                    disk,
                })
            }
            .await;
            let _ = tx.send(Update::Data(epoch, result)).await;
        }));
    }
    fn poll(&mut self) {
        while self.stats_jobs.try_join_next().is_some() {}
        while let Some(u) = self
            .pending_update
            .take()
            .or_else(|| self.rx.try_recv().ok())
        {
            match u {
                Update::Data(epoch, Ok(d))
                    if api_update_is_current(epoch, self.api_epoch, self.stopped_by_user) =>
                {
                    let keep = self.selected_id();
                    self.online = true;
                    self.load_error = None;
                    if !self.has_temporary_message() {
                        self.message.clear();
                    }
                    self.containers = d.containers;
                    self.containers.sort_by(|a, b| {
                        a.labels
                            .get("com.docker.compose.project")
                            .cmp(&b.labels.get("com.docker.compose.project"))
                            .then_with(|| a.names.first().cmp(&b.names.first()))
                    });
                    self.images = d.images;
                    self.volumes = d.volumes;
                    self.info = d.info;
                    self.disk = d.disk;
                    let eligible: HashSet<_> = cleanup::entries(&self.disk)
                        .iter()
                        .filter(|e| e.selectable())
                        .map(Entry::key)
                        .collect();
                    self.picked.retain(|key| eligible.contains(key));
                    if let Some(id) = keep {
                        self.selected = self.ids().iter().position(|x| x == &id).unwrap_or(0)
                    } else {
                        self.selected = 0
                    }
                    self.selected = self.selected.min(self.len().saturating_sub(1));
                    let e = self.engine.clone();
                    let tx = self.tx.clone();
                    let ids: Vec<String> = self
                        .containers
                        .iter()
                        .filter(|c| c.state == "running" && !self.stats_pending.contains(&c.id))
                        .map(|c| c.id.clone())
                        .collect();
                    for id in ids {
                        self.stats_pending.insert(id.clone());
                        let ee = e.clone();
                        let tt = tx.clone();
                        let epoch = self.api_epoch;
                        self.stats_jobs.spawn(async move {
                            let _ = tt
                                .send(Update::Stats(epoch, id.clone(), ee.stats(&id).await))
                                .await;
                        });
                    }
                }
                Update::Data(epoch, Err(reason))
                    if api_update_is_current(epoch, self.api_epoch, self.stopped_by_user)
                        && !self.has_temporary_message() =>
                {
                    self.load_error = Some(reason);
                    if !self.online {
                        self.message = "Docker 连接失败；检查服务或 socket".into()
                    } else {
                        self.message = "Docker API 暂时不可用".into()
                    }
                }
                Update::Stats(epoch, id, Ok(s))
                    if api_update_is_current(epoch, self.api_epoch, self.stopped_by_user) =>
                {
                    self.stats_pending.remove(&id);
                    self.stats.insert(id, s);
                }
                Update::Stats(epoch, id, Err(_))
                    if api_update_is_current(epoch, self.api_epoch, self.stopped_by_user) =>
                {
                    self.stats_pending.remove(&id);
                }
                Update::Vm(inventory) => {
                    let keep = if self.page == Page::Cleanup && self.vm_section {
                        self.selected_id()
                    } else {
                        None
                    };
                    self.vm = inventory;
                    if let Some(key) = keep {
                        self.selected = self
                            .vm_rows()
                            .iter()
                            .position(|r| r.key() == key)
                            .unwrap_or(0);
                    }
                    self.selected = self.selected.min(self.len().saturating_sub(1));
                }
                Update::Cleaned(report) => {
                    self.cleaning = false;
                    self.message = format!("清理完成 · {} 项失败 · Esc 关闭报告", report.failed);
                    self.cleanup_report = Some(report);
                    self.report_scroll = 0;
                    self.picked.clear();
                    self.last_refresh = Instant::now() - Duration::from_secs(3);
                }
                Update::Message(m) => {
                    self.message = m;
                    self.message_until = Some(Instant::now() + Duration::from_secs(5));
                    self.last_refresh = Instant::now() - Duration::from_secs(3)
                }
                Update::Log(epoch, s)
                    if api_update_is_current(epoch, self.api_epoch, self.stopped_by_user) =>
                {
                    let matcher = Matcher::new(&self.log_filter);
                    if !self.log_follow {
                        self.log_scroll = self.log_scroll.saturating_add(
                            s.lines()
                                .filter(|line| self.search_cache.matches(&matcher, line))
                                .count(),
                        );
                    }
                    self.log_lines.extend(s.lines().map(str::to_owned));
                    let mut bytes = self.log_lines.iter().map(String::len).sum::<usize>();
                    let mut discard = 0;
                    while self.log_lines.len().saturating_sub(discard) > 4000
                        || bytes > 4 * 1024 * 1024
                    {
                        let Some(line) = self.log_lines.get(discard) else {
                            break;
                        };
                        bytes = bytes.saturating_sub(line.len());
                        discard += 1;
                    }
                    if discard > 0 {
                        self.log_lines.drain(..discard);
                    }
                    if self.log_follow {
                        self.log_scroll = 0;
                    } else {
                        let count = self
                            .log_lines
                            .iter()
                            .filter(|line| self.search_cache.matches(&matcher, line))
                            .count();
                        self.log_scroll = self.log_scroll.min(count.saturating_sub(1));
                    }
                }
                Update::LogEnded(epoch, id)
                    if api_update_is_current(epoch, self.api_epoch, self.stopped_by_user)
                        && self.logs.as_deref() == Some(id.as_str()) =>
                {
                    self.logs = None;
                    self.message = "日志流已结束".into();
                }
                _ => {}
            }
        }
        if self.last_refresh.elapsed() >= Duration::from_secs(2) {
            self.refresh()
        }
    }
    fn len(&self) -> usize {
        match self.page {
            Page::Containers => self.filtered_containers().len(),
            Page::Images => self.filtered_images().len(),
            Page::Volumes => self.filtered_volumes().len(),
            Page::Overview => 0,
            Page::Cleanup if self.vm_section => self.vm_rows().len(),
            Page::Cleanup => self.cleanup_entries().len(),
        }
    }
    fn has_temporary_message(&self) -> bool {
        self.message_until
            .is_some_and(|until| Instant::now() < until)
    }
    fn ids(&self) -> Vec<String> {
        match self.page {
            Page::Containers => self
                .filtered_containers()
                .iter()
                .map(|c| c.id.clone())
                .collect(),
            Page::Images => self
                .filtered_images()
                .iter()
                .map(|x| x.id.clone())
                .collect(),
            Page::Volumes => self
                .filtered_volumes()
                .iter()
                .map(|x| x.name.clone())
                .collect(),
            Page::Overview => vec![],
            Page::Cleanup if self.vm_section => self.vm_rows().iter().map(|r| r.key()).collect(),
            Page::Cleanup => self.cleanup_entries().iter().map(Entry::key).collect(),
        }
    }
    fn move_sel(&mut self, d: i32) {
        let n = self.len();
        if n > 0 {
            self.selected = (self.selected as i64 + d as i64).clamp(0, n as i64 - 1) as usize;
        }
    }
    fn start_logs(&mut self) {
        let Some(c) = self.selected_container().cloned() else {
            return;
        };
        let id = c.id.clone();
        let display = c.names.first().cloned().unwrap_or_else(|| id.clone());
        self.log_lines.clear();
        self.logs = Some(id.clone());
        self.log_filter.clear();
        self.message = format!("正在跟随 {display} 日志");
        self.log_follow = true;
        self.log_scroll = 0;
        self.follow_logs(id, true);
    }
    fn follow_logs(&mut self, id: String, history: bool) {
        let e = self.engine.clone();
        let tx = self.tx.clone();
        if let Some(job) = self.log_job.take() {
            job.abort();
        }
        let epoch = self.api_epoch;
        self.log_job = Some(tokio::spawn(async move {
            let result = async {
                let (r, tty) = e.logs(&id, if history { 500 } else { 0 }).await?;
                if !r.status().is_success() {
                    return Err("读取日志失败".to_owned());
                }
                let mut stream = r.bytes_stream();
                let mut buf = Vec::new();
                while let Some(chunk) = stream.next().await {
                    let Ok(chunk) = chunk else { break };
                    buf.extend_from_slice(&chunk);
                    if cap_log_buffer(&mut buf, 256 * 1024) {
                        let _ = tx
                            .send(Update::Log(epoch, "[日志缓冲超过 256 KiB，已截断]".into()))
                            .await;
                    }
                    let lines = if tty {
                        drain_raw_log_lines(&mut buf)
                    } else {
                        drain_log_frames(&mut buf)
                    };
                    if !lines.is_empty() {
                        for l in lines {
                            if tx.send(Update::Log(epoch, l)).await.is_err() {
                                return Ok(());
                            }
                        }
                    }
                }
                Ok::<(), String>(())
            }
            .await;
            if let Err(e) = result {
                let _ = tx.send(Update::Message(e)).await;
            }
            let _ = tx.send(Update::LogEnded(epoch, id)).await;
        }));
    }
    fn command<F>(&mut self, f: F)
    where
        F: std::future::Future<Output = Result<(), String>> + Send + 'static,
    {
        if self.action.as_ref().is_some_and(|j| !j.is_finished()) {
            self.message = "操作正在进行".into();
            return;
        }
        let tx = self.tx.clone();
        self.action = Some(tokio::spawn(async move {
            let m = match f.await {
                Ok(()) => "操作完成，正在刷新".into(),
                Err(e) => e,
            };
            let _ = tx.send(Update::Message(m)).await;
        }));
    }
    fn act(&mut self, what: &str) {
        let Some(c) = self.selected_container().cloned() else {
            return;
        };
        let e = self.engine.clone();
        let tx = self.tx.clone();
        let id = c.id.clone();
        let on = c.state == "running";
        let project = c.labels.get("com.docker.compose.project").cloned();
        if what == "s" {
            self.command(async move {
                if on {
                    e.stop(&id).await
                } else {
                    e.start(&id).await
                }
            })
        } else if what == "r" {
            self.command(async move { e.restart(&id).await })
        } else if what == "p" {
            let Some(p) = project else {
                self.message = "所选容器没有 Compose 项目标签".into();
                return;
            };
            let project_rows: Vec<_> = self
                .containers
                .iter()
                .filter(|x| x.labels.get("com.docker.compose.project") == Some(&p))
                .map(|x| (x.id.clone(), x.state == "running"))
                .collect();
            let stop_project = project_rows.iter().all(|(_, running)| *running);
            let cs: Vec<_> = project_rows
                .into_iter()
                .filter(|(_, running)| *running == stop_project)
                .map(|(id, _)| id)
                .collect();
            self.command(async move {
                for id in cs {
                    let res = if stop_project {
                        e.stop(&id).await
                    } else {
                        e.start(&id).await
                    };
                    res?;
                }
                let _ = tx
                    .send(Update::Message(format!("Compose 项目 {p} 操作完成")))
                    .await;
                Ok(())
            })
        }
    }
    fn confirm_project_restart(&mut self) {
        let Some(c) = self.selected_container() else {
            return;
        };
        let Some(project) = c.labels.get("com.docker.compose.project").cloned() else {
            self.message = "所选容器没有 Compose 项目标签".into();
            return;
        };
        let ids = compose_project_ids(&self.containers, &project);
        self.confirm = Some(Confirm::ProjectRestart(project, ids));
    }
    fn suspend_api_for_daemon_stop(&mut self) -> ApiJobs {
        self.stopped_by_user = true;
        self.api_epoch = self.api_epoch.wrapping_add(1);
        self.online = false;
        self.filtering = false;
        self.confirm = None;
        self.logs = None;
        let handles = [
            &mut self.refresh,
            &mut self.log_job,
            &mut self.action,
            &mut self.exec_job,
        ]
        .into_iter()
        .filter_map(Option::take)
        .collect::<Vec<_>>();
        for handle in &handles {
            handle.abort();
        }
        let mut stats = std::mem::replace(&mut self.stats_jobs, tokio::task::JoinSet::new());
        stats.abort_all();
        self.stats_pending.clear();
        self.message = "正在停止 Docker；下次连接会自动启动。".into();
        ApiJobs { handles, stats }
    }
    fn confirm_action(&mut self) {
        let Some(c) = self.confirm.take() else { return };
        match c {
            Confirm::ProjectRestart(_, ids) => {
                let engine = self.engine.clone();
                self.command(async move {
                    for id in ids {
                        engine.restart(&id).await?;
                    }
                    Ok(())
                })
            }
            Confirm::StopDaemon => {
                let api_jobs = self.suspend_api_for_daemon_stop();
                self.command(async move {
                    api_jobs.stop_and_join().await;
                    let status = tokio::task::spawn_blocking(|| {
                        Command::new("systemctl")
                            .args(["--user", "stop", "docker.service", "docker-proxy.service"])
                            .status()
                    })
                    .await
                    .map_err(|_| "无法运行 systemctl".to_owned())?
                    .map_err(|_| "无法运行 systemctl".to_owned())?;
                    if status.success() {
                        Err("Docker 已停止；下次连接会自动启动。按 s 恢复查看".into())
                    } else {
                        Err("停止服务失败".into())
                    }
                })
            }
        }
    }
    fn action_key(&mut self, k: KeyEvent) {
        if self.vm_details.is_some() {
            match k.code {
                KeyCode::Esc => self.vm_details = None,
                KeyCode::Char('j') | KeyCode::Down => {
                    self.vm_scroll = self.vm_scroll.saturating_add(1)
                }
                KeyCode::Char('k') | KeyCode::Up => {
                    self.vm_scroll = self.vm_scroll.saturating_sub(1)
                }
                KeyCode::Char('y') => self.copy_vm_path(),
                _ => (),
            }
            return;
        }
        if self.cleanup_report.is_some() {
            match k.code {
                KeyCode::Esc | KeyCode::Char('q') => self.cleanup_report = None,
                KeyCode::Char('j') | KeyCode::Down => {
                    self.report_scroll = self.report_scroll.saturating_add(1)
                }
                KeyCode::Char('k') | KeyCode::Up => {
                    self.report_scroll = self.report_scroll.saturating_sub(1)
                }
                _ => (),
            }
            return;
        }
        if let Some(flow) = &mut self.cleanup_flow {
            if k.code == KeyCode::Esc {
                self.cleanup_flow = None;
            } else if let Some(plan) = flow.handle_key(k) {
                self.cleanup_flow = None;
                self.execute_cleanup(plan);
            }
            return;
        }
        if self.cleaning {
            if k.code == KeyCode::Char('q') {
                self.message = "清理执行中，请等待报告".into();
            }
            return;
        }
        if self.confirm.is_some() {
            match k.code {
                KeyCode::Esc | KeyCode::Char('n') => self.confirm = None,
                KeyCode::Char('y') => self.confirm_action(),
                _ => {}
            }
            return;
        }
        if self.help {
            if matches!(k.code, KeyCode::Esc | KeyCode::Char('?')) {
                self.help = false
            }
            return;
        }
        if self.filtering {
            let id = self.selected_id();
            let mut changed = false;
            match k.code {
                KeyCode::Esc => {
                    if self.logs.is_some() {
                        self.log_filter = self.filter_before.clone();
                    } else {
                        self.filter = self.filter_before.clone();
                    }
                    self.filtering = false;
                    changed = true;
                }
                KeyCode::Enter => self.filtering = false,
                KeyCode::Down => {
                    if self.logs.is_some() {
                        self.move_logs(-1);
                    } else {
                        self.move_sel(1);
                    }
                }
                KeyCode::Up => {
                    if self.logs.is_some() {
                        self.move_logs(1);
                    } else {
                        self.move_sel(-1);
                    }
                }
                KeyCode::PageDown => {
                    if self.logs.is_some() {
                        self.move_logs(-10);
                    } else {
                        self.move_sel(10);
                    }
                }
                KeyCode::PageUp => {
                    if self.logs.is_some() {
                        self.move_logs(10);
                    } else {
                        self.move_sel(-10);
                    }
                }
                _ => {
                    changed = if self.logs.is_some() {
                        self.log_filter.handle_key(k)
                    } else {
                        self.filter.handle_key(k)
                    }
                }
            }
            if changed {
                self.keep_selection(id);
                self.log_scroll = 0;
            }
            return;
        }
        if k.modifiers.intersects(
            crossterm::event::KeyModifiers::CONTROL | crossterm::event::KeyModifiers::ALT,
        ) {
            return;
        }
        if self.details {
            if k.code == KeyCode::Esc {
                self.details = false;
            }
            return;
        }
        let vm_readonly = self.page == Page::Cleanup
            && (matches!(k.code, KeyCode::Tab | KeyCode::Char('v'))
                || self.vm_section
                    && matches!(
                        k.code,
                        KeyCode::Enter | KeyCode::Char('y' | 'r' | ' ' | 'd')
                    ));
        if self.stopped_by_user && !stopped_key_allowed(k.code) && !vm_readonly {
            self.message = "Docker daemon 已手动停止；按 s 重新连接".into();
            return;
        }
        if self.logs.is_some() {
            match k.code {
                KeyCode::Esc if !self.log_filter.is_empty() => {
                    self.log_filter.clear();
                    self.log_scroll = 0;
                }
                KeyCode::Esc | KeyCode::Char('q') => {
                    self.logs = None;
                    if let Some(job) = self.log_job.take() {
                        job.abort();
                    }
                }
                KeyCode::Char('j') | KeyCode::Down => self.move_logs(-1),
                KeyCode::Char('k') | KeyCode::Up => self.move_logs(1),
                KeyCode::PageDown => self.move_logs(-10),
                KeyCode::PageUp => self.move_logs(10),
                KeyCode::Char('g') | KeyCode::Home => self.move_logs(i32::MAX),
                KeyCode::Char('G') => {
                    self.log_follow = true;
                    self.log_scroll = 0;
                }
                KeyCode::Char('/') => self.begin_filter(),
                _ => {}
            }
            return;
        }
        if self.page == Page::Cleanup {
            if matches!(k.code, KeyCode::Tab | KeyCode::Char('v')) {
                self.vm_section = !self.vm_section;
                self.selected = 0;
                return;
            }
            if self.vm_section {
                match k.code {
                    KeyCode::Enter => {
                        self.vm_details = self.vm_rows().get(self.selected).cloned().cloned();
                        self.vm_scroll = 0;
                        return;
                    }
                    KeyCode::Char('y') => {
                        self.copy_vm_path();
                        return;
                    }
                    KeyCode::Char('r') => {
                        self.last_vm = Instant::now() - Duration::from_secs(31);
                        return;
                    }
                    KeyCode::Char(' ' | 'd') => {
                        self.message = "VM 严格只读；不提供虚拟机、镜像、快照或 ISO 删除".into();
                        return;
                    }
                    _ => (),
                }
            }
        }
        match k.code {
            KeyCode::Char('q') => self.quit = true,
            KeyCode::Char('?') => self.help = true,
            KeyCode::Enter
                if self.page == Page::Containers && self.selected_container().is_some() =>
            {
                self.details = true;
            }
            KeyCode::Char('1') => {
                self.page = Page::Containers;
                self.selected = 0
            }
            KeyCode::Char('2') => {
                self.page = Page::Images;
                self.selected = 0
            }
            KeyCode::Char('3') => {
                self.page = Page::Volumes;
                self.selected = 0
            }
            KeyCode::Char('4') => {
                self.page = Page::Overview;
                self.selected = 0
            }
            KeyCode::Char('5') => {
                self.page = Page::Cleanup;
                self.selected = 0;
            }
            KeyCode::Char(' ') if self.page == Page::Cleanup => {
                if let Some(entry) = self.cleanup_entries().get(self.selected) {
                    if entry.selectable() {
                        let key = entry.key();
                        if !self.picked.remove(&key) {
                            self.picked.insert(key);
                        }
                    } else {
                        self.message = entry.blocked.clone().unwrap_or_default();
                    }
                }
            }
            KeyCode::Enter | KeyCode::Char('d') if self.page == Page::Cleanup => {
                let plan = cleanup::selected(&cleanup::entries(&self.disk), &self.picked);
                self.preview_cleanup(plan);
            }
            KeyCode::Esc => {
                let id = self.selected_id();
                self.filter.clear();
                self.keep_selection(id);
            }
            KeyCode::PageDown => self.move_sel(10),
            KeyCode::PageUp => self.move_sel(-10),
            KeyCode::Char('g') | KeyCode::Home => self.selected = 0,
            KeyCode::Char('G') | KeyCode::End => self.selected = self.len().saturating_sub(1),
            KeyCode::Char('j') | KeyCode::Down => self.move_sel(1),
            KeyCode::Char('k') | KeyCode::Up => self.move_sel(-1),
            KeyCode::Char('/') => self.begin_filter(),
            KeyCode::Char('o') => {
                let id = self.selected_id();
                self.sort = (self.sort + 1) % 3;
                self.keep_selection(id);
            }
            KeyCode::Char('s') if self.stopped_by_user => {
                self.stopped_by_user = false;
                self.api_epoch = self.api_epoch.wrapping_add(1);
                self.message = "正在重新连接 Docker…".into();
                self.refresh()
            }
            KeyCode::Char('s') if self.page == Page::Containers => self.act("s"),
            KeyCode::Char('r') if self.page == Page::Containers => self.act("r"),
            KeyCode::Char('R') if self.page == Page::Containers => self.confirm_project_restart(),
            KeyCode::Char('p') if self.page == Page::Containers => self.act("p"),
            KeyCode::Char('l') if self.page == Page::Containers => self.start_logs(),
            KeyCode::Char('e') if self.page == Page::Containers => self.exec_container(),
            KeyCode::Char('d') => {
                if let Some(id) = self.selected_id() {
                    let kind = match self.page {
                        Page::Containers => Some(Kind::Container),
                        Page::Images => Some(Kind::Image),
                        Page::Volumes => Some(Kind::Volume),
                        _ => None,
                    };
                    let plan = cleanup::entries(&self.disk)
                        .into_iter()
                        .filter(|e| Some(e.kind) == kind && e.id == id && e.selectable())
                        .collect();
                    self.preview_cleanup(plan);
                }
            }
            KeyCode::Char('S') if self.engine.can_stop_local_daemon => {
                self.confirm = Some(Confirm::StopDaemon)
            }
            KeyCode::Char('S') => {
                self.message = "自定义 DOCKER_HOST 不能通过本地 systemd units 停止".into()
            }
            _ => {}
        }
    }
    fn exec_container(&mut self) {
        let Some(c) = self.selected_container().cloned() else {
            return;
        };
        let name = c
            .names
            .first()
            .map(|s| s.trim_start_matches('/'))
            .unwrap_or(&c.id)
            .to_owned();
        let host = self.engine.host.clone();
        let e = self.engine.clone();
        let tx = self.tx.clone();
        self.exec_job = Some(tokio::spawn(async move {
            let bash = e.exec_has_bash(&c.id).await;
            let shell = if bash { "bash" } else { "sh" };
            let mut cmd = Command::new("kitty");
            cmd.args([
                "--class=mayon-docker-exec",
                "docker",
                "--host",
                &host,
                "exec",
                "-it",
                &name,
                shell,
            ]);
            match cmd.spawn() {
                Ok(_) => {
                    let _ = tx
                        .send(Update::Message(format!(
                            "已在 Kitty 中打开 {name} 的交互 shell"
                        )))
                        .await;
                }
                Err(_) => {
                    let _ = tx
                        .send(Update::Message("无法启动 Kitty/docker CLI".into()))
                        .await;
                }
            }
        }));
    }
    pub fn key(&mut self, k: KeyEvent) {
        if k.code == KeyCode::Char('c')
            && k.modifiers
                .contains(crossterm::event::KeyModifiers::CONTROL)
        {
            self.quit = true;
            return;
        }
        let before = self.message.clone();
        self.action_key(k);
        if self.message != before {
            self.message_until = Some(Instant::now() + Duration::from_secs(5));
        }
        self.pause_hidden_vm();
    }
    pub fn mouse(&mut self, m: MouseEvent, size: ratatui::layout::Size) {
        if self.confirm.is_some()
            || self.help
            || self.details
            || self.filtering
            || self.cleanup_flow.is_some()
            || self.cleaning
            || self.vm_details.is_some()
        {
            return;
        }
        if self.cleanup_report.is_some() {
            match m.kind {
                MouseEventKind::ScrollDown => {
                    self.report_scroll = self.report_scroll.saturating_add(3)
                }
                MouseEventKind::ScrollUp => {
                    self.report_scroll = self.report_scroll.saturating_sub(3)
                }
                _ => (),
            }
            return;
        }
        match m.kind {
            MouseEventKind::ScrollDown => {
                if self.logs.is_some() {
                    self.move_logs(-3);
                } else {
                    self.move_sel(1);
                }
            }
            MouseEventKind::ScrollUp => {
                if self.logs.is_some() {
                    self.move_logs(3);
                } else {
                    self.move_sel(-1);
                }
            }
            MouseEventKind::Down(crossterm::event::MouseButton::Left) => {
                if m.row == 1 {
                    if let Some(p) = tab_at(m.column) {
                        self.page = match p {
                            0 => Page::Containers,
                            1 => Page::Images,
                            2 => Page::Volumes,
                            3 => Page::Overview,
                            _ => Page::Cleanup,
                        };
                        self.selected = 0
                    }
                } else if m.row >= if self.page == Page::Cleanup { 15 } else { 5 } {
                    let first = if self.page == Page::Cleanup { 15 } else { 5 };
                    let visible_rows = size.height.saturating_sub(first + 3) as usize;
                    let visible_row = (m.row - first) as usize;
                    self.selected =
                        table_click_index(self.selected, visible_rows, visible_row, self.len());
                }
            }
            _ => {}
        }
    }
    fn pause_hidden_vm(&mut self) {
        if !(self.page == Page::Cleanup && self.vm_section) {
            if let Some(job) = self.vm_job.take() {
                job.abort();
            }
        }
    }
    pub async fn changed(&mut self) {
        self.pending_update = self.rx.recv().await;
    }
    pub fn deadline(&self) -> Instant {
        let mut deadline = if self.refresh.is_none() && !self.stopped_by_user {
            self.last_refresh + Duration::from_secs(2)
        } else {
            Instant::now() + Duration::from_secs(3600)
        };
        if self.page == Page::Cleanup && self.vm_section && self.vm_job.is_none() {
            deadline = deadline.min(self.last_vm + Duration::from_secs(30));
        }
        if let Some(until) = self.message_until {
            deadline = deadline.min(until);
        }
        deadline
    }
    pub fn suspend(&mut self) {
        self.api_epoch = self.api_epoch.wrapping_add(1);
        for job in [
            &mut self.refresh,
            &mut self.vm_job,
            &mut self.log_job,
            &mut self.exec_job,
        ] {
            if let Some(job) = job.take() {
                job.abort();
            }
        }
        self.stats_jobs.abort_all();
        self.stats_pending.clear();
        // A confirmed mutation is allowed to finish; no new requests start while this page is hidden.
    }
    pub fn resume(&mut self) {
        self.last_refresh = Instant::now() - Duration::from_secs(3);
        self.last_vm = Instant::now() - Duration::from_secs(31);
        if let Some(id) = self.logs.clone() {
            self.follow_logs(id, false);
        }
    }
    pub fn editing(&self) -> bool {
        self.filtering || self.cleanup_flow.is_some() || self.confirm.is_some()
    }
    pub fn tick(&mut self) -> bool {
        self.pause_hidden_vm();
        let expired = self
            .message_until
            .is_some_and(|until| Instant::now() >= until);
        if self.refresh.as_ref().is_some_and(|j| j.is_finished()) {
            self.refresh = None;
        }
        if self.vm_job.as_ref().is_some_and(|j| j.is_finished()) {
            self.vm_job = None;
        }
        if self
            .message_until
            .is_some_and(|until| Instant::now() >= until)
        {
            self.message.clear();
            self.message_until = None;
        }
        if self.page == Page::Cleanup
            && self.vm_section
            && self.last_vm.elapsed() >= Duration::from_secs(30)
            && self.vm_job.as_ref().is_none_or(|j| j.is_finished())
        {
            let tx = self.tx.clone();
            self.last_vm = Instant::now();
            self.vm_job = Some(tokio::spawn(async move {
                let inventory = vm::collect().await;
                let _ = tx.send(Update::Vm(inventory)).await;
            }));
        }
        self.poll();
        expired
    }
    pub fn draw(&mut self, f: &mut Frame) {
        let area = f.area();
        self.draw_in(f, area);
    }
    pub fn draw_in(&mut self, f: &mut Frame, viewport: ratatui::layout::Rect) {
        let (title, tabs, page) = (
            format!(
                " 󰡨 {} · {} · {}",
                if self.page == Page::Cleanup {
                    "Docker + VM"
                } else {
                    "Docker"
                },
                if self.stopped_by_user {
                    "已停止"
                } else if self.online {
                    "运行"
                } else {
                    "启动中"
                },
                if self.stopped_by_user {
                    "s 重新连接"
                } else if self.online {
                    self.info.version.as_str()
                } else {
                    "等待 daemon"
                }
            ),
            ["容器", "镜像", "卷", "概览", "空间"],
            match self.page {
                Page::Containers => 0,
                Page::Images => 1,
                Page::Volumes => 2,
                Page::Overview => 3,
                Page::Cleanup => 4,
            },
        );
        let hint = if self.logs.is_some() {
            "j/k 滚动  G 跟随  / 过滤  Esc 返回"
        } else if self.page == Page::Cleanup && self.vm_section {
            "Tab Docker/VM  Enter 详情  y 复制路径  / 过滤  r 刷新  ? 帮助"
        } else if self.page == Page::Cleanup {
            "Tab Docker/VM  Space 多选  Enter 预览  j/k 选择  / 过滤  1-5 切页  ? 帮助"
        } else {
            "o 排序  j/k 选择  Enter 详情  1-5 页签  / 过滤  s 启停  r 单重启  p 项目启停  R 项目重启  l 日志  e exec  d 删除  ? 帮助"
        };
        let area = ui::chrome_in(f, viewport, &title, &tabs, page, hint, &self.message);
        if self.logs.is_some() {
            self.draw_logs(f, area);
            return;
        }
        if let Some(row) = &self.vm_details {
            let body = row.details();
            use unicode_width::UnicodeWidthStr;
            let lines: usize = body
                .lines()
                .map(|l| {
                    l.width()
                        .max(1)
                        .div_ceil(area.width.saturating_sub(2).max(1) as usize)
                })
                .sum();
            self.vm_scroll = self.vm_scroll.min(
                lines
                    .saturating_sub(area.height.saturating_sub(2) as usize)
                    .min(u16::MAX as usize) as u16,
            );
            f.render_widget(
                Paragraph::new(body)
                    .style(ui::base())
                    .block(ui::block(
                        " VM 详情 · 严格只读 · j/k 滚动 · Esc 返回 ",
                        true,
                    ))
                    .wrap(Wrap { trim: false })
                    .scroll((self.vm_scroll, 0)),
                area,
            );
            return;
        }
        if let Some(flow) = &self.cleanup_flow {
            f.render_widget(
                Paragraph::new(flow.body())
                    .style(ui::base())
                    .block(ui::block(" 清理 · Esc 取消 ", true))
                    .wrap(Wrap { trim: false }),
                area,
            );
            if flow.stage == cleanup::Stage::Volumes {
                flow.input.render(
                    f,
                    ratatui::layout::Rect::new(
                        area.x.saturating_add(7),
                        area.y.saturating_add(6),
                        area.width.saturating_sub(8),
                        1,
                    ),
                    ui::base().fg(BLUE),
                );
            }
            return;
        }
        if let Some(report) = &self.cleanup_report {
            let body = report.body();
            use unicode_width::UnicodeWidthStr;
            let line_count: usize = body
                .lines()
                .map(|line| {
                    line.width()
                        .max(1)
                        .div_ceil(area.width.saturating_sub(2).max(1) as usize)
                })
                .sum();
            self.report_scroll = self.report_scroll.min(
                line_count
                    .saturating_sub(area.height.saturating_sub(2) as usize)
                    .min(u16::MAX as usize) as u16,
            );
            f.render_widget(
                Paragraph::new(body)
                    .style(ui::base())
                    .block(ui::block(" 清理报告 · j/k 滚动 · Esc 关闭 ", true))
                    .wrap(Wrap { trim: false })
                    .scroll((self.report_scroll, 0)),
                area,
            );
            return;
        }
        match self.page {
            Page::Containers => self.draw_containers(f, area),
            Page::Images => self.draw_images(f, area),
            Page::Volumes => self.draw_volumes(f, area),
            Page::Overview => self.draw_overview(f, area),
            Page::Cleanup => self.draw_cleanup(f, area),
        }
        if self.filtering {
            self.draw_filter(f, &self.filter, viewport);
        }
        if self.help {
            ui::help(
                f,
                "1-5 切页 · j/k 或方向键选择 · / 过滤\nEnter 查看容器完整镜像、状态与 IP 端口详情\ns 启动/停止容器 · r 单容器重启 · p 项目启停 · R 重启整个 Compose 项目\nl 跟随日志 · 日志内 j/k 滚动 / 过滤\ne 在新 Kitty 中进入容器 · d 删除并确认\n5 Docker + VM 空间：Tab/v 切分区\nVM：Enter 完整路径/详情 · y 复制路径 · r 刷新\nVM、镜像、快照、孤立候选和 ISO 均严格只读\nDocker：Space 多选 · Enter/d 冻结准确清单预览\nj/k 看完每项 → y 二次确认 → y 执行\n卷默认不选；需另行输入 DELETE 与完整卷名，数据不可恢复\n清理前重新验证引用；运行中容器与被引用镜像、卷不可选\nS 停止 Docker 与代理服务 · s 恢复连接\nq 退出 · ? 关闭帮助",
            )
        }
        if self.details {
            if let Some(container) = self.selected_container() {
                ui::dialog(f, " 容器详情 · Esc 关闭 ", &container_details(container));
            }
        }
        if let Some(c) = self.confirm.as_ref() {
            ui::dialog(f, " 确认操作 ", &confirm_body(c))
        }
    }
    fn draw_filter(&self, f: &mut Frame, input: &TextInput, area: ratatui::layout::Rect) {
        let row = area.bottom().saturating_sub(2);
        f.render_widget(
            Paragraph::new(" 过滤 /").style(ui::base().fg(BLUE)),
            ratatui::layout::Rect::new(area.x, row, area.width, 1),
        );
        input.render(
            f,
            ratatui::layout::Rect::new(
                area.x.saturating_add(7),
                row,
                area.width.saturating_sub(8),
                1,
            ),
            ui::base().fg(BLUE),
        );
    }
    fn draw_containers(&self, f: &mut Frame, a: ratatui::layout::Rect) {
        let xs = self.filtered_containers();
        let rows = xs
            .iter()
            .map(|c| {
                let project = c
                    .labels
                    .get("com.docker.compose.project")
                    .map(String::as_str)
                    .unwrap_or("-");
                let n = c
                    .names
                    .first()
                    .map(|s| s.trim_start_matches('/'))
                    .unwrap_or(&c.id);
                let ports = compact_port_mappings(c);
                let stat = self.stats.get(&c.id);
                vec![
                    format!("{project}/{n}"),
                    c.image.clone(),
                    compact_status(&c.status),
                    ports,
                    stat.map(|s| format!("{:.1}%", s.cpu))
                        .unwrap_or_else(|| "--".into()),
                    stat.map(|s| {
                        format!(
                            "{}/{}",
                            ui::theme::bytes(s.memory),
                            ui::theme::bytes(s.limit)
                        )
                    })
                    .unwrap_or_else(|| "--".into()),
                ]
            })
            .collect();
        self.draw_table(
            f,
            a,
            &format!(
                " 容器 {}{} ",
                xs.len(),
                if self.filter.is_empty() {
                    String::new()
                } else {
                    format!(" · /{}", self.filter)
                }
            ),
            vec!["项目 / 容器", "镜像", "状态", "端口", "CPU", "内存"],
            rows,
            &[
                Constraint::Percentage(24),
                Constraint::Percentage(17),
                Constraint::Percentage(17),
                Constraint::Percentage(19),
                Constraint::Percentage(8),
                Constraint::Percentage(13),
            ],
            self.selected,
        )
    }
    #[allow(clippy::too_many_arguments)]
    fn draw_table(
        &self,
        f: &mut Frame,
        area: ratatui::layout::Rect,
        title: &str,
        headers: Vec<&str>,
        rows: Vec<Vec<String>>,
        widths: &[Constraint],
        selected: usize,
    ) {
        let matcher = Matcher::new(&self.filter);
        let rows = rows
            .into_iter()
            .map(|row| {
                row.into_iter()
                    .enumerate()
                    .map(|(index, cell)| {
                        let line = self.search_cache.highlight(&matcher, &cell);
                        if headers.get(index).is_some_and(|label| {
                            matches!(
                                *label,
                                "大小" | "占用" | "可回收" | "CPU" | "内存" | "虚拟" | "引用"
                            )
                        }) {
                            line.right_aligned()
                        } else {
                            line
                        }
                    })
                    .collect()
            })
            .collect();
        let total = match self.page {
            Page::Containers => self.containers.len(),
            Page::Images => self.images.len(),
            Page::Volumes => self.volumes.len(),
            Page::Cleanup if self.vm_section => self.vm.rows.len(),
            Page::Cleanup => cleanup::entries(&self.disk).len(),
            Page::Overview => 0,
        };
        ui::table_highlighted(
            f,
            area,
            &format!("{title} · {}/{} · /{}", self.len(), total, self.filter),
            headers,
            rows,
            widths,
            selected,
        );
        if self.len() == 0 {
            let inner = ratatui::layout::Rect::new(
                area.x.saturating_add(1),
                area.y.saturating_add(2),
                area.width.saturating_sub(2),
                area.height.saturating_sub(3),
            );
            if self.page == Page::Cleanup && self.vm_section {
                ui::list_state(
                    f,
                    inner,
                    ui::ListState::Empty,
                    "暂无 VM 项目 · r 刷新 · Tab 返回 Docker",
                );
            } else if let Some(reason) = &self.load_error {
                ui::list_state(
                    f,
                    inner,
                    ui::ListState::Error,
                    &format!("{reason} · 检查 Docker socket；自动重试中"),
                );
            } else if !self.online {
                ui::list_state(
                    f,
                    inner,
                    ui::ListState::Loading,
                    "正在连接 Docker · 可用 1–5 切换子页",
                );
            } else {
                ui::list_state(
                    f,
                    inner,
                    ui::ListState::Empty,
                    "无匹配项 · Esc 清除过滤；1–5 切换子页",
                );
            }
        }
    }
    fn draw_images(&self, f: &mut Frame, a: ratatui::layout::Rect) {
        let rows = self
            .filtered_images()
            .iter()
            .map(|i| {
                vec![
                    short(&i.id).to_string(),
                    i.tags.first().cloned().unwrap_or_else(|| "<悬空>".into()),
                    ui::theme::bytes(i.size),
                    if crate::api::is_dangling(&i.tags) {
                        "悬空".to_string()
                    } else {
                        String::new()
                    },
                ]
            })
            .collect();
        self.draw_table(
            f,
            a,
            &format!(" 镜像 {} ", self.images.len()),
            vec!["ID", "标签", "大小", "标记"],
            rows,
            &[
                Constraint::Percentage(30),
                Constraint::Percentage(42),
                Constraint::Percentage(16),
                Constraint::Percentage(12),
            ],
            self.selected,
        )
    }
    fn draw_volumes(&self, f: &mut Frame, a: ratatui::layout::Rect) {
        let rows = self
            .filtered_volumes()
            .iter()
            .map(|v| {
                vec![
                    v.name.clone(),
                    v.usage
                        .as_ref()
                        .map(|u| {
                            if u.size < 0 {
                                "未知".into()
                            } else {
                                ui::theme::bytes(u.size as u64)
                            }
                        })
                        .unwrap_or_else(|| "未知".into()),
                    v.usage
                        .as_ref()
                        .map(|u| {
                            if u.refs > 0 {
                                "使用中"
                            } else if u.refs == 0 {
                                "未使用"
                            } else {
                                "未知 / 保护"
                            }
                        })
                        .unwrap_or("未知")
                        .into(),
                ]
            })
            .collect();
        self.draw_table(
            f,
            a,
            &format!(" 卷 {}  · d 预览 · 卷需输入名称确认 ", self.volumes.len()),
            vec!["卷名", "大小", "状态"],
            rows,
            &[
                Constraint::Percentage(62),
                Constraint::Percentage(18),
                Constraint::Percentage(20),
            ],
            self.selected,
        )
    }
    fn vm_rows(&self) -> Vec<&vm::Row> {
        let matcher = Matcher::new(&self.filter);
        self.vm
            .rows
            .iter()
            .filter(|r| {
                self.search_cache.matches(
                    &matcher,
                    &format!(
                        "{} {} {} {} {}",
                        r.uri,
                        r.owner,
                        r.kind,
                        r.path
                            .as_ref()
                            .map(|p| p.display().to_string())
                            .unwrap_or_default(),
                        r.note
                    ),
                )
            })
            .collect()
    }
    fn copy_vm_path(&mut self) {
        let row = self
            .vm_details
            .as_ref()
            .or_else(|| self.vm_rows().get(self.selected).copied())
            .cloned();
        let Some(path) = row.and_then(|r| r.path) else {
            self.message = "此项没有本地文件路径".into();
            return;
        };
        self.command(async move {
            vm::copy_path(&path).await?;
            Err("已复制完整 VM 路径；未读取或修改文件".into())
        });
    }
    fn cleanup_entries(&self) -> Vec<Entry> {
        let matcher = Matcher::new(&self.filter);
        cleanup::entries(&self.disk)
            .into_iter()
            .filter(|e| {
                self.search_cache
                    .matches(&matcher, &format!("{} {} {}", e.kind.label(), e.id, e.name))
            })
            .collect()
    }
    fn preview_cleanup(&mut self, plan: Vec<Entry>) {
        if self.action.as_ref().is_some_and(|j| !j.is_finished()) {
            self.message = "操作正在进行，完成后再预览".into();
            return;
        }
        self.cleanup_flow = Flow::new(plan);
        if self.cleanup_flow.is_none() {
            self.message = "没有可清理的选择；运行中、被引用或引用未知的资源已锁定".into();
        }
    }
    fn execute_cleanup(&mut self, plan: Vec<Entry>) {
        self.cleaning = true;
        self.message = "正在清理已确认清单…".into();
        let engine = self.engine.clone();
        let tx = self.tx.clone();
        self.action = Some(tokio::spawn(async move {
            let report = cleanup::execute(&engine, &plan).await;
            let _ = tx.send(Update::Cleaned(report)).await;
        }));
    }
    fn draw_cleanup(&self, f: &mut Frame, a: ratatui::layout::Rect) {
        let areas = ratatui::layout::Layout::vertical([Constraint::Length(10), Constraint::Min(3)])
            .split(a);
        let plan = cleanup::selected(&cleanup::entries(&self.disk), &self.picked);
        let summary = format!(
            "{}\n{}\nDocker 所选 {} 项 · 预计释放 {} · 卷数据不可恢复",
            cleanup::summary(&self.disk),
            self.vm.summary(),
            plan.len(),
            cleanup::estimate(&plan)
        );
        f.render_widget(
            Paragraph::new(summary)
                .style(ui::base())
                .block(ui::block(" Docker + VM 空间 · VM 严格只读 ", true)),
            areas[0],
        );
        if self.vm_section {
            let rows = self
                .vm_rows()
                .iter()
                .map(|r| {
                    vec![
                        r.uri.trim_start_matches("qemu:///").into(),
                        r.kind.clone(),
                        r.owner.clone(),
                        r.path
                            .as_ref()
                            .map(|p| {
                                format!(
                                    "…/{}/{}",
                                    p.parent()
                                        .and_then(|d| d.file_name())
                                        .unwrap_or_default()
                                        .to_string_lossy(),
                                    p.file_name().unwrap_or_default().to_string_lossy()
                                )
                            })
                            .unwrap_or_else(|| r.note.clone()),
                        cleanup::bytes(r.actual).replace(".0 ", " "),
                        cleanup::bytes(r.virtual_size).replace(".0 ", " "),
                    ]
                })
                .collect();
            self.draw_table(
                f,
                areas[1],
                &format!(" VM · 大小降序 · Tab 返回 Docker · /{} ", self.filter),
                vec![
                    "连接",
                    "类型",
                    "虚拟机/池",
                    "路径（Enter 完整）",
                    "占用",
                    "虚拟",
                ],
                rows,
                &[
                    Constraint::Length(7),
                    Constraint::Length(12),
                    Constraint::Length(15),
                    Constraint::Min(10),
                    Constraint::Length(9),
                    Constraint::Length(9),
                ],
                self.selected,
            );
            return;
        }
        let entries = self.cleanup_entries();
        let rows = entries
            .iter()
            .map(|e| {
                vec![
                    if !e.selectable() {
                        "锁".into()
                    } else if self.picked.contains(&e.key()) {
                        "[x]".into()
                    } else {
                        "[ ]".into()
                    },
                    e.kind.label().into(),
                    if e.kind == Kind::Volume || e.name.is_empty() {
                        e.id.clone()
                    } else {
                        e.name.clone()
                    },
                    cleanup::bytes(e.size).replace(".0 ", " "),
                    if e.selectable() {
                        cleanup::bytes(e.reclaim).replace(".0 ", " ")
                    } else {
                        "—".into()
                    },
                    e.blocked.clone().unwrap_or_else(|| {
                        if e.kind == Kind::Volume {
                            "需输入卷名".into()
                        } else {
                            "可清理".into()
                        }
                    }),
                ]
            })
            .collect();
        self.draw_table(
            f,
            areas[1],
            &format!(
                " Docker · 大小降序 · /{} · Space 多选 · Tab VM ",
                self.filter
            ),
            vec!["选", "类型", "名称 / ID", "占用", "可回收", "状态"],
            rows,
            &[
                Constraint::Length(3),
                Constraint::Length(8),
                Constraint::Min(10),
                Constraint::Length(9),
                Constraint::Length(9),
                Constraint::Length(18),
            ],
            self.selected,
        );
    }
    fn draw_overview(&self, f: &mut Frame, a: ratatui::layout::Rect) {
        let body = format!("Docker Engine {}\n\n{}\n{}\n\n5 Docker + VM 空间：Tab/v 切分区，VM 严格只读。\nS 停止 daemon + docker-proxy（另行确认）。", self.info.version, cleanup::summary(&self.disk),self.vm.summary());
        f.render_widget(
            Paragraph::new(body)
                .style(ui::base())
                .block(ui::block(" Docker Engine 概览 ", true))
                .wrap(Wrap { trim: false }),
            a,
        );
    }
    fn draw_logs(&self, f: &mut Frame, a: ratatui::layout::Rect) {
        let matcher = Matcher::new(&self.log_filter);
        let visible: Vec<_> = self
            .log_lines
            .iter()
            .filter(|s| self.search_cache.matches(&matcher, s))
            .collect();
        let end = visible.len().saturating_sub(self.log_scroll);
        let start = end.saturating_sub((a.height as usize).saturating_sub(2));
        let mut body = visible
            .iter()
            .skip(start)
            .take(end - start)
            .map(|s| {
                let text = ui::theme::clip(s, (a.width as usize).saturating_sub(2));
                let ranges = self
                    .search_cache
                    .find(&matcher, &text)
                    .map(|m| m.ranges)
                    .unwrap_or_default();
                ui::search::highlight(&text, &ranges)
            })
            .collect::<Vec<_>>();
        if visible.is_empty() {
            body.push(Line::from("无匹配日志 · Esc 清除过滤"));
        }
        f.render_widget(
            Paragraph::new(body)
                .style(ui::base())
                .block(ui::block(
                    format!(
                        " 实时日志 · {} · {}/{} · /{} ",
                        self.logs.as_deref().map(short).unwrap_or(""),
                        visible.len(),
                        self.log_lines.len(),
                        self.log_filter
                    ),
                    true,
                ))
                .wrap(Wrap { trim: false }),
            a,
        );
        if self.filtering {
            self.draw_filter(
                f,
                &self.log_filter,
                ratatui::layout::Rect::new(a.x, a.y, a.width, a.height.saturating_add(2)),
            );
        }
    }
}
fn compose_project_ids(containers: &[Container], project: &str) -> Vec<String> {
    containers
        .iter()
        .filter(|c| {
            c.labels
                .get("com.docker.compose.project")
                .is_some_and(|v| v == project)
        })
        .map(|c| c.id.clone())
        .collect()
}
fn tab_at(column: u16) -> Option<usize> {
    use unicode_width::UnicodeWidthStr;
    let mut start = 1u16;
    for (index, label) in ["1 容器", "2 镜像", "3 卷", "4 概览", "5 空间"]
        .iter()
        .enumerate()
    {
        let width = label.width() as u16 + 2;
        if (start..start + width).contains(&column) {
            return Some(index);
        }
        start += width + 2;
    }
    None
}
fn api_update_is_current(update_epoch: u64, current_epoch: u64, stopped: bool) -> bool {
    !stopped && update_epoch == current_epoch
}
fn cap_log_buffer(buffer: &mut Vec<u8>, max_bytes: usize) -> bool {
    if buffer.len() > max_bytes {
        buffer.clear();
        true
    } else {
        false
    }
}
fn table_click_index(
    selected: usize,
    visible_rows: usize,
    clicked_row: usize,
    len: usize,
) -> usize {
    if len == 0 || visible_rows == 0 {
        return 0;
    }
    let offset = selected.saturating_add(1).saturating_sub(visible_rows);
    offset.saturating_add(clicked_row).min(len - 1)
}
fn stopped_key_allowed(code: KeyCode) -> bool {
    matches!(
        code,
        KeyCode::Char('q' | '?' | '1' | '2' | '3' | '4' | '5' | 's' | 'j' | 'k' | 'o' | '/')
            | KeyCode::Esc
            | KeyCode::Up
            | KeyCode::Down
            | KeyCode::Left
            | KeyCode::Right
    )
}
#[cfg(test)]
#[allow(clippy::items_after_test_module)]
mod stop_policy_tests {
    use super::*;
    use crossterm::event::KeyModifiers;

    fn test_app() -> App {
        App::new(Some("unix:///tmp/docker-tui-test.sock".into())).unwrap()
    }

    fn key(ch: char) -> KeyEvent {
        KeyEvent::new(KeyCode::Char(ch), KeyModifiers::NONE)
    }

    #[test]
    fn filtering_images_is_incremental_and_keeps_stable_ids() {
        let mut app = test_app();
        app.page = Page::Images;
        app.online = true;
        app.images = vec![
            serde_json::from_value(serde_json::json!({"Id":"a","RepoTags":["北京 Apple"]}))
                .unwrap(),
            serde_json::from_value(serde_json::json!({"Id":"b","RepoTags":["香港 Apple"]}))
                .unwrap(),
        ];
        app.selected = 1;
        app.key(key('/'));
        app.paste("apple");
        assert_eq!(app.selected_id().as_deref(), Some("b"));
        app.key(KeyEvent::new(KeyCode::Up, KeyModifiers::NONE));
        assert_eq!(app.selected_id().as_deref(), Some("a"));
        app.paste(" nonexistent");
        assert_eq!(app.len(), 0);
        assert_eq!(app.selected, 0);
        let mut terminal =
            ratatui::Terminal::new(ratatui::backend::TestBackend::new(100, 30)).unwrap();
        terminal.draw(|f| app.draw(f)).unwrap();
        let text = terminal
            .backend()
            .buffer()
            .content
            .iter()
            .map(|c| c.symbol())
            .filter(|s| *s != " ")
            .collect::<String>();
        assert!(text.contains("无匹配项"));
        app.key(KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE));
        assert_eq!(app.len(), 2);
        app.key(key('/'));
        app.paste("xianggang apple");
        assert_eq!(app.selected_id().as_deref(), Some("b"));
        app.key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE));
        app.key(key('/'));
        app.paste(" xyz");
        app.key(KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE));
        assert_eq!(app.filter.as_str(), "xianggang apple");
        app.key(KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE));
        assert_eq!(app.len(), 2);
    }
    #[test]
    fn filtered_log_refresh_preserves_scrolled_record_even_at_buffer_limit() {
        let mut app = test_app();
        app.log_filter.set("keep");
        app.log_lines = (0..4000).map(|i| format!("keep {i}")).collect();
        app.log_follow = false;
        app.log_scroll = 20;
        let anchor = |app: &App| {
            let matcher = Matcher::new(&app.log_filter);
            let rows: Vec<_> = app
                .log_lines
                .iter()
                .filter(|line| matcher.matches(line))
                .collect();
            rows[rows.len() - app.log_scroll - 1].to_owned()
        };
        let before = anchor(&app);
        app.last_refresh = Instant::now();
        app.tx
            .try_send(Update::Log(app.api_epoch, "skip\nkeep 4000".into()))
            .unwrap();
        app.poll();
        assert_eq!(anchor(&app), before);
        assert_eq!(app.log_lines.len(), 4000);
        assert_eq!(app.log_scroll, 21);
    }
    #[tokio::test]
    async fn suspend_keeps_log_view_state_and_cancels_background_jobs() {
        let mut app = test_app();
        app.filter.set("容器");
        app.log_filter.set("apple");
        app.logs = Some("fixture".into());
        app.log_lines = vec!["Apple retained".into()];
        app.log_scroll = 1;
        app.refresh = Some(tokio::spawn(std::future::pending()));
        app.log_job = Some(tokio::spawn(std::future::pending()));
        app.suspend();
        assert!(app.refresh.is_none());
        assert!(app.log_job.is_none());
        app.resume();
        assert_eq!(app.filter.as_str(), "容器");
        assert_eq!(app.log_filter.as_str(), "apple");
        assert_eq!(app.log_lines, vec!["Apple retained"]);
        assert_eq!(app.log_scroll, 1);
        assert!(app.log_job.is_some());
    }
    #[tokio::test]
    async fn vm_jobs_only_exist_while_the_vm_inventory_is_visible() {
        let mut app = test_app();
        app.last_refresh = Instant::now();
        app.tick();
        assert!(app.vm_job.is_none());
        app.page = Page::Cleanup;
        app.vm_section = true;
        app.vm_job = Some(tokio::spawn(std::future::pending()));
        app.key(KeyEvent::new(KeyCode::Tab, KeyModifiers::NONE));
        assert!(app.vm_job.is_none());
        app.vm_section = true;
        app.vm_job = Some(tokio::spawn(std::future::pending()));
        app.key(key('1'));
        assert!(app.vm_job.is_none());
    }
    #[test]
    fn log_capture_has_a_byte_budget_even_for_large_lines() {
        let mut app = test_app();
        app.last_refresh = Instant::now();
        app.tx
            .try_send(Update::Log(app.api_epoch, "x".repeat(5 * 1024 * 1024)))
            .unwrap();
        app.poll();
        assert!(app.log_lines.iter().map(String::len).sum::<usize>() <= 4 * 1024 * 1024);
    }
    #[test]
    fn vm_section_never_enters_docker_cleanup_or_selects_resources() {
        let mut app = test_app();
        app.page = Page::Cleanup;
        app.vm_section = true;
        app.picked.insert("镜像:fixture".into());
        app.key(key(' '));
        app.key(key('d'));
        app.key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE));
        assert!(app.cleanup_flow.is_none());
        assert!(app.confirm.is_none());
        assert!(app.action.is_none());
        assert_eq!(app.picked.len(), 1);
        assert!(app.message.contains("严格只读"));
        app.key(KeyEvent::new(KeyCode::Tab, KeyModifiers::NONE));
        assert!(!app.vm_section);
    }

    #[test]
    fn vm_navigation_and_refresh_work_while_docker_is_suspended() {
        let mut app = test_app();
        app.page = Page::Cleanup;
        app.stopped_by_user = true;
        app.key(KeyEvent::new(KeyCode::Tab, KeyModifiers::NONE));
        assert!(app.vm_section);
        app.key(key('r'));
        assert!(app.last_vm.elapsed() >= Duration::from_secs(30));
        app.key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE));
        assert!(app.refresh.is_none());
        assert!(app.action.is_none());
        assert!(app.stopped_by_user);
    }

    #[test]
    fn suspended_docker_does_not_resume_through_retained_cleanup_selection() {
        let mut app = test_app();
        app.page = Page::Cleanup;
        app.stopped_by_user = true;
        app.picked.insert("镜像:fixture".into());
        app.disk.images.push(
            serde_json::from_value(
                serde_json::json!({"Id":"fixture","Containers":0,"Size":32,"SharedSize":0}),
            )
            .unwrap(),
        );
        app.key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE));
        app.key(key('y'));
        app.key(key('y'));
        assert!(app.cleanup_flow.is_none());
        assert!(app.action.is_none());
        assert!(app.refresh.is_none());
        assert!(app.stopped_by_user);
    }

    #[test]
    fn stopped_daemon_rejects_a_real_action_key() {
        let mut app = test_app();
        app.stopped_by_user = true;
        app.key(key('r'));
        assert!(app.action.is_none());
        assert!(app.message.contains("按 s"));
    }

    #[test]
    fn refresh_snapshot_does_not_replace_recent_action_message() {
        let mut app = test_app();
        app.message = "构建缓存清理完成 · 实际释放 192 MiB".into();
        app.message_until = Some(Instant::now() + Duration::from_secs(5));
        app.last_refresh = Instant::now();
        assert!(app
            .tx
            .try_send(Update::Data(
                app.api_epoch,
                Ok(Data {
                    containers: vec![],
                    images: vec![],
                    volumes: vec![],
                    info: Info {
                        version: "test".into()
                    },
                    disk: Disk {
                        images: vec![],
                        containers: vec![],
                        volumes: vec![],
                        build_cache: vec![],
                        layers_size: 0,
                    },
                }),
            ))
            .is_ok());
        app.poll();
        assert_eq!(app.message, "构建缓存清理完成 · 实际释放 192 MiB");
    }

    #[test]
    fn container_details_preserve_full_image_status_and_bind_ip() {
        let container: Container = serde_json::from_str(
            r#"{"Id":"abc123","Names":["/api"],"Image":"python:3.12-alpine","State":"running","Status":"Up 18 minutes","Ports":[{"IP":"0.0.0.0","PrivatePort":8000,"PublicPort":8080,"Type":"tcp"}]}"#,
        )
        .unwrap();
        let details = container_details(&container);
        assert!(details.contains("python:3.12-alpine"));
        assert!(details.contains("Up 18 minutes (running)"));
        assert!(details.contains("0.0.0.0:8080 → :8000/tcp"));
        use unicode_width::UnicodeWidthStr;
        assert!(compact_port_mappings(&container).width() <= 15);
    }

    #[test]
    fn enter_opens_details_and_details_block_mouse_until_escape() {
        let mut app = test_app();
        app.containers
            .push(serde_json::from_str(r#"{"Id":"abc123","Names":["/api"]}"#).unwrap());
        app.key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE));
        assert!(app.details);
        app.mouse(
            MouseEvent {
                kind: MouseEventKind::Down(crossterm::event::MouseButton::Left),
                column: 14,
                row: 1,
                modifiers: KeyModifiers::NONE,
            },
            ratatui::layout::Size::new(90, 30),
        );
        assert!(matches!(app.page, Page::Containers));
        app.key(KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE));
        assert!(!app.details);
    }

    #[test]
    fn stop_allows_navigation_but_blocks_daemon_requests() {
        for key in [
            KeyCode::Char('q'),
            KeyCode::Char('?'),
            KeyCode::Char('1'),
            KeyCode::Char('s'),
            KeyCode::Char('j'),
            KeyCode::Char('/'),
            KeyCode::Esc,
            KeyCode::Down,
        ] {
            assert!(stopped_key_allowed(key));
        }
        for key in [
            KeyCode::Char('r'),
            KeyCode::Char('p'),
            KeyCode::Char('l'),
            KeyCode::Char('e'),
            KeyCode::Char('d'),
            KeyCode::Char('c'),
            KeyCode::Char('b'),
            KeyCode::Char('S'),
        ] {
            assert!(!stopped_key_allowed(key));
        }
    }
    #[test]
    fn tabs_follow_rendered_unicode_cell_widths() {
        assert_eq!(tab_at(2), Some(0));
        assert_eq!(tab_at(14), Some(1));
        assert_eq!(tab_at(26), Some(2));
        assert_eq!(tab_at(34), Some(3));
    }
    #[test]
    fn table_click_uses_the_scroll_offset_for_long_lists() {
        assert_eq!(table_click_index(0, 10, 7, 30), 7);
        assert_eq!(table_click_index(19, 10, 4, 30), 14);
        assert_eq!(table_click_index(29, 10, 9, 30), 29);
    }
    #[test]
    fn long_log_fragments_are_bounded_and_cleared() {
        let mut buffer = vec![b'x'; 8];
        assert!(!cap_log_buffer(&mut buffer, 8));
        buffer.push(b'x');
        assert!(cap_log_buffer(&mut buffer, 8));
        assert!(buffer.is_empty());
    }
    #[test]
    fn compose_restart_targets_every_container_in_only_that_project() {
        let a = Container {
            id: "a".into(),
            labels: HashMap::from([("com.docker.compose.project".into(), "alpha".into())]),
            ..serde_json::from_str(r#"{"Id":"a"}"#).unwrap()
        };
        let b = Container {
            id: "b".into(),
            labels: HashMap::from([("com.docker.compose.project".into(), "alpha".into())]),
            ..serde_json::from_str(r#"{"Id":"b"}"#).unwrap()
        };
        let c = Container {
            id: "c".into(),
            labels: HashMap::from([("com.docker.compose.project".into(), "beta".into())]),
            ..serde_json::from_str(r#"{"Id":"c"}"#).unwrap()
        };
        assert_eq!(compose_project_ids(&[a, b, c], "alpha"), ["a", "b"]);
    }
    #[test]
    fn stale_api_updates_stay_discarded_after_reconnect() {
        assert!(!api_update_is_current(4, 5, false));
        assert!(!api_update_is_current(5, 5, true));
        assert!(api_update_is_current(5, 5, false));
    }
}
fn container_details(c: &Container) -> String {
    let name = c
        .names
        .first()
        .map(|name| name.trim_start_matches('/'))
        .unwrap_or(&c.id);
    let project = c
        .labels
        .get("com.docker.compose.project")
        .map(String::as_str)
        .unwrap_or("-");
    let ports = if c.ports.is_empty() {
        "无".to_owned()
    } else {
        c.ports
            .iter()
            .map(|p| match p.public {
                Some(host_port) => format!(
                    "{}:{} → :{}/{}",
                    p.ip.as_deref().unwrap_or("*"),
                    host_port,
                    p.private,
                    p.kind
                ),
                None => format!("未发布 → :{}/{}", p.private, p.kind),
            })
            .collect::<Vec<_>>()
            .join("\n")
    };
    format!("名称：{name}\nID：{}\nCompose 项目：{project}\n镜像：{}\n状态：{} ({})\n端口映射：\n{ports}", c.id, c.image, c.status, c.state)
}
fn compact_port_mappings(c: &Container) -> String {
    c.ports
        .iter()
        .filter_map(|p| {
            p.public
                .map(|host_port| format!("{host_port}>{}/{}", p.private, p.kind))
        })
        .collect::<Vec<_>>()
        .join(",")
}
fn confirm_body(confirm: &Confirm) -> String {
    match confirm {
        Confirm::ProjectRestart(name, ids) => {
            format!(
                "重启 Compose 项目 {name} 中的 {} 个容器？\ny 确认 · Esc 取消",
                ids.len()
            )
        }
        Confirm::StopDaemon => {
            "停止 Docker daemon 与 socket proxy？\n下次 Docker 请求会自动启动。\ny 确认 · Esc 取消"
                .into()
        }
    }
}
fn short(s: &str) -> &str {
    if s.len() > 12 {
        &s[..12]
    } else {
        s
    }
}

impl Drop for App {
    fn drop(&mut self) {
        if let Some(job) = self.vm_job.take() {
            job.abort();
        }
        if let Some(job) = self.refresh.take() {
            job.abort();
        }
        if let Some(job) = self.log_job.take() {
            job.abort();
        }
        if let Some(job) = self.action.take() {
            job.abort();
        }
        if let Some(job) = self.exec_job.take() {
            job.abort();
        }
        self.stats_jobs.abort_all();
    }
}

fn compact_status(status: &str) -> String {
    let mut value = status.to_string();
    for (from, to) in [
        (" seconds", "s"),
        (" second", "s"),
        (" minutes", "m"),
        (" minute", "m"),
        (" hours", "h"),
        (" hour", "h"),
        (" days", "d"),
        (" day", "d"),
        (" weeks", "w"),
        (" week", "w"),
        (" months", "mo"),
        (" month", "mo"),
        (" ago", ""),
        ("Exited", "Exit"),
    ] {
        value = value.replace(from, to);
    }
    value
}
