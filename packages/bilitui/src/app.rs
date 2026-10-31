use crate::{
    api::Api,
    media::{self, Download, Progress},
    model::{self, Video},
    store::{self, Config},
};
use anyhow::{bail, Context, Result};
use base64::Engine;
use crossterm::event::{
    self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers, MouseEventKind,
};
use futures_util::StreamExt;
use mayon_ui::{
    self as ui,
    input::TextInput,
    search::{Matcher, SearchCache},
    theme::*,
};
use ratatui::{
    layout::{Constraint, Layout, Rect},
    style::Style,
    text::{Line, Span},
    widgets::{Block, Paragraph, Wrap},
    Frame,
};
use serde_json::Value;
use std::{
    collections::HashMap,
    io::{self, Cursor as IoCursor, Write},
    time::Duration,
};
use tokio::sync::mpsc;

const TABS: [&str; 9] = [
    "推荐", "热门", "排行", "动态", "搜索", "收藏", "稍后", "历史", "下载",
];
const HELP:&str="1–9 切页 · j/k / ↑↓ / 滚轮 移动 · Enter 详情 / 打开 UP / 收藏夹\np 播放 · [ / ] 分 P · Q 清晰度（0 最高可用） · r 相关推荐\nu UP 投稿 · g 合集 · n / N 下一页 / 上一页 · R 刷新\ns 搜索 · Tab 切换视频/UP · / 本地过滤 · Esc 返回/清除过滤\nl 点赞 · c 投币（确认后投 1 枚） · f 选择收藏夹 · w 稍后再看\nv 下载视频 · a 下载音频 · A 下载当前视频全部分 P · G 下载合集\ny 复制链接（OSC52） · d 下次播放弹幕开关 · h 历史回报开关\nL 扫码登录（Esc 取消） · ? 帮助 · q 退出\n搜索输入：↑↓ 选历史/建议 · Tab 获取建议（单次请求）\n下载串行执行；退出会取消未完成任务，不覆盖已有文件。";
#[derive(Clone)]
struct Folder {
    id: u64,
    title: String,
    count: u64,
}
enum Message {
    Page(Vec<Video>, String),
    CursorPage {
        page: usize,
        pn: u64,
        list: Vec<Video>,
        title: String,
        next: Option<Cursor>,
    },
    Read(u64, Box<Message>),
    Detail(Box<Video>, Vec<Video>),
    Folders(Vec<Folder>, bool, Option<Video>),
    Cover(String, Vec<u8>),
    Qr(String, String),
    Login(String),
    Suggestions(Vec<String>),
    Notice(String),
    Error(String),
}
#[derive(Clone, Debug, Default)]
struct Cursor {
    offset: Option<String>,
    max: Option<String>,
    view_at: Option<String>,
    business: Option<String>,
}
enum Modal {
    Help,
    Error(String),
    Input {
        kind: InputKind,
        value: TextInput,
        choices: Vec<String>,
        selected: Option<usize>,
    },
    Confirm(Video),
    Favourite(Vec<Folder>, usize, Video),
    Qr {
        key: String,
        art: String,
        status: String,
        last: std::time::Instant,
    },
    Quality(Vec<(u64, String)>, usize),
}
#[derive(Clone, Copy)]
enum InputKind {
    Search,
    Filter,
}
struct QueueItem {
    title: String,
    state: String,
    bytes: u64,
}
pub struct App {
    api: Api,
    config: Config,
    demo: bool,
    page: usize,
    pn: u64,
    list: Vec<Video>,
    selected: usize,
    detail: Option<Video>,
    related: Vec<Video>,
    part: usize,
    quality: u64,
    filter: TextInput,
    filter_before: TextInput,
    filtering: bool,
    search: SearchCache,
    loaded_page: (usize, u64),
    query: String,
    up_search: bool,
    heading: String,
    notice: String,
    notice_display: ui::Notice,
    last_notice: String,
    loading: bool,
    error: Option<String>,
    modal: Option<Modal>,
    tx: mpsc::UnboundedSender<Message>,
    rx: mpsc::UnboundedReceiver<Message>,
    jobs: Vec<tokio::task::JoinHandle<()>>,
    read_job: Option<tokio::task::JoinHandle<()>>,
    cover_job: Option<tokio::task::JoinHandle<()>>,
    focused: bool,
    resume_read: bool,
    download: mpsc::UnboundedSender<Download>,
    progress: mpsc::UnboundedReceiver<Progress>,
    queue: Vec<QueueItem>,
    play_notice: mpsc::UnboundedReceiver<String>,
    play_tx: mpsc::UnboundedSender<String>,
    player: Option<tokio::task::JoinHandle<()>>,
    image: Option<(String, Vec<u8>)>,
    image_requested: String,
    image_rect: Option<Rect>,
    list_rect: Rect,
    list_offset: usize,
    context_mid: Option<u64>,
    context_folder: Option<u64>,
    kitty: bool,
    polling: bool,
    cursors: HashMap<(usize, u64), Cursor>,
    read_generation: u64,
}
impl Drop for App {
    fn drop(&mut self) {
        for job in &self.jobs {
            job.abort();
        }
        if let Some(job) = &self.read_job {
            job.abort();
        }
        if let Some(job) = &self.player {
            job.abort();
        }
        if let Some(job) = &self.cover_job {
            job.abort();
        }
    }
}
impl App {
    pub fn new(api: Api, config: Config, demo: bool, cover: Option<Vec<u8>>) -> Self {
        let (tx, rx) = mpsc::unbounded_channel();
        let (download, job_rx) = mpsc::unbounded_channel();
        let (updates, progress) = mpsc::unbounded_channel();
        let (play_tx, play_notice) = mpsc::unbounded_channel();
        let jobs = if demo {
            vec![]
        } else {
            vec![tokio::spawn(media::download_worker(
                api.clone(),
                job_rx,
                updates,
            ))]
        };
        let list = if demo { demo_videos() } else { Vec::new() };
        let image = cover
            .and_then(|b| encode_image(&b).ok())
            .map(|b| ("demo".into(), b));
        Self {
            api,
            config,
            demo,
            page: 0,
            pn: 1,
            list,
            selected: 0,
            detail: None,
            related: vec![],
            part: 0,
            quality: 0,
            filter: TextInput::default(),
            filter_before: TextInput::default(),
            filtering: false,
            search: SearchCache::default(),
            loaded_page: (0, 1),
            query: String::new(),
            up_search: false,
            heading: "首页推荐".into(),
            notice: if demo {
                "离线样例 · 不访问网络、不读取登录状态".into()
            } else {
                "正在加载…".into()
            },
            notice_display: ui::Notice::default(),
            last_notice: String::new(),
            loading: false,
            error: None,
            modal: None,
            tx,
            rx,
            jobs,
            read_job: None,
            cover_job: None,
            focused: true,
            resume_read: false,
            download,
            progress,
            queue: vec![],
            play_notice,
            play_tx,
            player: None,
            image,
            image_requested: String::new(),
            image_rect: None,
            list_rect: Rect::default(),
            list_offset: 0,
            context_mid: None,
            context_folder: None,
            kitty: std::env::var("TERM").is_ok_and(|s| s.contains("kitty"))
                || std::env::var_os("KITTY_WINDOW_ID").is_some(),
            polling: false,
            cursors: HashMap::new(),
            read_generation: 0,
        }
    }
    pub fn fixture(&mut self, value: Value) {
        self.list = model::videos(&value["list"]);
        self.heading = "热门 · 匿名公开录制".into();
        if let Some((url, _)) = &mut self.image {
            *url = self
                .list
                .first()
                .map(|v| v.cover.clone())
                .unwrap_or_default();
        }
    }
    fn request(
        &mut self,
        future: impl std::future::Future<Output = Result<Message>> + Send + 'static,
    ) {
        self.cancel_read();
        let generation = self.read_generation;
        let tx = self.tx.clone();
        self.notice = "加载中…".into();
        self.loading = true;
        self.error = None;
        self.read_job = Some(tokio::spawn(async move {
            let result = match future.await {
                Ok(v) => v,
                Err(e) => Message::Error(e.to_string()),
            };
            let _ = tx.send(Message::Read(generation, Box::new(result)));
        }));
    }
    fn cancel_read(&mut self) {
        self.read_generation = self.read_generation.wrapping_add(1);
        if let Some(job) = self.read_job.take() {
            job.abort();
        }
    }
    fn independent(
        &mut self,
        future: impl std::future::Future<Output = Result<Message>> + Send + 'static,
    ) {
        let tx = self.tx.clone();
        self.jobs.retain(|j| !j.is_finished());
        self.jobs.push(tokio::spawn(async move {
            let result = match future.await {
                Ok(v) => v,
                Err(e) => Message::Error(e.to_string()),
            };
            let _ = tx.send(result);
        }));
    }
    fn current(&self) -> Option<Video> {
        let video = self.filtered().get(self.selected).cloned().cloned()?;
        if let Some(detail) = &self.detail {
            if detail.bvid == video.bvid {
                return Some(detail.clone());
            }
        }
        Some(video)
    }
    fn filtered(&self) -> Vec<&Video> {
        let matcher = Matcher::new(&self.filter);
        let mut matches: Vec<_> = self
            .list
            .iter()
            .filter_map(|v| {
                self.search
                    .find(&matcher, &format!("{} {} {}", v.title, v.up, v.bvid))
                    .map(|hit| (hit.score, v))
            })
            .collect();
        if !self.filter.is_empty() {
            matches.sort_by_key(|(score, _)| std::cmp::Reverse(*score));
        }
        matches.into_iter().map(|(_, video)| video).collect()
    }
    fn filtered_queue(&self) -> Vec<usize> {
        let matcher = Matcher::new(&self.filter);
        self.queue
            .iter()
            .enumerate()
            .filter(|(_, q)| {
                self.search
                    .matches(&matcher, &format!("{} {}", q.title, q.state))
            })
            .map(|(i, _)| i)
            .collect()
    }
    fn selected_key(&self) -> Option<String> {
        if self.page == 8 {
            self.filtered_queue()
                .get(self.selected)
                .map(|id| format!("download:{id}"))
        } else {
            self.filtered().get(self.selected).map(|v| video_key(v))
        }
    }
    fn keep_selection(&mut self, key: Option<String>) {
        self.selected = if self.page == 8 {
            key.and_then(|key| {
                self.filtered_queue()
                    .iter()
                    .position(|id| format!("download:{id}") == key)
            })
            .unwrap_or(0)
        } else {
            key.and_then(|key| self.filtered().iter().position(|v| video_key(v) == key))
                .unwrap_or(0)
        };
        self.detail = self
            .detail
            .take()
            .filter(|v| self.selected_key().as_deref() == Some(video_key(v).as_str()));
    }
    fn replace_list(&mut self, list: Vec<Video>, title: String) {
        let keep = (self.loaded_page == (self.page, self.pn))
            .then(|| self.selected_key())
            .flatten();
        self.list = list;
        self.heading = title;
        self.loaded_page = (self.page, self.pn);
        self.keep_selection(keep);
        self.detail = None;
    }
    fn paste(&mut self, text: &str) {
        if let Some(Modal::Input {
            value, selected, ..
        }) = &mut self.modal
        {
            value.paste(text);
            *selected = None;
        } else if self.filtering {
            let keep = self.selected_key();
            self.filter.paste(text);
            self.keep_selection(keep);
        }
    }
    fn require_login(&mut self) -> bool {
        if self.demo {
            self.notice = "离线样例不会执行操作".into();
            false
        } else if !self.api.logged_in() {
            self.notice = "此页面/操作需要登录；L 扫码，Esc 返回公开页面".into();
            false
        } else {
            true
        }
    }
    fn refresh(&mut self) {
        if self.demo {
            self.notice = "离线样例 · 使用真实终端与 Kitty 图形协议".into();
            return;
        }
        if [3, 5, 6, 7].contains(&self.page) && !self.require_login() {
            self.cancel_read();
            self.list.clear();
            return;
        }
        if self.page == 8 {
            self.cancel_read();
            return;
        }
        let api = self.api.clone();
        let page = self.page;
        let pn = self.pn;
        let query = self.query.clone();
        let up = self.up_search;
        let mid = self.context_mid;
        let folder = self.context_folder;
        let cursor = self.cursors.get(&(page, pn)).cloned().unwrap_or_default();
        self.request(async move {
            load(
                &api,
                LoadRequest {
                    page,
                    pn,
                    query,
                    up,
                    mid,
                    folder,
                    cursor,
                },
            )
            .await
        });
    }
    fn select(&mut self, delta: isize) {
        let len = if self.page == 8 {
            self.filtered_queue().len()
        } else {
            self.filtered().len()
        };
        if len > 0 {
            self.selected = (self.selected as isize + delta).clamp(0, len as isize - 1) as usize;
            self.detail = None;
            self.part = 0;
        }
    }
    fn detail(&mut self) {
        let Some(video) = self.current() else { return };
        if let Some(id) = video
            .bvid
            .strip_prefix("folder:")
            .and_then(|s| s.parse().ok())
        {
            self.context_folder = Some(id);
            self.pn = 1;
            self.refresh();
            return;
        }
        if video.bvid.is_empty() {
            self.context_mid = Some(video.mid);
            self.pn = 1;
            self.refresh();
            return;
        }
        if self.demo {
            self.related = demo_videos();
            self.detail = Some(video);
            return;
        }
        let api = self.api.clone();
        self.request(async move {
            let value = api
                .get("/x/web-interface/view", &[("bvid", video.bvid.clone())])
                .await?;
            let detail = Video::parse(&value);
            let related = api
                .get("/x/web-interface/archive/related", &[("bvid", video.bvid)])
                .await
                .ok()
                .map(|v| model::videos(&v))
                .unwrap_or_default();
            Ok(Message::Detail(Box::new(detail), related))
        });
    }
    fn play(&mut self) {
        if self.demo {
            self.notice = "离线样例不会启动播放".into();
            return;
        }
        if self.player.as_ref().is_some_and(|p| !p.is_finished()) {
            self.notice = "已有 mpv 播放；关闭该播放器后再启动".into();
            return;
        }
        let Some(video) = self.current() else { return };
        let cid = video.pages.get(self.part).map_or(video.cid, |p| p.cid);
        if cid == 0 {
            self.notice = "先按 Enter 加载视频详情，再按 p".into();
            self.detail();
            return;
        }
        let api = self.api.clone();
        let config = self.config.clone();
        let quality = self.quality;
        let messages = self.play_tx.clone();
        self.player = Some(tokio::spawn(async move {
            if let Err(e) =
                media::play(api, video, cid, quality, config, false, messages.clone()).await
            {
                let _ = messages.send(e.to_string());
            }
        }));
        self.notice = "正在解析播放地址…".into();
    }
    fn enqueue(&mut self, mode: char) {
        if self.demo {
            self.notice = "离线样例不会下载".into();
            return;
        }
        let Some(video) = self.current() else { return };
        if video.cid == 0 && video.pages.is_empty() {
            self.detail();
            self.notice = "先加载详情，再按下载键".into();
            return;
        }
        let entries: Vec<(Video, u64)> = match mode {
            'A' => {
                if video.pages.is_empty() {
                    vec![(video.clone(), video.cid)]
                } else {
                    video.pages.iter().map(|p| (video.clone(), p.cid)).collect()
                }
            }
            'G' => {
                if video.collection.is_empty() {
                    self.notice = "当前视频没有可下载合集".into();
                    return;
                }
                video
                    .collection
                    .iter()
                    .cloned()
                    .map(|v| {
                        let cid = v.cid;
                        (v, cid)
                    })
                    .collect()
            }
            _ => vec![(
                video.clone(),
                video.pages.get(self.part).map_or(video.cid, |p| p.cid),
            )],
        };
        for (video, cid) in entries.into_iter().take(500) {
            let id = self.queue.len();
            self.queue.push(QueueItem {
                title: format!(
                    "{} · CID{cid}{}",
                    video.title,
                    if mode == 'a' { " · 音频" } else { "" }
                ),
                state: "等待中".into(),
                bytes: 0,
            });
            let _ = self.download.send(Download {
                id,
                video,
                cid,
                quality: self.quality,
                audio_only: mode == 'a',
                directory: self.config.download_dir.clone(),
            });
        }
        self.notice = "已加入下载队列 · 9 查看".into();
    }
    fn action(&mut self, key: char) {
        if !self.require_login() {
            return;
        }
        let Some(video) = self.current() else { return };
        if video.aid == 0 {
            self.notice = "请先 Enter 载入视频详情".into();
            return;
        }
        if key == 'c' {
            self.modal = Some(Modal::Confirm(video));
            return;
        }
        if key == 'f' {
            let api = self.api.clone();
            let target = video.clone();
            self.request(
                async move { Ok(Message::Folders(folders(&api).await?, true, Some(target))) },
            );
            return;
        }
        let (path, params) = match key {
            'l' => (
                "/x/web-interface/archive/like",
                vec![("aid", video.aid.to_string()), ("like", "1".into())],
            ),
            'w' => (
                "/x/v2/history/toview/add",
                vec![("aid", video.aid.to_string())],
            ),
            _ => return,
        };
        let api = self.api.clone();
        self.independent(async move {
            api.post(path, &params).await?;
            Ok(Message::Notice("操作成功".into()))
        });
    }
    fn quality(&mut self) {
        if self.demo {
            self.modal = Some(Modal::Quality(
                vec![
                    (0, "最高可用".into()),
                    (80, "1080P（需登录）".into()),
                    (64, "720P（需登录）".into()),
                    (16, "360P".into()),
                ],
                0,
            ));
            return;
        }
        let Some(v) = self.current() else { return };
        let cid = v.pages.get(self.part).map_or(v.cid, |p| p.cid);
        if cid == 0 {
            self.detail();
            return;
        }
        let api = self.api.clone();
        let tx = self.tx.clone();
        self.independent(async move {
            let stream = media::resolve(&api, &v, cid, 0).await?;
            let choices = serde_json::to_string(&stream.choices)?;
            let _ = tx.send(Message::Notice(format!("quality:{choices}")));
            Ok(Message::Notice("清晰度只影响下一次播放/下载".into()))
        });
    }
    fn input(&mut self, kind: InputKind) {
        if matches!(kind, InputKind::Filter) {
            self.filter_before = self.filter.clone();
            self.filtering = true;
            return;
        }
        self.modal = Some(Modal::Input {
            kind,
            value: self.query.clone().into(),
            choices: if self.demo {
                vec!["Rust 入门".into(), "终端工作流".into()]
            } else {
                store::history()
            },
            selected: None,
        });
    }
    fn key_modal(&mut self, event: KeyEvent) -> Result<()> {
        let key = event.code;
        let Some(mut modal) = self.modal.take() else {
            return Ok(());
        };
        if matches!(key, KeyCode::Esc) {
            self.cancel_read();
            if matches!(modal, Modal::Qr { .. }) {
                self.polling = false;
            }
            return Ok(());
        }
        if !matches!(modal, Modal::Input { .. })
            && event
                .modifiers
                .intersects(KeyModifiers::CONTROL | KeyModifiers::ALT | KeyModifiers::SUPER)
        {
            self.modal = Some(modal);
            return Ok(());
        }
        let mut keep = true;
        match &mut modal {
            Modal::Error(_) => {
                if matches!(key, KeyCode::Enter | KeyCode::Char('q')) {
                    keep = false;
                }
            }
            Modal::Help => {
                if matches!(key, KeyCode::Char('?') | KeyCode::Char('q')) {
                    keep = false;
                }
            }
            Modal::Input {
                kind,
                value,
                choices,
                selected,
            } => match key {
                KeyCode::Enter => {
                    if let Some(i) = *selected {
                        if let Some(s) = choices.get(i) {
                            value.set(s.clone());
                        }
                    }
                    if matches!(kind, InputKind::Filter) {
                        let key = self.selected_key();
                        self.filter = value.clone();
                        self.keep_selection(key);
                    } else {
                        self.query = value.trim().to_string();
                        self.page = 4;
                        self.pn = 1;
                        self.context_mid = None;
                        self.context_folder = None;
                        if !self.query.is_empty() {
                            if !self.demo {
                                store::add_search(&self.query)?;
                            }
                            self.refresh();
                        }
                    }
                    keep = false;
                }
                KeyCode::Down if !choices.is_empty() => {
                    *selected = Some(selected.map_or(0, |i| (i + 1).min(choices.len() - 1)));
                }
                KeyCode::Up => {
                    *selected = selected.map(|i| i.saturating_sub(1));
                }
                KeyCode::Tab if matches!(kind, InputKind::Search) && !self.demo => {
                    let api = self.api.clone();
                    let query = value.to_string();
                    self.request(
                        async move { Ok(Message::Suggestions(api.suggest(&query).await?)) },
                    );
                }
                _ => {
                    if value.handle_key(event) {
                        *selected = None;
                    }
                }
            },
            Modal::Confirm(video) => {
                if key == KeyCode::Char('y') || key == KeyCode::Enter {
                    let api = self.api.clone();
                    let aid = video.aid;
                    self.independent(async move {
                        api.post(
                            "/x/web-interface/coin/add",
                            &[
                                ("aid", aid.to_string()),
                                ("multiply", "1".into()),
                                ("select_like", "0".into()),
                            ],
                        )
                        .await?;
                        Ok(Message::Notice("已投 1 枚硬币".into()))
                    });
                    keep = false;
                } else if key == KeyCode::Char('n') {
                    keep = false;
                }
            }
            Modal::Favourite(folders, selected, target) => match key {
                KeyCode::Down | KeyCode::Char('j') => {
                    *selected = (*selected + 1).min(folders.len().saturating_sub(1))
                }
                KeyCode::Up | KeyCode::Char('k') => *selected = selected.saturating_sub(1),
                KeyCode::Enter => {
                    if let Some(folder) = folders.get(*selected) {
                        let api = self.api.clone();
                        let id = folder.id;
                        let aid = target.aid;
                        self.independent(async move {
                            api.post(
                                "/x/v3/fav/resource/deal",
                                &[
                                    ("rid", aid.to_string()),
                                    ("type", "2".into()),
                                    ("add_media_ids", id.to_string()),
                                    ("del_media_ids", String::new()),
                                ],
                            )
                            .await?;
                            Ok(Message::Notice("已加入收藏夹".into()))
                        });
                    }
                    keep = false;
                }
                _ => {}
            },
            Modal::Quality(choices, selected) => match key {
                KeyCode::Down | KeyCode::Char('j') => {
                    *selected = (*selected + 1).min(choices.len().saturating_sub(1))
                }
                KeyCode::Up | KeyCode::Char('k') => *selected = selected.saturating_sub(1),
                KeyCode::Enter => {
                    if let Some((quality, _)) = choices.get(*selected) {
                        self.quality = *quality;
                    }
                    keep = false;
                }
                _ => {}
            },
            Modal::Qr { .. } => {}
        }
        if keep {
            self.modal = Some(modal);
        }
        Ok(())
    }
    fn key(&mut self, event: KeyEvent) -> Result<bool> {
        let key = event.code;
        if self.modal.is_some() {
            self.key_modal(event)?;
            return Ok(false);
        }
        if self.filtering {
            let keep = self.selected_key();
            let mut changed = false;
            match key {
                KeyCode::Esc => {
                    self.filter = self.filter_before.clone();
                    self.filtering = false;
                    changed = true;
                }
                KeyCode::Enter => self.filtering = false,
                KeyCode::Down => self.select(1),
                KeyCode::Up => self.select(-1),
                KeyCode::PageDown => self.select(10),
                KeyCode::PageUp => self.select(-10),
                _ => changed = self.filter.handle_key(event),
            }
            if changed {
                self.keep_selection(keep);
            }
            return Ok(false);
        }
        if event
            .modifiers
            .intersects(KeyModifiers::CONTROL | KeyModifiers::ALT | KeyModifiers::SUPER)
        {
            return Ok(false);
        }
        match key {
            KeyCode::Char('q') => return Ok(true),
            KeyCode::Char('?') => self.modal = Some(Modal::Help),
            KeyCode::Char(c @ '1'..='9') => {
                self.page = c as usize - '1' as usize;
                self.pn = 1;
                self.selected = 0;
                self.detail = None;
                self.filter.clear();
                self.context_mid = None;
                self.context_folder = None;
                self.refresh();
            }
            KeyCode::Down | KeyCode::Char('j') => self.select(1),
            KeyCode::Up | KeyCode::Char('k') => self.select(-1),
            KeyCode::PageDown => {
                self.select(self.list_rect.height.saturating_sub(3).max(1) as isize)
            }
            KeyCode::PageUp => {
                self.select(-(self.list_rect.height.saturating_sub(3).max(1) as isize))
            }
            KeyCode::Home => {
                self.selected = 0;
                self.detail = None;
            }
            KeyCode::End => {
                self.selected = if self.page == 8 {
                    self.filtered_queue().len()
                } else {
                    self.filtered().len()
                }
                .saturating_sub(1);
                self.detail = None;
            }
            KeyCode::Enter => self.detail(),
            KeyCode::Char('p') => self.play(),
            KeyCode::Char('s') => self.input(InputKind::Search),
            KeyCode::Char('/') => self.input(InputKind::Filter),
            KeyCode::Char('[') => self.part = self.part.saturating_sub(1),
            KeyCode::Char(']') => {
                if let Some(v) = self.current() {
                    self.part = (self.part + 1).min(v.pages.len().saturating_sub(1));
                }
            }
            KeyCode::Char('Q') => self.quality(),
            KeyCode::Char('d') => {
                self.config.danmaku = !self.config.danmaku;
                self.notice = format!(
                    "下次播放弹幕：{}（mpv 内 j 切换字幕）",
                    if self.config.danmaku { "开" } else { "关" }
                );
            }
            KeyCode::Char('h') => {
                self.config.report_history = !self.config.report_history;
                self.notice = format!(
                    "下次播放历史回报：{}",
                    if self.config.report_history {
                        "开"
                    } else {
                        "关"
                    }
                );
            }
            KeyCode::Char('u') => {
                if let Some(v) = self.current() {
                    if v.mid != 0 {
                        self.context_mid = Some(v.mid);
                        self.pn = 1;
                        self.refresh();
                    }
                }
            }
            KeyCode::Char('g') => {
                if let Some(v) = self.current() {
                    if !v.collection.is_empty() {
                        self.list = v.collection;
                        self.selected = 0;
                        self.detail = None;
                        self.heading = "合集".into();
                    }
                }
            }
            KeyCode::Char('r') if !self.related.is_empty() => {
                self.list = self.related.clone();
                self.detail = None;
                self.selected = 0;
                self.heading = "相关推荐".into();
            }
            KeyCode::Char('R') => self.refresh(),
            KeyCode::Char('n') => {
                if [3, 7].contains(&self.page)
                    && self.context_mid.is_none()
                    && self.context_folder.is_none()
                    && !self.cursors.contains_key(&(self.page, self.pn + 1))
                {
                    self.notice = "已经到最后一页 · 当前没有下一页游标".into();
                } else {
                    self.pn += 1;
                    self.refresh();
                }
            }
            KeyCode::Char('N') => {
                self.pn = self.pn.saturating_sub(1).max(1);
                self.refresh();
            }
            KeyCode::Tab if self.page == 4 => {
                self.up_search = !self.up_search;
                self.pn = 1;
                self.refresh();
            }
            KeyCode::Char(c @ ('l' | 'c' | 'f' | 'w')) => self.action(c),
            KeyCode::Char(c @ ('v' | 'a' | 'A' | 'G')) => self.enqueue(c),
            KeyCode::Char('y') => {
                if let Some(v) = self.current() {
                    let encoded = base64::engine::general_purpose::STANDARD.encode(v.link());
                    print!("\x1b]52;c;{encoded}\x07");
                    io::stdout().flush()?;
                    self.notice = "已通过 OSC52 复制链接".into();
                }
            }
            KeyCode::Char('L') => {
                if self.demo {
                    self.notice = "离线样例禁用登录".into();
                } else if self
                    .queue
                    .iter()
                    .any(|item| item.state != "已完成" && !item.state.starts_with("失败："))
                    || self.player.as_ref().is_some_and(|p| !p.is_finished())
                {
                    self.notice = "请先关闭播放器并等待下载完成，再切换登录账号".into();
                } else {
                    self.modal = Some(Modal::Qr {
                        key: String::new(),
                        art: String::new(),
                        status: "正在获取二维码… Esc 取消".into(),
                        last: std::time::Instant::now(),
                    });
                    let api = self.api.clone();
                    self.request(async move {
                        let (url, key) = api.qr_generate().await?;
                        Ok(Message::Qr(url, key))
                    });
                }
            }
            KeyCode::Esc if !self.filter.is_empty() => {
                let keep = self.selected_key();
                self.filter.clear();
                self.keep_selection(keep);
            }
            KeyCode::Esc => {
                self.cancel_read();
                if self.detail.take().is_none() {
                    if self.context_mid.take().is_some() || self.context_folder.take().is_some() {
                        self.pn = 1;
                        self.refresh();
                    } else {
                        self.filter.clear();
                        self.selected = 0;
                    }
                }
            }
            _ => {}
        }
        Ok(false)
    }
    fn apply_message(&mut self, message: Message) -> bool {
        let message = match message {
            Message::Read(id, _) if id != self.read_generation => return false,
            Message::Read(_, inner) => {
                self.loading = false;
                *inner
            }
            other => other,
        };
        match message {
            Message::Read(_, _) => return false,
            Message::Page(list, title) => {
                self.replace_list(list, title);
                self.notice = if self.list.is_empty() {
                    "没有内容；s 搜索 · R 刷新 · L 登录".into()
                } else {
                    format!("{} 项 · 第 {} 页 · n / N 翻页", self.list.len(), self.pn)
                };
            }
            Message::CursorPage {
                page,
                pn,
                list,
                title,
                next,
            } => {
                if let Some(cursor) = next {
                    self.cursors.insert((page, pn + 1), cursor);
                } else {
                    self.cursors.remove(&(page, pn + 1));
                }
                self.replace_list(list, title);
                self.notice = if self.cursors.contains_key(&(page, pn + 1)) {
                    if self.list.is_empty() {
                        format!("本页没有可显示视频 · 第 {} 页 · n 下一页", pn)
                    } else {
                        format!("{} 项 · 第 {} 页 · n 下一页", self.list.len(), pn)
                    }
                } else if self.list.is_empty() {
                    "没有更多内容 · N 返回上一页 · R 刷新".into()
                } else {
                    format!("{} 项 · 第 {} 页 · 已到最后一页", self.list.len(), pn)
                };
            }
            Message::Detail(v, r) => {
                self.detail = Some(*v);
                self.related = r;
                self.part = 0;
                self.notice = "p 播放 · [ / ] 分 P · Q 清晰度 · v 下载".into();
            }
            Message::Folders(folders, picker, target) => {
                if picker {
                    if let Some(video) = target {
                        self.modal = Some(Modal::Favourite(folders, 0, video));
                    }
                } else {
                    self.list = folders
                        .into_iter()
                        .map(|f| Video {
                            bvid: format!("folder:{}", f.id),
                            title: f.title,
                            views: f.count,
                            up: "收藏夹 · Enter 打开".into(),
                            ..Default::default()
                        })
                        .collect();
                    self.heading = "收藏夹".into();
                    self.selected = 0;
                }
            }
            Message::Cover(url, bytes) => {
                if self.current().is_some_and(|v| v.cover == url) {
                    match encode_image(&bytes) {
                        Ok(png) => self.image = Some((url, png)),
                        Err(_) => {
                            self.image = None;
                        }
                    }
                }
            }
            Message::Qr(url, key) => match qr_art(&url) {
                Ok(art) => {
                    self.modal = Some(Modal::Qr {
                        key,
                        art,
                        status: "用哔哩哔哩 App 扫码，并在手机确认".into(),
                        last: std::time::Instant::now(),
                    })
                }
                Err(e) => {
                    self.error = Some(e.to_string());
                    self.modal = Some(Modal::Error(e.to_string()));
                }
            },
            Message::Login(cookie) => {
                if matches!(self.modal, Some(Modal::Qr { .. })) {
                    match store::save_cookie(&cookie).and_then(|_| Api::new(cookie)) {
                        Ok(api) => {
                            self.api = api;
                            self.modal = None;
                            self.notice = "登录成功 · 登录状态已保存".into();
                            let (tx, rx) = mpsc::unbounded_channel();
                            let (updates, progress) = mpsc::unbounded_channel();
                            self.download = tx;
                            self.progress = progress;
                            self.jobs.push(tokio::spawn(media::download_worker(
                                self.api.clone(),
                                rx,
                                updates,
                            )));
                        }
                        Err(e) => {
                            self.error = Some(e.to_string());
                            self.modal = Some(Modal::Error(e.to_string()));
                        }
                    }
                }
                self.polling = false;
            }
            Message::Suggestions(s) => {
                if let Some(Modal::Input {
                    choices, selected, ..
                }) = &mut self.modal
                {
                    *choices = s.into_iter().map(|s| model::clean(&s)).collect();
                    *selected = None;
                }
            }
            Message::Error(error) => {
                self.error = Some(error.clone());
                self.notice = error.clone();
                self.polling = false;
                self.modal = Some(Modal::Error(error));
            }
            Message::Notice(s) => {
                if let Some(raw) = s.strip_prefix("quality:") {
                    if let Ok(mut q) = serde_json::from_str::<Vec<(u64, String)>>(raw) {
                        q.insert(0, (0, "最高可用（按当前登录权限）".into()));
                        self.modal = Some(Modal::Quality(q, 0));
                    }
                } else if let Some(status) = s.strip_prefix("qr-expired:") {
                    self.polling = false;
                    if let Some(Modal::Qr {
                        key,
                        status: s,
                        last,
                        ..
                    }) = &mut self.modal
                    {
                        key.clear();
                        *s = status.into();
                        *last = std::time::Instant::now();
                    }
                } else if let Some(status) = s.strip_prefix("qr:") {
                    self.polling = false;
                    if let Some(Modal::Qr {
                        status: s, last, ..
                    }) = &mut self.modal
                    {
                        *s = status.into();
                        *last = std::time::Instant::now();
                    }
                } else {
                    if let Some(Modal::Qr { key, status, .. }) = &mut self.modal {
                        if key.is_empty() {
                            *status = s.clone();
                        }
                    }
                    self.notice = s;
                }
            }
        }
        true
    }
    fn receive(&mut self) -> bool {
        let mut dirty = false;
        while let Ok(message) = self.rx.try_recv() {
            dirty |= self.apply_message(message);
        }
        while let Ok(progress) = self.progress.try_recv() {
            if let Some(item) = self.queue.get_mut(progress.id) {
                item.state = progress.state;
                if progress.bytes > 0 {
                    item.bytes = progress.bytes;
                }
            }
            dirty = true;
        }
        while let Ok(s) = self.play_notice.try_recv() {
            self.notice = s;
            dirty = true;
        }
        dirty
    }
    fn poll_qr(&mut self) {
        if !self.focused {
            return;
        }
        let key = if let Some(Modal::Qr { key, last, .. }) = &self.modal {
            if !key.is_empty() && last.elapsed() >= Duration::from_secs(3) && !self.polling {
                Some(key.clone())
            } else {
                None
            }
        } else {
            None
        };
        if let Some(key) = key {
            self.polling = true;
            let api = self.api.clone();
            self.request(async move {
                match api.qr_poll(&key).await {
                    Ok((0, Some(c))) => Ok(Message::Login(c)),
                    Ok((86038, _)) => Ok(Message::Notice(
                        "qr-expired:二维码过期，Esc 后按 L 重新生成".into(),
                    )),
                    Ok((code, _)) => Ok(Message::Notice(format!(
                        "qr:{}",
                        match code {
                            86101 => "等待扫码".to_owned(),
                            86090 => "已扫码，请在手机确认".to_owned(),
                            _ => format!("二维码状态 {code}，请稍后重试"),
                        }
                    ))),
                    Err(e) => Err(e),
                }
            });
        }
    }
    fn request_cover(&mut self, width: u16) {
        if !self.focused || self.demo || !self.kitty || width < 110 || self.modal.is_some() {
            return;
        }
        let Some(video) = self.current() else { return };
        if video.cover.is_empty() || video.cover == self.image_requested {
            return;
        }
        self.image_requested = video.cover.clone();
        let api_url = video.cover;
        if let Some(job) = self.cover_job.take() {
            job.abort();
        }
        let tx = self.tx.clone();
        self.cover_job = Some(tokio::spawn(async move {
            let message = match media::cover(&api_url).await {
                Ok(bytes) => Message::Cover(api_url, bytes),
                Err(error) => Message::Notice(format!("封面不可用：{error}")),
            };
            let _ = tx.send(message);
        }));
    }
    fn focus(&mut self, focused: bool) {
        self.focused = focused;
        if !focused {
            self.resume_read =
                self.loading || self.read_job.as_ref().is_some_and(|job| !job.is_finished());
            self.cancel_read();
            self.loading = false;
            self.polling = false;
            if let Some(job) = self.cover_job.take() {
                if !job.is_finished() {
                    job.abort();
                    self.image_requested.clear();
                }
            }
        } else {
            if let Some(Modal::Qr { key, last, .. }) = &mut self.modal {
                *last = std::time::Instant::now();
                if key.is_empty() && self.resume_read {
                    let api = self.api.clone();
                    self.request(async move {
                        let (url, key) = api.qr_generate().await?;
                        Ok(Message::Qr(url, key))
                    });
                }
            } else if self.resume_read && self.modal.is_none() {
                self.refresh();
            }
            self.resume_read = false;
        }
    }
    fn handle_event(&mut self, event: Event) -> Result<bool> {
        match event {
            Event::FocusLost => {
                self.focus(false);
                delete_image()?;
            }
            Event::FocusGained => self.focus(true),
            Event::Key(key) if key.kind != KeyEventKind::Release && self.key(key)? => {
                return Ok(true);
            }
            Event::Resize(_, _) => {}
            Event::Paste(text) => self.paste(&text),
            Event::Mouse(mouse) if self.modal.is_none() => match mouse.kind {
                MouseEventKind::ScrollDown => self.select(1),
                MouseEventKind::ScrollUp => self.select(-1),
                MouseEventKind::Down(event::MouseButton::Left) => {
                    if mouse.row == 1 {
                        let mut x = 1;
                        for (page, label) in TABS.iter().enumerate() {
                            let width = unicode_width::UnicodeWidthStr::width(*label) as u16 + 4;
                            if mouse.column >= x && mouse.column < x + width {
                                self.page = page;
                                self.pn = 1;
                                self.context_mid = None;
                                self.context_folder = None;
                                self.detail = None;
                                self.selected = 0;
                                self.filter.clear();
                                self.filtering = false;
                                self.refresh();
                                break;
                            }
                            x += width;
                        }
                    } else if self.list_rect.contains((mouse.column, mouse.row).into())
                        && mouse.row >= self.list_rect.y.saturating_add(2)
                        && mouse.row < self.list_rect.bottom().saturating_sub(1)
                        && mouse.column > self.list_rect.x
                        && mouse.column < self.list_rect.right().saturating_sub(1)
                    {
                        self.selected =
                            self.list_offset + (mouse.row - self.list_rect.y - 2) as usize;
                        let len = if self.page == 8 {
                            self.filtered_queue().len()
                        } else {
                            self.filtered().len()
                        };
                        self.selected = self.selected.min(len.saturating_sub(1));
                        self.detail = None;
                    }
                }
                _ => {}
            },
            _ => {}
        }
        Ok(false)
    }
    fn sync_notice(&mut self) {
        if self.notice != self.last_notice {
            let tone = if self.error.as_ref() == Some(&self.notice) {
                ui::Tone::Error
            } else if self.notice.starts_with("已") || self.notice.starts_with("登录成功") {
                ui::Tone::Success
            } else if self.notice.contains("需要")
                || self.notice.contains("请先")
                || self.notice.contains("不可用")
                || self.notice.contains("禁用")
            {
                ui::Tone::Warning
            } else {
                ui::Tone::Info
            };
            self.notice_display.set(self.notice.clone(), tone);
            self.last_notice = self.notice.clone();
        }
    }
    pub async fn run(mut self) -> Result<()> {
        let (mut terminal, _guard) = ui::terminal()?;
        print!("\x1b]11;#1e2228\x07");
        self.refresh();
        let mut dirty = true;
        let mut events = event::EventStream::new();
        loop {
            dirty |= self.receive();
            self.sync_notice();
            if self.focused {
                self.poll_qr();
                self.request_cover(terminal.size()?.width);
                if dirty {
                    terminal.draw(|frame| self.draw(frame))?;
                    self.paint_cover()?;
                    dirty = false;
                }
            }
            let qr = if self.focused && !self.polling {
                match &self.modal {
                    Some(Modal::Qr { key, last, .. }) if !key.is_empty() => {
                        Some(*last + Duration::from_secs(3))
                    }
                    _ => None,
                }
            } else {
                None
            };
            let deadline = if self.focused {
                self.notice_display.deadline().into_iter().chain(qr).min()
            } else {
                None
            };
            let wake = async {
                match deadline {
                    Some(t) => tokio::time::sleep_until(t.into()).await,
                    None => std::future::pending::<()>().await,
                }
            };
            tokio::select! {
                event=events.next()=> {
                    let Some(event)=event else{break};
                    if self.handle_event(event?)? {break;}
                    dirty=true;
                }
                Some(message)=self.rx.recv()=>{dirty|=self.apply_message(message);}
                Some(progress)=self.progress.recv()=>{
                    if let Some(item)=self.queue.get_mut(progress.id) {item.state=progress.state;if progress.bytes>0 {item.bytes=progress.bytes;}}
                    dirty=true;
                }
                Some(notice)=self.play_notice.recv()=>{self.notice=notice;dirty=true;}
                _=wake=>{
                    if self.notice_display.expire() {self.notice.clear();self.last_notice.clear();}
                    self.poll_qr();dirty=true;
                }
            }
        }
        delete_image()?;
        print!("\x1b]111\x07");
        Ok(())
    }
    fn draw(&mut self, frame: &mut Frame) {
        let auth = if self.demo {
            "离线样例"
        } else if self.api.logged_in() {
            "已登录"
        } else {
            "游客"
        };
        let area = frame.area();
        frame.render_widget(Block::default().style(ui::base()), area);
        let layout = Layout::vertical([
            Constraint::Length(1),
            Constraint::Length(1),
            Constraint::Min(1),
            Constraint::Length(2),
        ])
        .split(area);
        self.sync_notice();
        let auth_tone = if self.api.logged_in() && !self.demo {
            ui::Tone::Success
        } else {
            ui::Tone::Info
        };
        frame.render_widget(
            Paragraph::new(Line::from(vec![
                Span::styled(" 哔哩哔哩", Style::default().fg(BRIGHTFG)),
                ui::muted(" · "),
                Span::styled(
                    if matches!(auth_tone, ui::Tone::Info) {
                        auth.to_string()
                    } else {
                        format!("{} {auth}", auth_tone.symbol())
                    },
                    Style::default().fg(auth_tone.color()),
                ),
                ui::muted(format!(
                    " · 弹幕 {}",
                    if self.config.danmaku { "开" } else { "关" }
                )),
            ]))
            .style(ui::base()),
            layout[0],
        );
        let spans = TABS
            .iter()
            .enumerate()
            .flat_map(|(i, t)| {
                [
                    Span::styled(
                        format!("{} {t}", i + 1),
                        if i == self.page {
                            Style::default()
                                .fg(BLUE)
                                .add_modifier(ratatui::style::Modifier::UNDERLINED)
                        } else {
                            Style::default().fg(MUTED)
                        },
                    ),
                    Span::raw("  "),
                ]
            })
            .collect::<Vec<_>>();
        let mut tabs = vec![Span::raw(" ")];
        tabs.extend(spans);
        frame.render_widget(Paragraph::new(Line::from(tabs)), layout[1]);
        let hint = if self.filtering {
            "↑/↓ 选择  Enter 保留  Esc 恢复"
        } else if matches!(self.modal, Some(Modal::Input { .. })) {
            if self.demo {
                "Enter 搜索  ↑/↓ 历史  Esc 取消"
            } else {
                "Enter 搜索  ↑/↓ 历史  Tab 建议  Esc 取消"
            }
        } else if matches!(self.modal, Some(Modal::Error(_))) {
            "Enter 关闭  Esc 关闭"
        } else if matches!(self.modal, Some(Modal::Help)) {
            "?/Esc 关闭帮助"
        } else if matches!(self.modal, Some(Modal::Qr { .. })) {
            "Esc 取消登录"
        } else if self.modal.is_some() {
            "↑/↓ 选择  Enter 确认  Esc 取消"
        } else if self.page == 8 {
            "↑/↓ 选择  / 过滤  1–9 切页  ? 帮助  q 退出"
        } else if self.filtered().is_empty() {
            "/ 过滤  s 搜索  R 刷新  L 登录  ? 帮助  q 退出"
        } else if self.demo {
            "Enter 详情  / 过滤  s 搜索  ↑/↓ 选择  ? 帮助  q 退出"
        } else {
            "Enter 详情  p 播放  s 搜索  / 过滤  v 下载  ? 帮助  q 退出"
        };
        let mut footer = vec![ui::hint_line(hint, layout[3].width as usize)];
        if let Some((text, tone)) = self.notice_display.visible() {
            footer.push(Line::from(Span::styled(
                format!(
                    "{} {}",
                    tone.symbol(),
                    ui::theme::clip(text, layout[3].width.saturating_sub(2) as usize)
                ),
                Style::default().fg(tone.color()),
            )));
        }
        frame.render_widget(Paragraph::new(footer).style(ui::base()), layout[3]);
        if self.filtering {
            self.filter.render(
                frame,
                Rect::new(
                    layout[1].x,
                    layout[1].bottom().saturating_sub(1),
                    layout[1].width,
                    1,
                ),
                ui::base().fg(BLUE),
            );
        }
        self.image_rect = None;
        let body = layout[2];
        if self.page == 8 {
            self.list_rect = body;
            let ids = self.filtered_queue();
            self.list_offset = self
                .selected
                .saturating_sub(body.height.saturating_sub(4) as usize);
            let matcher = Matcher::new(&self.filter);
            let rows = ids
                .iter()
                .map(|i| {
                    let q = &self.queue[*i];
                    let tone = if q.state.starts_with("失败") {
                        ui::Tone::Error
                    } else if q.state == "已完成" {
                        ui::Tone::Success
                    } else {
                        ui::Tone::Info
                    };
                    vec![
                        self.search.highlight(&matcher, &q.title),
                        Line::styled(q.state.clone(), Style::default().fg(tone.color())),
                        ui::numeric(format!("{:.1} MiB", q.bytes as f64 / 1048576.)),
                    ]
                })
                .collect();
            ui::table_highlighted(
                frame,
                body,
                &format!(
                    "下载队列 · {}/{} · /{}",
                    ids.len(),
                    self.queue.len(),
                    self.filter
                ),
                vec!["内容", "状态", "已传输"],
                rows,
                &[
                    Constraint::Min(12),
                    Constraint::Length(16),
                    Constraint::Length(12),
                ],
                self.selected,
            );
            if ids.is_empty() {
                ui::list_state(
                    frame,
                    body.inner(ratatui::layout::Margin {
                        horizontal: 1,
                        vertical: 2,
                    }),
                    ui::ListState::Empty,
                    "/ 修改过滤 · Esc 清除；选择视频后 v 下载",
                );
            }
        } else {
            let wide = body.width >= 110 && self.current().is_some();
            let parts =
                Layout::horizontal([Constraint::Percentage(60), Constraint::Percentage(40)])
                    .split(body);
            if wide {
                self.draw_list(frame, parts[0]);
                self.draw_detail(frame, parts[1]);
            } else if self.detail.is_some() {
                self.draw_detail(frame, body);
            } else {
                self.draw_list(frame, body);
            }
        }
        if let Some(modal) = &self.modal {
            match modal {
                Modal::Help => ui::help(frame, HELP),
                Modal::Error(error) => ui::error_dialog(
                    frame,
                    "请求失败",
                    &format!("{error}\n\nEnter / Esc 关闭；返回列表后 R 重试或 L 登录"),
                ),
                Modal::Input {
                    value,
                    choices,
                    selected,
                    ..
                } => {
                    let inner = ui::modal(
                        frame,
                        if self.demo {
                            "搜索 · ↑/↓ 历史"
                        } else {
                            "搜索 · Tab 建议 · ↑/↓ 历史"
                        },
                        76,
                        18,
                        ui::Tone::Action,
                    );
                    let mut lines = vec![Line::raw(""), Line::raw("")];
                    lines.extend(choices.iter().take(10).enumerate().map(|(i, c)| {
                        Line::from(Span::styled(
                            format!("{} {}", if *selected == Some(i) { "›" } else { " " }, c),
                            Style::default().fg(if *selected == Some(i) { BLUE } else { MUTED }),
                        ))
                    }));
                    lines.push(Line::raw(""));
                    lines.push(ui::hint_line("Enter 搜索  Esc 取消", inner.width as usize));
                    frame.render_widget(Paragraph::new(lines).style(ui::base().bg(SURFACE)), inner);
                    value.render(
                        frame,
                        Rect::new(inner.x, inner.y, inner.width, 1),
                        ui::base().bg(SURFACE).fg(FG),
                    );
                }
                Modal::Confirm(v) => ui::dialog(
                    frame,
                    " 确认投币 ",
                    &format!(
                        "{}\n\n向该视频投 1 枚硬币？\nEnter / y 确认 · n / Esc 取消",
                        v.title
                    ),
                ),
                Modal::Favourite(folders, selected, target) => {
                    let text = if folders.is_empty() {
                        format!("视频：{}\n\n没有收藏夹，请先在官方客户端创建", target.title)
                    } else {
                        format!(
                            "视频：{}\n\n{}",
                            target.title,
                            folders
                                .iter()
                                .enumerate()
                                .map(|(i, f)| format!(
                                    "{} {} · {} 项",
                                    if i == *selected { "▏" } else { " " },
                                    f.title,
                                    f.count
                                ))
                                .collect::<Vec<_>>()
                                .join("\n")
                        )
                    };
                    ui::dialog(frame, " 收藏到 · j/k 选择 · Enter 确认 ", &text);
                }
                Modal::Quality(choices, selected) => ui::dialog(
                    frame,
                    " 清晰度 · j/k 选择 · Enter 确认 ",
                    &choices
                        .iter()
                        .enumerate()
                        .map(|(i, (q, n))| {
                            format!("{} {} · Q{}", if i == *selected { "▏" } else { " " }, n, q)
                        })
                        .collect::<Vec<_>>()
                        .join("\n"),
                ),
                Modal::Qr { art, status, .. } => {
                    let width = art
                        .lines()
                        .next()
                        .map_or(50, unicode_width::UnicodeWidthStr::width)
                        as u16
                        + 4;
                    let height = art.lines().count() as u16 + 5;
                    let inner = ui::modal(
                        frame,
                        "手机扫码登录",
                        width.max(58),
                        height,
                        ui::Tone::Action,
                    );
                    if art.lines().count() as u16 > inner.height.saturating_sub(2)
                        || art.lines().next().is_some_and(|line| {
                            unicode_width::UnicodeWidthStr::width(line) > inner.width as usize
                        })
                    {
                        frame.render_widget(
                            Paragraph::new("请放大终端以完整显示二维码\n\nEsc 取消登录")
                                .style(ui::base().bg(SURFACE).fg(YELLOW))
                                .wrap(Wrap { trim: false }),
                            inner,
                        );
                    } else {
                        let art_height = art.lines().count() as u16;
                        frame.render_widget(
                            Paragraph::new(art.clone()).style(
                                Style::default()
                                    .fg(ratatui::style::Color::White)
                                    .bg(ratatui::style::Color::Black),
                            ),
                            Rect::new(inner.x, inner.y, inner.width, art_height),
                        );
                        let tone = if status.contains("过期") {
                            ui::Tone::Warning
                        } else {
                            ui::Tone::Action
                        };
                        frame.render_widget(
                            Paragraph::new(format!("{} {status}\nEsc 取消登录", tone.symbol()))
                                .style(ui::base().bg(SURFACE).fg(tone.color()))
                                .wrap(Wrap { trim: false }),
                            Rect::new(
                                inner.x,
                                inner.y + art_height,
                                inner.width,
                                inner.height.saturating_sub(art_height),
                            ),
                        );
                    }
                }
            }
        }
    }
    fn draw_list(&mut self, frame: &mut Frame, area: Rect) {
        self.list_rect = area;
        let visible = area.height.saturating_sub(3) as usize;
        self.list_offset = self.selected.saturating_add(1).saturating_sub(visible);
        let matcher = Matcher::new(&self.filter);
        let list = self.filtered();
        let rows = list
            .iter()
            .map(|v| {
                vec![
                    self.search.highlight(&matcher, &v.title),
                    self.search.highlight(&matcher, &v.up),
                    ui::numeric(model::count(v.views)),
                    ui::numeric(v.duration.clone()),
                ]
            })
            .collect();
        ui::table_highlighted(
            frame,
            area,
            &format!(
                "{}/{}{} · {} · 第 {} 页{}",
                list.len(),
                self.list.len(),
                if self.filter.is_empty() {
                    String::new()
                } else {
                    format!(" · /{}", self.filter)
                },
                self.heading,
                self.pn,
                if self.loading {
                    " · 加载中…"
                } else if self.error.is_some() {
                    " · × 请求失败"
                } else {
                    ""
                }
            ),
            vec!["标题", "UP 主", "播放", "时长"],
            rows,
            &[
                Constraint::Min(14),
                Constraint::Length(if area.width < 80 { 12 } else { 18 }),
                Constraint::Length(7),
                Constraint::Length(6),
            ],
            self.selected,
        );
        if list.is_empty() {
            let inner = area.inner(ratatui::layout::Margin {
                horizontal: 1,
                vertical: 2,
            });
            let (state, detail) = if self.loading {
                (
                    ui::ListState::Loading,
                    "正在请求 B 站；Esc 取消本次请求".to_owned(),
                )
            } else if let Some(error) = &self.error {
                (
                    ui::ListState::Error,
                    format!("{error}\nR 重试 · s 搜索 · L 登录"),
                )
            } else if !self.filter.is_empty() {
                (
                    ui::ListState::Empty,
                    format!("过滤：{}\nEsc 清除过滤 · / 修改", self.filter),
                )
            } else {
                (
                    ui::ListState::Empty,
                    if self.page == 4 {
                        "s 输入搜索词 · Tab 视频 / UP 主".into()
                    } else {
                        "R 刷新 · s 搜索 · L 登录；访客可浏览推荐、热门和排行".into()
                    },
                )
            };
            ui::list_state(frame, inner, state, &detail);
        }
    }
    fn draw_detail(&mut self, frame: &mut Frame, area: Rect) {
        frame.render_widget(ui::block(" 视频 · Enter 详情 / p 播放 ", false), area);
        let inner = Rect::new(
            area.x + 2,
            area.y + 1,
            area.width.saturating_sub(4),
            area.height.saturating_sub(2),
        );
        let Some(v) = self.current() else {
            ui::list_state(
                frame,
                inner,
                ui::ListState::Empty,
                "↑/↓ 选择视频 · Enter 查看详情",
            );
            return;
        };
        let has_image = self.kitty
            && area.width >= 38
            && frame.area().width >= 110
            && self.image.as_ref().is_some_and(|(url, _)| *url == v.cover);
        let cover_height = if has_image {
            ((inner.width as f32 * 0.30) as u16)
                .clamp(6, 13)
                .min(inner.height / 2)
        } else {
            0
        };
        let mut y = inner.y;
        if cover_height > 0 {
            self.image_rect = Some(Rect::new(inner.x, y, inner.width, cover_height));
            y += cover_height + 1;
        }
        let mut lines = vec![
            Line::from(Span::styled(v.title.clone(), Style::default().fg(BRIGHTFG))),
            Line::default(),
            Line::from(ui::blue(format!("{}  ·  {}", v.up, v.bvid))),
            Line::from(ui::muted(format!(
                "播放 {}    弹幕 {}    赞 {}",
                model::count(v.views),
                model::count(v.danmaku),
                model::count(v.likes)
            ))),
            Line::default(),
        ];
        if self.detail.is_some() {
            lines.push(Line::from(ui::blue(format!(
                "P{} / {}   ·   Q{}",
                self.part + 1,
                v.pages.len().max(1),
                if self.quality == 0 {
                    "AUTO".into()
                } else {
                    self.quality.to_string()
                }
            ))));
            if let Some(p) = v.pages.get(self.part) {
                lines.push(Line::from(p.part.clone()));
            }
            lines.push(Line::default());
            lines.extend(
                v.description
                    .lines()
                    .take(12)
                    .map(|s| Line::from(s.to_owned())),
            );
            if !v.collection.is_empty() {
                lines.push(Line::from(ui::blue(format!(
                    "合集 · {} 集 · g 浏览 / G 下载",
                    v.collection.len()
                ))));
            }
        } else {
            lines.push(Line::from(ui::muted("Enter 加载简介、分 P 与相关推荐")));
            lines.push(Line::default());
            lines.push(Line::from(ui::muted("[ / ] 分 P     Q 清晰度")));
            lines.push(Line::from(ui::muted("v 视频下载     a 音频下载")));
            lines.push(Line::from(ui::muted("l 点赞   c 投币   f 收藏")));
            lines.push(Line::from(ui::muted("w 稍后再看     u UP 主页")));
        }
        if !has_image {
            lines.push(Line::default());
            lines.push(Line::from(ui::muted("封面：窄窗或非 Kitty 时使用文字")));
        }
        frame.render_widget(
            Paragraph::new(lines)
                .style(ui::base())
                .wrap(Wrap { trim: false }),
            Rect::new(inner.x, y, inner.width, inner.bottom().saturating_sub(y)),
        );
    }
    fn paint_cover(&self) -> Result<()> {
        delete_image()?;
        if self.modal.is_some() {
            return Ok(());
        }
        let (Some(rect), Some((_, png))) = (self.image_rect, self.image.as_ref()) else {
            return Ok(());
        };
        let encoded = base64::engine::general_purpose::STANDARD.encode(png);
        let mut stdout = io::stdout().lock();
        write!(stdout, "\x1b7\x1b[{};{}H", rect.y + 1, rect.x + 1)?;
        let chunks = encoded.as_bytes().chunks(4096);
        let total = chunks.len();
        for (i, chunk) in chunks.enumerate() {
            if i == 0 {
                write!(
                    stdout,
                    "\x1b_Ga=T,f=100,i=42,c={},r={},q=2,m={};",
                    rect.width,
                    rect.height,
                    usize::from(i + 1 < total)
                )?;
            } else {
                write!(stdout, "\x1b_Gm={};", usize::from(i + 1 < total))?;
            }
            stdout.write_all(chunk)?;
            stdout.write_all(b"\x1b\\")?;
        }
        stdout.write_all(b"\x1b8")?;
        stdout.flush()?;
        Ok(())
    }
}
fn video_key(video: &Video) -> String {
    if video.bvid.is_empty() {
        format!("up:{}", video.mid)
    } else {
        video.bvid.clone()
    }
}
fn delete_image() -> Result<()> {
    print!("\x1b_Ga=d,d=I,i=42,q=2\x1b\\");
    io::stdout().flush()?;
    Ok(())
}
fn encode_image(bytes: &[u8]) -> Result<Vec<u8>> {
    let mut reader = image::ImageReader::new(IoCursor::new(bytes)).with_guessed_format()?;
    let mut limits = image::Limits::default();
    limits.max_image_width = Some(8192);
    limits.max_image_height = Some(8192);
    limits.max_alloc = Some(128 * 1024 * 1024);
    reader.limits(limits);
    let decoded = reader.decode()?.thumbnail(640, 360);
    let mut png = IoCursor::new(Vec::new());
    decoded.write_to(&mut png, image::ImageFormat::Png)?;
    Ok(png.into_inner())
}
fn qr_art(url: &str) -> Result<String> {
    use qrcode::{Color, QrCode};
    let qr = QrCode::new(url)?;
    let width = qr.width();
    let quiet = 4;
    let size = width + quiet * 2;
    let dark = |x: usize, y: usize| {
        x >= quiet
            && y >= quiet
            && x < width + quiet
            && y < width + quiet
            && qr[(x - quiet, y - quiet)] == Color::Dark
    };
    let mut out = String::new();
    for y in (0..size).step_by(2) {
        for x in 0..size {
            out.push(match (dark(x, y), y + 1 < size && dark(x, y + 1)) {
                (true, true) => ' ',
                (true, false) => '▄',
                (false, true) => '▀',
                (false, false) => '█',
            });
        }
        out.push('\n');
    }
    Ok(out)
}
fn uid(api: &Api) -> Result<String> {
    api.cookie()
        .split(';')
        .find_map(|p| p.trim().strip_prefix("DedeUserID="))
        .filter(|s| s.chars().all(|c| c.is_ascii_digit()))
        .map(str::to_owned)
        .context("登录状态缺少用户 ID，请重新登录")
}
async fn folders(api: &Api) -> Result<Vec<Folder>> {
    let value = api
        .get(
            "/x/v3/fav/folder/created/list-all",
            &[("up_mid", uid(api)?)],
        )
        .await?;
    Ok(value["list"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|v| Folder {
            id: model::number(&v["id"]),
            title: model::clean(v["title"].as_str().unwrap_or("收藏夹")),
            count: model::number(&v["media_count"]),
        })
        .collect())
}
fn cursor_string(value: &Value) -> Option<String> {
    value
        .as_str()
        .map(str::to_owned)
        .or_else(|| value.as_u64().map(|n| n.to_string()))
        .or_else(|| value.as_i64().map(|n| n.to_string()))
}
struct LoadRequest {
    page: usize,
    pn: u64,
    query: String,
    up: bool,
    mid: Option<u64>,
    folder: Option<u64>,
    cursor: Cursor,
}
async fn load(api: &Api, request: LoadRequest) -> Result<Message> {
    let LoadRequest {
        page,
        pn,
        query,
        up,
        mid,
        folder,
        cursor,
    } = request;
    if let Some(mid) = mid {
        let value = api
            .signed(
                "/x/space/wbi/arc/search",
                &[
                    ("mid", mid.to_string()),
                    ("pn", pn.to_string()),
                    ("ps", "20".into()),
                    ("order", "pubdate".into()),
                ],
            )
            .await?;
        return Ok(Message::Page(
            model::videos(&value["list"]["vlist"]),
            format!("UP 投稿 · {mid}"),
        ));
    }
    if let Some(folder) = folder {
        let value = api
            .get(
                "/x/v3/fav/resource/list",
                &[
                    ("media_id", folder.to_string()),
                    ("pn", pn.to_string()),
                    ("ps", "20".into()),
                    ("platform", "web".into()),
                ],
            )
            .await?;
        return Ok(Message::Page(
            model::videos(&value["medias"]),
            model::clean(value["info"]["title"].as_str().unwrap_or("收藏夹")),
        ));
    }
    let pagination = [("pn", pn.to_string()), ("ps", "20".into())];
    let (videos, title) = match page {
        0 => {
            let value = api
                .signed(
                    "/x/web-interface/wbi/index/top/feed/rcmd",
                    &[
                        ("ps", "20".into()),
                        ("fresh_type", "3".into()),
                        ("fresh_idx", pn.to_string()),
                        ("fresh_idx_1h", pn.to_string()),
                        ("brush", pn.to_string()),
                    ],
                )
                .await?;
            (model::videos(&value["item"]), "首页推荐".into())
        }
        1 => {
            let value = api.get("/x/web-interface/popular", &pagination).await?;
            (model::videos(&value["list"]), "热门视频".into())
        }
        2 => {
            let value = api
                .get(
                    "/x/web-interface/ranking/v2",
                    &[("rid", "0".into()), ("type", "all".into())],
                )
                .await?;
            let list = model::videos(&value["list"]);
            (
                list.into_iter()
                    .skip((pn.saturating_sub(1) * 20) as usize)
                    .take(20)
                    .collect(),
                "全站排行榜".into(),
            )
        }
        3 => {
            let offset = cursor.offset.clone().unwrap_or_default();
            let value = api
                .get(
                    "/x/polymer/web-dynamic/v1/feed/all",
                    &[("type", "video".into()), ("offset", offset.clone())],
                )
                .await?;
            let list = value["items"]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(|item| {
                    let arc = &item["modules"]["module_dynamic"]["major"]["archive"];
                    if arc.is_null() {
                        return None;
                    }
                    let mut video = Video::parse(arc);
                    let author = &item["modules"]["module_author"];
                    video.up = model::clean(author["name"].as_str().unwrap_or(""));
                    video.mid = model::number(&author["mid"]);
                    video.views = model::number(&arc["stat"]["play"]);
                    Some(video)
                })
                .collect::<Vec<_>>();
            let next_offset = value["offset"]
                .as_str()
                .filter(|s| !s.is_empty() && *s != offset.as_str())
                .map(str::to_owned);
            let has_more = value["has_more"].as_bool().unwrap_or(next_offset.is_some());
            let next = if has_more {
                next_offset.map(|offset| Cursor {
                    offset: Some(offset),
                    ..Default::default()
                })
            } else {
                None
            };
            return Ok(Message::CursorPage {
                page,
                pn,
                list,
                title: "关注动态 · 视频".into(),
                next,
            });
        }
        4 => {
            if query.is_empty() {
                return Ok(Message::Page(vec![], "搜索 · s 输入关键词".into()));
            }
            let value = api
                .signed(
                    "/x/web-interface/wbi/search/type",
                    &[
                        (
                            "search_type",
                            if up {
                                "bili_user".into()
                            } else {
                                "video".into()
                            },
                        ),
                        ("keyword", query.clone()),
                        ("page", pn.to_string()),
                        ("page_size", "20".into()),
                    ],
                )
                .await?;
            let list = if up {
                value["result"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .map(|v| Video {
                        mid: model::number(&v["mid"]),
                        title: model::clean(v["uname"].as_str().unwrap_or("")),
                        up: "UP 主 · Enter 投稿列表".into(),
                        cover: v["upic"].as_str().unwrap_or("").into(),
                        ..Default::default()
                    })
                    .collect()
            } else {
                model::videos(&value["result"])
            };
            (
                list,
                format!("搜索{} · {query}", if up { " UP 主" } else { "视频" }),
            )
        }
        5 => return Ok(Message::Folders(folders(api).await?, false, None)),
        6 => {
            let value = api.get("/x/v2/history/toview", &[]).await?;
            (model::videos(&value["list"]), "稍后再看".into())
        }
        7 => {
            let max = cursor.max.clone().unwrap_or_else(|| "0".into());
            let view_at = cursor.view_at.clone().unwrap_or_else(|| "0".into());
            let business = cursor.business.clone().unwrap_or_else(|| "archive".into());
            let value = api
                .get(
                    "/x/web-interface/history/cursor",
                    &[
                        ("ps", "20".into()),
                        ("type", "archive".into()),
                        ("max", max.clone()),
                        ("view_at", view_at.clone()),
                        ("business", business.clone()),
                    ],
                )
                .await?;
            let list = value["list"]
                .as_array()
                .into_iter()
                .flatten()
                .filter(|v| v["history"]["business"] == "archive")
                .map(|v| {
                    let mut video = Video::parse(v);
                    video.bvid = v["history"]["bvid"].as_str().unwrap_or("").into();
                    video.aid = model::number(&v["history"]["oid"]);
                    video.cid = model::number(&v["history"]["cid"]);
                    video.up = model::clean(v["author_name"].as_str().unwrap_or(""));
                    video.mid = model::number(&v["author_mid"]);
                    video
                })
                .collect::<Vec<_>>();
            let returned = &value["cursor"];
            let next_max = cursor_string(&returned["max"]);
            let next_view = cursor_string(&returned["view_at"]);
            let next_business = returned["business"].as_str().map(str::to_owned);
            let changed = next_max.as_deref().is_some_and(|v| v != max.as_str())
                || next_view.as_deref().is_some_and(|v| v != view_at.as_str());
            let has_more = value["has_more"]
                .as_bool()
                .unwrap_or(changed && !list.is_empty());
            let next = if has_more && changed {
                Some(Cursor {
                    max: next_max,
                    view_at: next_view,
                    business: next_business,
                    ..Default::default()
                })
            } else {
                None
            };
            return Ok(Message::CursorPage {
                page,
                pn,
                list,
                title: "历史记录".into(),
                next,
            });
        }
        _ => bail!("未知页面"),
    };
    Ok(Message::Page(videos, title))
}
fn demo_videos() -> Vec<Video> {
    [
    ("在终端里看 B 站：让专注多一点","终端工作室",382400,"12:08"),
    ("从零理解 Rust 的所有权与借用","代码漫游",216800,"24:36"),
    ("一个人的周末，在山野间慢慢走","山间来信",802100,"08:42"),
    ("用 Nix 搭建可以复现的开发环境","Linux 日常",126700,"18:27"),
    ("给生活留一点空白｜桌面与工作流","慢速频道",450600,"10:56"),
    ("夜晚的城市，和一首没有名字的歌","声音收藏家",1304200,"04:18"),
    ("这一次，我们把镜头交给星空","宇宙观测站",687200,"15:03"),
    ("十分钟，把 FFmpeg 的常用操作讲清楚","媒体实验室",96500,"10:00"),
    ("开源项目背后的日常：把小工具做好","开发者手记",184300,"16:48"),
    ("从一杯咖啡开始的清晨","日常收集",392800,"06:21"),
].into_iter().enumerate().map(|(i,(title,up,views,duration))|Video{bvid:format!("BV1demo{:05}",i),aid:1000+i as u64,cid:2000+i as u64,title:title.into(),up:up.into(),mid:42,cover:"demo".into(),views,danmaku:326,likes:14600,duration:duration.into(),description:"这里是离线展示数据。真实运行时会加载 B 站视频简介、分 P 与合集。\n\n终端负责浏览与选择，mpv 负责硬件解码和 ASS 弹幕。".into(),pages:vec![model::Part{cid:2000+i as u64,page:1,part:"正片".into()},model::Part{cid:3000+i as u64,page:2,part:"幕后花絮".into()}],collection:vec![]}).collect()
}
#[cfg(test)]
mod tests {
    use super::*;
    fn app() -> App {
        App::new(
            Api::new(String::new()).unwrap(),
            Config::default(),
            true,
            None,
        )
    }
    fn key(code: KeyCode) -> KeyEvent {
        KeyEvent::new(code, KeyModifiers::NONE)
    }
    fn screen(app: &mut App, width: u16, height: u16) -> String {
        let mut terminal =
            ratatui::Terminal::new(ratatui::backend::TestBackend::new(width, height)).unwrap();
        terminal.draw(|frame| app.draw(frame)).unwrap();
        terminal
            .backend()
            .buffer()
            .content
            .iter()
            .map(|cell| cell.symbol())
            .collect::<String>()
            .replace(' ', "")
    }
    #[test]
    fn local_filter_is_incremental_keeps_identity_and_escape_snapshot() {
        let mut app = app();
        app.selected = 3;
        app.key(key(KeyCode::Char('/'))).unwrap();
        app.key(key(KeyCode::Down)).unwrap();
        let selected = app.selected_key();
        app.paste("shenghuo");
        assert!(!app.filtered().is_empty() && app.filtered().len() < app.list.len());
        assert_eq!(app.selected_key(), selected);
        app.key(KeyEvent::new(KeyCode::Char('q'), KeyModifiers::CONTROL))
            .unwrap();
        assert_eq!(app.filter.as_str(), "shenghuo");
        app.key(key(KeyCode::Enter)).unwrap();
        app.key(key(KeyCode::Char('/'))).unwrap();
        app.paste("\nq\nmissing");
        assert!(app.filtered().is_empty());
        assert_eq!(app.selected, 0);
        app.key(key(KeyCode::Enter)).unwrap();
        let empty = screen(&mut app, 80, 24);
        assert!(empty.contains("0/10"));
        assert!(empty.contains("shenghuoqmissing"));
        assert!(empty.contains("Esc清除过滤"));
        app.key(key(KeyCode::Esc)).unwrap();
        assert!(app.filter.is_empty());
        app.key(key(KeyCode::Char('/'))).unwrap();
        app.paste("nix");
        app.key(key(KeyCode::Enter)).unwrap();
        app.key(key(KeyCode::Char('/'))).unwrap();
        app.paste("missing");
        app.key(key(KeyCode::Esc)).unwrap();
        assert_eq!(app.filter.as_str(), "nix");
        assert!(!app.filtered().is_empty());
        assert!(app.filtered().len() < app.list.len());
        app.paste("q");
        assert_eq!(app.filter.as_str(), "nix");
    }
    #[test]
    fn refresh_and_filtered_mouse_rows_keep_video_ids_and_highlight_han() {
        let mut app = app();
        app.list = vec![
            Video {
                bvid: "a".into(),
                title: "北京 Apple".into(),
                ..Default::default()
            },
            Video {
                bvid: "b".into(),
                title: "香港 Apple".into(),
                ..Default::default()
            },
        ];
        app.selected = 1;
        app.filter.set("apple");
        let mut reversed = app.list.clone();
        reversed.reverse();
        app.apply_message(Message::Page(reversed, "样例".into()));
        assert_eq!(app.selected_key().as_deref(), Some("b"));
        app.key(key(KeyCode::Char('/'))).unwrap();
        app.key(KeyEvent::new(KeyCode::Char('a'), KeyModifiers::CONTROL))
            .unwrap();
        app.key(KeyEvent::new(KeyCode::Char('k'), KeyModifiers::CONTROL))
            .unwrap();
        app.paste("xianggang");
        app.key(key(KeyCode::Enter)).unwrap();
        let mut terminal =
            ratatui::Terminal::new(ratatui::backend::TestBackend::new(80, 24)).unwrap();
        terminal.draw(|frame| app.draw(frame)).unwrap();
        assert!(terminal
            .backend()
            .buffer()
            .content
            .iter()
            .any(|cell| cell.symbol() == "香" && cell.fg == YELLOW));
        let row = app.list_rect.y + 2;
        app.handle_event(Event::Mouse(event::MouseEvent {
            kind: MouseEventKind::Down(event::MouseButton::Left),
            column: 2,
            row,
            modifiers: KeyModifiers::NONE,
        }))
        .unwrap();
        assert_eq!(app.selected_key().as_deref(), Some("b"));
        let last = app.selected;
        app.handle_event(Event::Mouse(event::MouseEvent {
            kind: MouseEventKind::Down(event::MouseButton::Left),
            column: 2,
            row: app.list_rect.bottom() - 1,
            modifiers: KeyModifiers::NONE,
        }))
        .unwrap();
        assert_eq!(app.selected, last);
    }
    #[test]
    fn remote_search_waits_for_enter_and_all_inputs_use_character_editing() {
        let mut app = app();
        app.key(key(KeyCode::Char('s'))).unwrap();
        app.paste("Apple 中文");
        assert!(app.query.is_empty());
        app.key(key(KeyCode::Home)).unwrap();
        app.key(key(KeyCode::Char('中'))).unwrap();
        app.key(KeyEvent::new(KeyCode::Char('x'), KeyModifiers::ALT))
            .unwrap();
        app.key(key(KeyCode::Enter)).unwrap();
        assert_eq!(app.query, "中Apple 中文");
        assert_eq!(app.page, 4);
        assert!(app.modal.is_none());
        for (width, height) in [(80, 24), (120, 24), (1, 1)] {
            screen(&mut app, width, height);
            app.key(key(KeyCode::Char('s'))).unwrap();
            screen(&mut app, width, height);
            app.key(key(KeyCode::Esc)).unwrap();
        }
    }
    #[test]
    fn api_errors_remain_visible_with_a_red_title_and_retry_instruction() {
        let mut app = app();
        app.list.clear();
        app.apply_message(Message::Error(
            "请求参数不正确（错误码 -400）：接口原因".into(),
        ));
        let mut terminal =
            ratatui::Terminal::new(ratatui::backend::TestBackend::new(80, 24)).unwrap();
        terminal.draw(|frame| app.draw(frame)).unwrap();
        assert!(terminal
            .backend()
            .buffer()
            .content
            .iter()
            .any(|cell| cell.fg == RED));
        let text = screen(&mut app, 80, 24);
        assert!(text.contains("请求失败") && text.contains("-400") && text.contains("接口原因"));
        app.key(key(KeyCode::Esc)).unwrap();
        let text = screen(&mut app, 80, 24);
        assert!(text.contains("加载失败") && text.contains("R重试"));
    }
    #[tokio::test]
    async fn losing_focus_cancels_passive_work_and_blocks_qr_polling() {
        let mut app = app();
        let generation = app.read_generation;
        app.read_job = Some(tokio::spawn(std::future::pending()));
        app.cover_job = Some(tokio::spawn(std::future::pending()));
        app.image_requested = "fixture".into();
        app.modal = Some(Modal::Qr {
            key: "0123456789abcdef0123456789abcdef".into(),
            art: String::new(),
            status: String::new(),
            last: std::time::Instant::now() - Duration::from_secs(10),
        });
        app.focus(false);
        app.poll_qr();
        assert!(!app.focused && app.read_job.is_none() && app.cover_job.is_none());
        assert!(!app.polling);
        assert!(app.image_requested.is_empty());
        assert!(!app.apply_message(Message::Read(
            generation,
            Box::new(Message::Page(vec![], "旧请求".into()))
        )));
        app.focus(true);
        assert!(app.focused && !app.polling);
    }
    #[tokio::test]
    async fn focus_resumes_completed_reads_before_their_results_are_consumed() {
        for qr in [false, true] {
            let mut app = app();
            app.demo = false;
            if qr {
                app.modal = Some(Modal::Qr {
                    key: String::new(),
                    art: String::new(),
                    status: "正在获取二维码".into(),
                    last: std::time::Instant::now(),
                });
            }
            app.request(async { Ok(Message::Page(vec![], "尚未消费".into())) });
            while !app.read_job.as_ref().unwrap().is_finished() {
                tokio::task::yield_now().await;
            }
            assert!(app.loading);
            app.focus(false);
            assert!(app.resume_read);
            assert!(!app.receive());
            assert_ne!(app.heading, "尚未消费");
            app.focus(true);
            assert!(app.loading && app.read_job.is_some());
            assert!(!app.resume_read);
            app.cancel_read();
        }
    }
    #[test]
    fn qr_modal_shows_complete_art_or_an_explicit_size_instruction() {
        let mut app = app();
        let art =
            qr_art("https://account.bilibili.com/h5/account-h5/auth/scan-web?fixture=1").unwrap();
        app.modal = Some(Modal::Qr {
            key: String::new(),
            art,
            status: "等待扫码".into(),
            last: std::time::Instant::now(),
        });
        assert!(screen(&mut app, 80, 24).contains("请放大终端"));
        assert!(screen(&mut app, 120, 50).contains('█'));
        screen(&mut app, 1, 1);
    }

    #[test]
    fn qr_uses_half_blocks() {
        let art = qr_art("https://example.com/fixture").unwrap();
        assert!(art.contains('▀'));
        assert!(art
            .lines()
            .all(|l| l.chars().count() == art.lines().next().unwrap().chars().count()));
    }
    #[test]
    fn fixture_detail_parser() {
        let v: Value = serde_json::from_str(include_str!("../fixtures/video.json")).unwrap();
        let video = Video::parse(&v["data"]);
        assert!(!video.bvid.is_empty());
    }
}
