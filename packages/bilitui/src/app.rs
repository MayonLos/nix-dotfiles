use crate::{
    api::Api,
    media::{self, Download, Progress},
    model::{self, Video},
    store::{self, Config},
};
use anyhow::{bail, Context, Result};
use base64::Engine;
use crossterm::event::{self, Event, KeyCode, KeyEventKind, MouseEventKind};
use mayon_ui::{self as ui, theme::*};
use ratatui::{
    layout::{Constraint, Layout, Rect},
    style::Style,
    text::{Line, Span},
    widgets::{Block, Clear, Paragraph, Wrap},
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
    Input {
        kind: InputKind,
        value: String,
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
    filter: String,
    query: String,
    up_search: bool,
    heading: String,
    notice: String,
    modal: Option<Modal>,
    tx: mpsc::UnboundedSender<Message>,
    rx: mpsc::UnboundedReceiver<Message>,
    jobs: Vec<tokio::task::JoinHandle<()>>,
    read_job: Option<tokio::task::JoinHandle<()>>,
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
            filter: String::new(),
            query: String::new(),
            up_search: false,
            heading: "首页推荐".into(),
            notice: if demo {
                "离线样例 · 不访问网络、不读取登录状态".into()
            } else {
                "正在加载…".into()
            },
            modal: None,
            tx,
            rx,
            jobs,
            read_job: None,
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
        self.read_job = Some(tokio::spawn(async move {
            let result = match future.await {
                Ok(v) => v,
                Err(e) => Message::Notice(e.to_string()),
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
                Err(e) => Message::Notice(e.to_string()),
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
        self.list
            .iter()
            .filter(|v| {
                self.filter.is_empty()
                    || format!("{} {}", v.title, v.up)
                        .to_lowercase()
                        .contains(&self.filter.to_lowercase())
            })
            .collect()
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
            self.queue.len()
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
        self.modal = Some(Modal::Input {
            kind,
            value: if matches!(kind, InputKind::Filter) {
                self.filter.clone()
            } else {
                self.query.clone()
            },
            choices: if self.demo {
                vec!["Rust 入门".into(), "终端工作流".into()]
            } else {
                store::history()
            },
            selected: None,
        });
    }
    fn key_modal(&mut self, key: KeyCode) -> Result<()> {
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
        let mut keep = true;
        match &mut modal {
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
                            *value = s.clone();
                        }
                    }
                    if matches!(kind, InputKind::Filter) {
                        self.filter = value.clone();
                        self.selected = 0;
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
                KeyCode::Backspace => {
                    value.pop();
                    *selected = None;
                }
                KeyCode::Char(c) => {
                    if value.len() < 256 {
                        value.push(c);
                    }
                    *selected = None;
                }
                KeyCode::Down if !choices.is_empty() => {
                    *selected = Some(selected.map_or(0, |i| (i + 1).min(choices.len() - 1)));
                }
                KeyCode::Up => {
                    *selected = selected.map(|i| i.saturating_sub(1));
                }
                KeyCode::Tab if matches!(kind, InputKind::Search) && !self.demo => {
                    let api = self.api.clone();
                    let query = value.clone();
                    self.request(
                        async move { Ok(Message::Suggestions(api.suggest(&query).await?)) },
                    );
                }
                _ => {}
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
    fn key(&mut self, key: KeyCode) -> Result<bool> {
        if self.modal.is_some() {
            self.key_modal(key)?;
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
            KeyCode::PageDown => self.select(10),
            KeyCode::PageUp => self.select(-10),
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
    fn receive(&mut self) -> bool {
        let mut dirty = false;
        while let Ok(message) = self.rx.try_recv() {
            let message = match message {
                Message::Read(id, _) if id != self.read_generation => continue,
                Message::Read(_, inner) => *inner,
                other => other,
            };
            dirty = true;
            match message {
                Message::Read(_, _) => continue,
                Message::Page(list, title) => {
                    self.list = list;
                    self.heading = title;
                    self.selected = 0;
                    self.detail = None;
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
                    self.list = list;
                    self.heading = title;
                    self.selected = 0;
                    self.detail = None;
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
                            status: "请用哔哩哔哩 App 扫码；Esc 取消".into(),
                            last: std::time::Instant::now(),
                        })
                    }
                    Err(e) => self.notice = e.to_string(),
                },
                Message::Login(cookie) => {
                    if matches!(self.modal, Some(Modal::Qr { .. })) {
                        match store::save_cookie(&cookie).and_then(|_| Api::new(cookie)) {
                            Ok(api) => {
                                self.api = api;
                                self.modal = None;
                                self.notice = "登录成功 · cookie 已以 0600 保存".into();
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
                            Err(e) => self.notice = e.to_string(),
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
                            86101 => "等待扫码",
                            86090 => "已扫码，请在手机确认",
                            _ => "二维码未完成，请稍后重试",
                        }
                    ))),
                    Err(e) => Ok(Message::Notice(format!("qr:{e}"))),
                }
            });
        }
    }
    fn request_cover(&mut self, width: u16) {
        if self.demo || !self.kitty || width < 110 || self.modal.is_some() {
            return;
        }
        let Some(video) = self.current() else { return };
        if video.cover.is_empty() || video.cover == self.image_requested {
            return;
        }
        self.image_requested = video.cover.clone();
        let api_url = video.cover;
        self.independent(async move {
            let bytes = media::cover(&api_url).await?;
            Ok(Message::Cover(api_url, bytes))
        });
    }
    pub async fn run(mut self) -> Result<()> {
        let (mut terminal, _guard) = ui::terminal()?;
        print!("\x1b]11;#1e2228\x07");
        self.refresh();
        let mut dirty = true;
        loop {
            dirty |= self.receive();
            self.poll_qr();
            self.request_cover(terminal.size()?.width);
            if dirty {
                terminal.draw(|frame| self.draw(frame))?;
                self.paint_cover()?;
                dirty = false;
            }
            if event::poll(Duration::from_millis(80))? {
                match event::read()? {
                    Event::Key(key) if key.kind == KeyEventKind::Press => {
                        if self.key(key.code)? {
                            break;
                        }
                        dirty = true;
                    }
                    Event::Resize(_, _) => dirty = true,
                    Event::Mouse(mouse) if self.modal.is_none() => {
                        match mouse.kind {
                            MouseEventKind::ScrollDown => self.select(1),
                            MouseEventKind::ScrollUp => self.select(-1),
                            MouseEventKind::Down(event::MouseButton::Left) => {
                                if mouse.row == 1 {
                                    let mut x = 0;
                                    for (page, label) in TABS.iter().enumerate() {
                                        let width = unicode_width::UnicodeWidthStr::width(*label)
                                            as u16
                                            + 5;
                                        if mouse.column >= x && mouse.column < x + width {
                                            self.page = page;
                                            self.pn = 1;
                                            self.context_mid = None;
                                            self.context_folder = None;
                                            self.detail = None;
                                            self.selected = 0;
                                            self.refresh();
                                            break;
                                        }
                                        x += width;
                                    }
                                } else if self.list_rect.contains((mouse.column, mouse.row).into())
                                    && mouse.row > self.list_rect.y + 1
                                {
                                    self.selected = self.list_offset
                                        + (mouse.row - self.list_rect.y - 2) as usize;
                                    self.selected =
                                        self.selected.min(self.filtered().len().saturating_sub(1));
                                    self.detail = None;
                                }
                            }
                            _ => {}
                        }
                        dirty = true;
                    }
                    _ => {}
                }
            }
            tokio::task::yield_now().await;
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
            Constraint::Length(2),
            Constraint::Min(1),
            Constraint::Length(2),
        ])
        .split(area);
        ui::status(frame,layout[0],&format!(" BILIBILI   /   bilitui-mayon                         {auth} · mpv / DASH · 弹幕 {}",if self.config.danmaku{"开"}else{"关"}));
        // Compact tabs retain every numbered destination at 90 columns.
        let spans = TABS
            .iter()
            .enumerate()
            .flat_map(|(i, t)| {
                [
                    Span::styled(
                        format!(" {} {t} ", i + 1),
                        Style::default().fg(if i == self.page { BLUE } else { MUTED }),
                    ),
                    Span::raw(" "),
                ]
            })
            .collect::<Vec<_>>();
        frame.render_widget(Paragraph::new(Line::from(spans)), layout[1]);
        ui::footer(
            frame,
            layout[3],
            " Enter 详情  p 播放  s 搜索  / 过滤  v 下载  ? 帮助  q 退出",
            &self.notice,
        );
        self.image_rect = None;
        let body = layout[2];
        if self.page == 8 {
            let rows = self
                .queue
                .iter()
                .map(|q| {
                    vec![
                        q.title.clone(),
                        q.state.clone(),
                        format!("{:.1} MiB", q.bytes as f64 / 1048576.),
                    ]
                })
                .collect();
            ui::table(
                frame,
                body,
                " 下载队列 · 串行 / 退出取消 ",
                vec!["内容", "状态", "已传输"],
                rows,
                &[
                    Constraint::Min(20),
                    Constraint::Length(20),
                    Constraint::Length(12),
                ],
                self.selected,
            );
        } else {
            let wide = body.width >= 110;
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
                Modal::Input {
                    kind,
                    value,
                    choices,
                    selected,
                } => {
                    let title = if matches!(kind, InputKind::Filter) {
                        " 过滤当前列表 "
                    } else {
                        " 搜索 · Tab 建议 · ↑↓ 历史 "
                    };
                    let mut lines = vec![format!("{value}▏"), String::new()];
                    lines.extend(choices.iter().take(10).enumerate().map(|(i, c)| {
                        format!("{} {}", if *selected == Some(i) { "▏" } else { " " }, c)
                    }));
                    lines.push("Enter 确认 · Esc 取消".into());
                    ui::dialog(frame, title, &lines.join("\n"));
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
                    let a = ui::centered(area, width.max(58), height);
                    frame.render_widget(Clear, a);
                    frame.render_widget(
                        Paragraph::new(format!("{art}\n{status}\nEsc 取消；二维码仅当前进程保存"))
                            .style(
                                Style::default()
                                    .fg(ratatui::style::Color::White)
                                    .bg(ratatui::style::Color::Black),
                            )
                            .block(ui::block(" 手机扫码登录 ", true)),
                        a,
                    );
                }
            }
        }
    }
    fn draw_list(&mut self, frame: &mut Frame, area: Rect) {
        self.list_rect = area;
        let visible = area.height.saturating_sub(3).max(1) as usize;
        self.list_offset = self.selected.saturating_sub(visible.saturating_sub(1));
        let list = self.filtered();
        let rows = list
            .iter()
            .map(|v| {
                vec![
                    v.title.clone(),
                    v.up.clone(),
                    model::count(v.views),
                    v.duration.clone(),
                ]
            })
            .collect();
        ui::table(
            frame,
            area,
            &format!(
                " {} · {} 项 · 第 {} 页{} ",
                self.heading,
                list.len(),
                self.pn,
                if self.filter.is_empty() {
                    String::new()
                } else {
                    format!(" · /{}", self.filter)
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
            let a = Rect::new(
                area.x + 2,
                area.y + 3,
                area.width.saturating_sub(4),
                area.height.saturating_sub(5),
            );
            frame.render_widget(
                Paragraph::new(if self.page == 4 {
                    "s 输入搜索词 · Tab 视频 / UP 主\n\n搜索历史保存在本机，Tab 按需获取建议。"
                } else {
                    "没有内容\n\nR 刷新 · s 搜索 · L 登录\n访客可以浏览推荐、热门、排行和视频详情。"
                })
                .style(ui::base().fg(MUTED))
                .wrap(Wrap { trim: false }),
                a,
            );
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
        let Some(v) = self.current() else { return };
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
