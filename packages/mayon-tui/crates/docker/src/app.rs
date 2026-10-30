use crate::api::{
    drain_log_frames, drain_raw_log_lines, Container, Disk, Engine, Image, Info, StatView, Volume,
};
use crossterm::event::{KeyCode, KeyEvent, MouseEvent, MouseEventKind};
use futures_util::StreamExt;
use mayon_ui::{self as ui, theme::*};
use ratatui::{
    layout::Constraint,
    style::Style,
    text::{Line, Span},
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
}
#[derive(Clone)]
enum Confirm {
    Container(String),
    Image(String),
    Volume(String, u8),
    PruneImages(u64),
    PruneBuild(u64),
    StopDaemon,
    ProjectRestart(String, Vec<String>),
}
enum Update {
    Data(u64, Result<Data, String>),
    Stats(u64, String, Result<StatView, String>),
    Message(String),
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
    filter: String,
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
    confirm: Option<Confirm>,
    help: bool,
    details: bool,
    logs: Option<String>,
    log_lines: Vec<String>,
    log_filter: String,
    log_scroll: usize,
    log_follow: bool,
    log_job: Option<JoinHandle<()>>,
    tx: mpsc::Sender<Update>,
    rx: mpsc::Receiver<Update>,
    refresh: Option<JoinHandle<()>>,
    last_refresh: Instant,
    action: Option<JoinHandle<()>>,
    exec_job: Option<JoinHandle<()>>,
    stopped_by_user: bool,
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
            filter: String::new(),
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
            confirm: None,
            help: false,
            details: false,
            logs: None,
            log_lines: vec![],
            log_filter: String::new(),
            log_scroll: 0,
            log_follow: true,
            log_job: None,
            tx,
            rx,
            refresh: None,
            last_refresh: Instant::now() - Duration::from_secs(5),
            action: None,
            exec_job: None,
            stopped_by_user: false,
        })
    }
    fn selected_container(&self) -> Option<&Container> {
        self.filtered_containers().get(self.selected).copied()
    }
    fn filtered_containers(&self) -> Vec<&Container> {
        let q = self.filter.to_lowercase();
        let mut xs: Vec<_> = self
            .containers
            .iter()
            .filter(|c| {
                let n = c.names.first().map(String::as_str).unwrap_or(&c.id);
                format!(
                    "{n} {} {}",
                    c.image,
                    c.labels
                        .get("com.docker.compose.project")
                        .map(String::as_str)
                        .unwrap_or("")
                )
                .to_lowercase()
                .contains(&q)
            })
            .collect();
        if self.sort == 1 {
            xs.sort_by(|a, b| a.image.cmp(&b.image))
        } else if self.sort == 2 {
            xs.sort_by(|a, b| a.status.cmp(&b.status))
        }
        xs
    }
    fn selected_id(&self) -> Option<String> {
        match self.page {
            Page::Containers => self.selected_container().map(|c| c.id.clone()),
            Page::Images => self.images.get(self.selected).map(|x| x.id.clone()),
            Page::Volumes => self.volumes.get(self.selected).map(|x| x.name.clone()),
            Page::Overview => None,
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
        while let Ok(u) = self.rx.try_recv() {
            match u {
                Update::Data(epoch, Ok(d))
                    if api_update_is_current(epoch, self.api_epoch, self.stopped_by_user) =>
                {
                    let keep = self.selected_id();
                    self.online = true;
                    if !self.has_temporary_message() {
                        self.message = format!(
                            "{} 容器 · {} 镜像 · {} 卷",
                            d.containers.len(),
                            d.images.len(),
                            d.volumes.len()
                        );
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
                Update::Data(epoch, Err(_))
                    if api_update_is_current(epoch, self.api_epoch, self.stopped_by_user)
                        && !self.has_temporary_message() =>
                {
                    if !self.online {
                        self.message = "Docker 启动中…".into()
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
                Update::Message(m) => {
                    self.message = m;
                    self.message_until = Some(Instant::now() + Duration::from_secs(5));
                    self.last_refresh = Instant::now() - Duration::from_secs(3)
                }
                Update::Log(epoch, s)
                    if api_update_is_current(epoch, self.api_epoch, self.stopped_by_user) =>
                {
                    self.log_lines.extend(s.lines().map(str::to_owned));
                    if self.log_lines.len() > 4000 {
                        self.log_lines.drain(..self.log_lines.len() - 4000);
                    }
                    if self.log_follow {
                        self.log_scroll = 0;
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
            Page::Images => self.images.len(),
            Page::Volumes => self.volumes.len(),
            Page::Overview => 0,
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
            Page::Images => self.images.iter().map(|x| x.id.clone()).collect(),
            Page::Volumes => self.volumes.iter().map(|x| x.name.clone()).collect(),
            Page::Overview => vec![],
        }
    }
    fn move_sel(&mut self, d: i32) {
        let n = self.len();
        if n > 0 {
            self.selected = if d < 0 {
                self.selected.saturating_sub(1)
            } else {
                (self.selected + 1).min(n - 1)
            }
        }
    }
    fn start_logs(&mut self) {
        let Some(c) = self.selected_container().cloned() else {
            return;
        };
        let id = c.id.clone();
        let display = c.names.first().cloned().unwrap_or_else(|| id.clone());
        let e = self.engine.clone();
        let tx = self.tx.clone();
        self.log_lines.clear();
        self.logs = Some(id.clone());
        self.log_filter.clear();
        self.message = format!("正在跟随 {display} 日志");
        self.log_follow = true;
        self.log_scroll = 0;
        if let Some(job) = self.log_job.take() {
            job.abort();
        }
        let epoch = self.api_epoch;
        self.log_job = Some(tokio::spawn(async move {
            let result = async {
                let (r, tty) = e.logs(&id).await?;
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
            Confirm::Container(id) => {
                let e = self.engine.clone();
                self.command(async move { e.remove_container(&id).await })
            }
            Confirm::Image(id) => {
                let e = self.engine.clone();
                self.command(async move { e.remove_image(&id).await })
            }
            Confirm::Volume(n, k) => {
                if !crate::api::volume_delete_confirmed(k + 1) {
                    self.confirm = Some(Confirm::Volume(n.clone(), 1));
                    self.message = format!("再次确认删除卷 {n}：按 y 删除，Esc 取消");
                } else {
                    let e = self.engine.clone();
                    self.command(async move { e.remove_volume(&n).await })
                }
            }
            Confirm::PruneImages(_) => {
                let e = self.engine.clone();
                self.command(async move {
                    let result = e.prune_images().await?;
                    let reclaimed = result
                        .get("SpaceReclaimed")
                        .and_then(serde_json::Value::as_u64)
                        .unwrap_or(0);
                    Err(format!(
                        "悬空镜像清理完成 · 实际释放 {}",
                        ui::theme::bytes(reclaimed)
                    ))
                })
            }
            Confirm::PruneBuild(_) => {
                let e = self.engine.clone();
                self.command(async move {
                    let result = e.prune_build().await?;
                    let reclaimed = result
                        .get("SpaceReclaimed")
                        .and_then(serde_json::Value::as_u64)
                        .unwrap_or(0);
                    Err(format!(
                        "构建缓存清理完成 · 实际释放 {}",
                        ui::theme::bytes(reclaimed)
                    ))
                })
            }
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
        if let Some(Confirm::Volume(n, count)) = self.confirm.clone() {
            match k.code {
                KeyCode::Esc | KeyCode::Char('n') => {
                    self.confirm = None;
                    return;
                }
                KeyCode::Char('y') => {
                    self.confirm = Some(Confirm::Volume(n, count));
                    self.confirm_action();
                    return;
                }
                _ => return,
            }
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
            match k.code {
                KeyCode::Esc => {
                    if self.logs.is_some() {
                        self.log_filter.clear();
                    } else {
                        self.filter.clear();
                    }
                    self.filtering = false;
                    self.selected = 0
                }
                KeyCode::Enter => self.filtering = false,
                KeyCode::Backspace => {
                    if self.logs.is_some() {
                        self.log_filter.pop();
                    } else {
                        self.filter.pop();
                    }
                    self.selected = 0
                }
                KeyCode::Char(c) if !c.is_control() => {
                    if self.logs.is_some() {
                        self.log_filter.push(c);
                    } else {
                        self.filter.push(c);
                    }
                    self.selected = 0
                }
                _ => {}
            }
            return;
        }
        if self.details {
            if k.code == KeyCode::Esc {
                self.details = false;
            }
            return;
        }
        if self.stopped_by_user && !stopped_key_allowed(k.code) {
            self.message = "Docker daemon 已手动停止；按 s 重新连接".into();
            return;
        }
        if self.logs.is_some() {
            match k.code {
                KeyCode::Esc | KeyCode::Char('q') => {
                    self.logs = None;
                    if let Some(job) = self.log_job.take() {
                        job.abort();
                    }
                }
                KeyCode::Char('j') | KeyCode::Down => {
                    self.log_follow = true;
                    self.log_scroll = 0;
                }
                KeyCode::Char('k') | KeyCode::Up => {
                    self.log_follow = false;
                    self.log_scroll =
                        (self.log_scroll + 1).min(self.log_lines.len().saturating_sub(1));
                }
                KeyCode::Char('G') => {
                    self.log_follow = true;
                    self.log_scroll = 0;
                }
                KeyCode::Char('/') => self.filtering = true,
                _ => {}
            }
            return;
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
            KeyCode::Char('j') | KeyCode::Down => self.move_sel(1),
            KeyCode::Char('k') | KeyCode::Up => self.move_sel(-1),
            KeyCode::Char('/') => self.filtering = true,
            KeyCode::Char('o') => {
                self.sort = (self.sort + 1) % 3;
                self.selected = 0;
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
            KeyCode::Char('d') if self.page == Page::Containers => {
                if let Some(c) = self.selected_container() {
                    self.confirm = Some(Confirm::Container(c.id.clone()))
                }
            }
            KeyCode::Char('d') if self.page == Page::Images => {
                if let Some(i) = self.images.get(self.selected) {
                    self.confirm = Some(Confirm::Image(i.id.clone()))
                }
            }
            KeyCode::Char('d') if self.page == Page::Volumes => {
                if let Some(v) = self.volumes.get(self.selected) {
                    self.confirm = Some(Confirm::Volume(v.name.clone(), 0))
                }
            }
            KeyCode::Char('c') if self.page == Page::Overview => {
                let dangling = self
                    .disk
                    .images
                    .iter()
                    .filter(|i| crate::api::is_dangling(&i.tags))
                    .map(|i| i.size.saturating_sub(i.shared))
                    .sum();
                self.confirm = Some(Confirm::PruneImages(dangling))
            }
            KeyCode::Char('b') if self.page == Page::Overview => {
                let size = crate::api::reclaimable_build_cache(&self.disk.build_cache);
                self.confirm = Some(Confirm::PruneBuild(size))
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
        self.action_key(k)
    }
    pub fn mouse(&mut self, m: MouseEvent, size: ratatui::layout::Size) {
        if self.confirm.is_some() || self.help || self.details || self.filtering {
            return;
        }
        match m.kind {
            MouseEventKind::ScrollDown => {
                if self.logs.is_some() {
                    self.log_scroll = self.log_scroll.saturating_sub(3);
                    self.log_follow = self.log_scroll == 0;
                } else {
                    self.move_sel(1);
                }
            }
            MouseEventKind::ScrollUp => {
                if self.logs.is_some() {
                    self.log_scroll =
                        (self.log_scroll + 3).min(self.log_lines.len().saturating_sub(1));
                    self.log_follow = false;
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
                            _ => Page::Overview,
                        };
                        self.selected = 0
                    }
                } else if m.row >= 5 {
                    let visible_rows = size.height.saturating_sub(8) as usize;
                    let visible_row = m.row as usize - 5;
                    self.selected =
                        table_click_index(self.selected, visible_rows, visible_row, self.len());
                }
            }
            _ => {}
        }
    }
    pub fn tick(&mut self) {
        self.poll()
    }
    pub fn draw(&mut self, f: &mut Frame) {
        let (title, tabs, page) = (
            format!(
                " 󰡨 Docker  ·  {}  ·  {}",
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
            ["容器", "镜像", "卷", "概览"],
            match self.page {
                Page::Containers => 0,
                Page::Images => 1,
                Page::Volumes => 2,
                Page::Overview => 3,
            },
        );
        let hint = if self.logs.is_some() {
            "j/k 滚动  G 跟随  / 过滤  Esc 返回"
        } else {
            "o 排序  j/k 选择  Enter 详情  1-4 页签  / 过滤  s 启停  r 单重启  p 项目启停  R 项目重启  l 日志  e exec  d 删除  ? 帮助"
        };
        let area = ui::chrome(f, &title, &tabs, page, hint, &self.message);
        if self.logs.is_some() {
            self.draw_logs(f, area);
            return;
        }
        match self.page {
            Page::Containers => self.draw_containers(f, area),
            Page::Images => self.draw_images(f, area),
            Page::Volumes => self.draw_volumes(f, area),
            Page::Overview => self.draw_overview(f, area),
        }
        if self.help {
            ui::help(
                f,
                "1-4 切页 · j/k 或方向键选择 · / 过滤\nEnter 查看容器完整镜像、状态与 IP 端口详情\ns 启动/停止容器 · r 单容器重启 · p 项目启停 · R 重启整个 Compose 项目\nl 跟随日志 · 日志内 j/k 滚动 / 过滤\ne 在新 Kitty 中进入容器 · d 删除并确认\n卷删除需输入两次 y，显示名称且永不自动清理\n概览 c 清理悬空镜像 · b 清理构建缓存\nS 停止 Docker 与代理服务 · s 恢复连接\nq 退出 · ? 关闭帮助",
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
        ui::table(
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
    fn draw_images(&self, f: &mut Frame, a: ratatui::layout::Rect) {
        let rows = self
            .images
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
        ui::table(
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
            .volumes
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
                        .map(|u| if u.refs > 0 { "使用中" } else { "未使用" })
                        .unwrap_or("未知")
                        .into(),
                ]
            })
            .collect();
        ui::table(
            f,
            a,
            &format!(" 卷 {}  · d 删除需二次确认 ", self.volumes.len()),
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
    fn draw_overview(&self, f: &mut Frame, a: ratatui::layout::Rect) {
        let build_reclaimable = crate::api::reclaimable_build_cache(&self.disk.build_cache);
        let build_total = self
            .disk
            .build_cache
            .iter()
            .map(|entry| entry.size)
            .sum::<u64>();
        let dangling = self
            .disk
            .images
            .iter()
            .filter(|i| crate::api::is_dangling(&i.tags))
            .map(|i| i.size.saturating_sub(i.shared))
            .sum::<u64>();
        let body = format!(
            "Docker Engine {}\n\n容器：{}  ·  镜像：{}  ·  卷：{}\n镜像层：{}\n\n悬空镜像：{}（c 清理，预计释放 {}）\n构建缓存：{}（预计可回收 {}；b 清理）\n\nS 停止 daemon + docker-proxy\n确认后，下次连接会按需启动。",
            self.info.version,
            self.disk.containers.len(),
            self.disk.images.len(),
            self.disk.volumes.len(),
            ui::theme::bytes(self.disk.layers_size),
            self.disk
                .images
                .iter()
                .filter(|i| crate::api::is_dangling(&i.tags))
                .count(),
            ui::theme::bytes(dangling),
            ui::theme::bytes(build_total),
            ui::theme::bytes(build_reclaimable)
        );
        f.render_widget(
            Paragraph::new(body)
                .style(ui::base())
                .block(ui::block(" Docker Engine 概览 ", true))
                .wrap(Wrap { trim: false }),
            a,
        )
    }
    fn draw_logs(&self, f: &mut Frame, a: ratatui::layout::Rect) {
        let q = self.log_filter.to_lowercase();
        let visible: Vec<_> = self
            .log_lines
            .iter()
            .filter(|s| s.to_lowercase().contains(&q))
            .collect();
        let end = visible.len().saturating_sub(self.log_scroll);
        let start = end.saturating_sub((a.height as usize).saturating_sub(2));
        let body = visible
            .iter()
            .skip(start)
            .take(end - start)
            .map(|s| {
                Line::from(Span::styled(
                    ui::theme::clip(s, (a.width as usize).saturating_sub(2)),
                    Style::default().fg(FG),
                ))
            })
            .collect::<Vec<_>>();
        f.render_widget(
            Paragraph::new(body)
                .style(ui::base())
                .block(ui::block(
                    format!(
                        " 实时日志 · {} · /{} ",
                        self.logs.as_deref().map(short).unwrap_or(""),
                        self.log_filter
                    ),
                    true,
                ))
                .wrap(Wrap { trim: false }),
            a,
        )
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
    for (index, label) in ["1 容器", "2 镜像", "3 卷", "4 概览"].iter().enumerate() {
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
        KeyCode::Char('q' | '?' | '1' | '2' | '3' | '4' | 's' | 'j' | 'k' | 'o' | '/')
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
    fn stopped_daemon_rejects_a_real_action_key() {
        let mut app = test_app();
        app.stopped_by_user = true;
        app.key(key('r'));
        assert!(app.action.is_none());
        assert!(app.message.contains("按 s"));
    }

    #[test]
    fn volume_confirmation_requires_a_second_y_and_escape_cancels() {
        let mut app = test_app();
        app.confirm = Some(Confirm::Volume("fixture-data".into(), 0));
        assert!(confirm_body(app.confirm.as_ref().unwrap()).contains("第一次 y"));
        app.key(key('y'));
        assert!(
            matches!(app.confirm, Some(Confirm::Volume(ref name, 1)) if name == "fixture-data")
        );
        let second_stage = confirm_body(app.confirm.as_ref().unwrap());
        assert!(second_stage.contains("二次确认"));
        assert!(second_stage.contains("fixture-data"));
        assert!(second_stage.contains("再次 y 永久删除 · Esc 取消"));
        app.key(KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE));
        assert!(app.confirm.is_none());
        assert!(app.action.is_none());
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
        Confirm::Container(id) => format!(
            "删除容器 {}？容器 writable layer 也会删除。\ny 确认 · Esc 取消",
            short(id)
        ),
        Confirm::Image(id) => format!("删除镜像 {}？\ny 确认 · Esc 取消", short(id)),
        Confirm::Volume(name, 0) => {
            format!("删除卷 {name} 会永久删除卷内数据。\n第一次 y：继续到二次确认。")
        }
        Confirm::Volume(name, _) => {
            format!("二次确认：永久删除卷 {name}？\n再次 y 永久删除 · Esc 取消")
        }
        Confirm::PruneImages(size) => format!(
            "清理悬空镜像，预计释放 {}？\ny 确认 · Esc 取消",
            ui::theme::bytes(*size)
        ),
        Confirm::PruneBuild(size) => format!(
            "清理构建缓存，预计释放 {}？\ny 确认 · Esc 取消",
            ui::theme::bytes(*size)
        ),
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
