//! Overlay state and drawing for both modes.
//!
//! The clipboard and launcher are the same interactive surface: a centred
//! One Dark card with a search field and a scrollable list. Clipboard rows show
//! text previews or image thumbnails; launcher rows are pure text (no icons).
//! The same state machine is driven by real Wayland keyboard/pointer events,
//! IPC commands (used by the headless test harness) and calls from `main`
//! (single-instance toggle).

use crate::canvas::Canvas;
use crate::cliphist;
use crate::desktop::{self, AppEntry};
use crate::fonts::Fonts;
use crate::logger::{self, Logger};
use crate::palette as colors;
use std::path::PathBuf;

const PAD: f32 = 22.0;
const TITLE_SIZE: f32 = 15.0;
const SEARCH_SIZE: f32 = 16.0;
const ROW_TEXT_SIZE: f32 = 15.0;
const ROW_SUB_SIZE: f32 = 12.0;
const FOOTER_SIZE: f32 = 12.0;
const CLIP_ROW_H: f32 = 74.0;
const LAUNCH_ROW_H: f32 = 42.0;
const SEARCH_H: f32 = 42.0;
const FOOTER_H: f32 = 28.0;
const THUMB_W: f32 = 84.0;
const THUMB_H: f32 = 56.0;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mode {
    Clipboard,
    Launcher,
}

impl Mode {
    pub fn name(self) -> &'static str {
        match self {
            Mode::Clipboard => "clipboard",
            Mode::Launcher => "launcher",
        }
    }
    pub fn default_socket_path(self) -> PathBuf {
        let runtime = std::env::var_os("XDG_RUNTIME_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("/tmp"));
        runtime.join(self.default_socket_name())
    }
    fn default_socket_name(self) -> &'static str {
        match self {
            Mode::Clipboard => "mayon-overlay-clipboard.sock",
            Mode::Launcher => "mayon-overlay-launcher.sock",
        }
    }
    fn row_height(self) -> f32 {
        match self {
            Mode::Clipboard => CLIP_ROW_H,
            Mode::Launcher => LAUNCH_ROW_H,
        }
    }
}

pub enum Item {
    ClipText {
        id: i64,
        text: String,
    },
    ClipImage {
        id: i64,
        preview: String,
        dimensions: Option<(u32, u32)>,
        mime: String,
    },
    App {
        app: AppEntry,
    },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Key {
    Escape,
    Enter,
    Tab,
    Backspace,
    Up,
    Down,
    PageUp,
    PageDown,
    Home,
    End,
    /// Plain character typed by the user; appended to the query.
    Char(char),
    /// Ctrl+character, used for vim-style list movement.
    CtrlChar(char),
    Other,
}

pub enum ExitAction {
    ClipboardCopied {
        is_image: bool,
        bytes: usize,
        preview: String,
    },
    Launched {
        name: String,
        desktop_path: String,
        result: Result<(), String>,
    },
    Closed {
        reason: String,
    },
}

pub struct Layout {
    pub width: f32,
    pub height: f32,
    pub scale: f32,
    pub card_x: f32,
    pub card_y: f32,
    pub card_w: f32,
    pub card_h: f32,
    pub capacity: usize,
    pub rows: Vec<(usize, f32, f32, f32, f32)>,
}

struct Geometry {
    card_x: f32,
    card_y: f32,
    card_w: f32,
    card_h: f32,
    list_x: f32,
    list_y: f32,
    list_w: f32,
    row_h: f32,
    capacity: usize,
}

pub struct Overlay {
    pub mode: Mode,
    pub query: String,
    pub selected: usize,
    pub first_visible: usize,
    pub items: Vec<Item>,
    pub visible: Vec<usize>,
    pub status: Option<String>,
    pub layout: Option<Layout>,
    pub canvas: Option<Canvas>,
    fonts: Option<Fonts>,
    pub logger: Logger,
    extra_data_dirs: Vec<PathBuf>,
    ready_logged: bool,
}

impl Overlay {
    pub fn new_clipboard(fonts: Fonts, logger: Logger) -> Overlay {
        let mut overlay = Overlay::new(Mode::Clipboard, fonts, logger);
        match cliphist::load_history() {
            Ok(entries) => {
                for entry in entries {
                    if entry.is_image {
                        overlay.items.push(Item::ClipImage {
                            id: entry.id,
                            dimensions: parse_dimensions(&entry.preview),
                            preview: entry.preview,
                            mime: entry.image_mime.unwrap_or_else(|| "image/png".to_string()),
                        });
                    } else {
                        overlay.items.push(Item::ClipText {
                            id: entry.id,
                            text: cliphist::preview_text(&entry.preview),
                        });
                    }
                }
                let count = overlay.items.len();
                overlay.logger.event(
                    "history",
                    &[
                        ("mode", logger::json_string("clipboard")),
                        ("count", count.to_string()),
                    ],
                );
            }
            Err(error) => {
                overlay.status = Some(format!("无法读取剪贴板历史：{}", error));
                overlay.logger.event(
                    "history_error",
                    &[
                        ("mode", logger::json_string("clipboard")),
                        ("error", logger::json_string(&error)),
                    ],
                );
            }
        }
        overlay.refilter();
        overlay
    }

    pub fn new_launcher(fonts: Fonts, logger: Logger, extra_data_dirs: Vec<PathBuf>) -> Overlay {
        let mut overlay = Overlay::new(Mode::Launcher, fonts, logger);
        overlay.extra_data_dirs = extra_data_dirs;
        overlay.reload_apps();
        overlay.refilter();
        overlay
    }

    fn new(mode: Mode, fonts: Fonts, logger: Logger) -> Overlay {
        Overlay {
            mode,
            query: String::new(),
            selected: 0,
            first_visible: 0,
            items: Vec::new(),
            visible: Vec::new(),
            status: None,
            layout: None,
            canvas: None,
            fonts: Some(fonts),
            logger,
            extra_data_dirs: Vec::new(),
            ready_logged: false,
        }
    }

    pub fn reload_apps(&mut self) {
        let apps = desktop::load_apps(&self.extra_data_dirs);
        self.items = apps.into_iter().map(|app| Item::App { app }).collect();
        let count = self.items.len();
        self.logger.event(
            "apps",
            &[
                ("mode", logger::json_string("launcher")),
                ("count", count.to_string()),
            ],
        );
    }

    /// Recompute the filtered view from the current query and reset the
    /// cursor. Image entries are kept while the query is empty; any non-empty
    /// query filters on the visible preview text.
    pub fn refilter(&mut self) {
        let query = self.query.trim().to_lowercase();
        let mut visible = Vec::new();
        if self.mode == Mode::Launcher {
            let mut ranked: Vec<(u8, usize)> = Vec::new();
            for (index, item) in self.items.iter().enumerate() {
                if let Item::App { app } = item {
                    if let Some(rank) = desktop::rank(app, &query) {
                        ranked.push((rank, index));
                    }
                }
            }
            ranked.sort_by_key(|(rank, index)| (*rank, *index));
            visible.extend(ranked.into_iter().map(|(_, index)| index));
        } else {
            for (index, item) in self.items.iter().enumerate() {
                let matches = match item {
                    Item::ClipText { text, .. } => {
                        query.is_empty() || text.to_lowercase().contains(&query)
                    }
                    Item::ClipImage { .. } => query.is_empty(),
                    Item::App { app } => desktop::rank(app, &query).is_some(),
                };
                if matches {
                    visible.push(index);
                }
            }
        }
        self.visible = visible;
        self.selected = 0;
        self.first_visible = 0;
        self.layout = None;
    }

    pub fn set_query(&mut self, query: String) {
        self.query = query;
        self.refilter();
    }

    pub fn move_selection(&mut self, delta: i64) {
        if self.visible.is_empty() {
            return;
        }
        let max = self.visible.len() as i64 - 1;
        self.selected = (self.selected as i64 + delta).clamp(0, max) as usize;
        self.status = None;
        self.layout = None;
    }

    pub fn select(&mut self, index: usize) {
        if index < self.visible.len() {
            self.selected = index;
            self.status = None;
            self.layout = None;
        }
    }

    /// Perform the selected action. Clipboard entries are decoded and written
    /// to the compositor clipboard here; the caller only needs to exit and
    /// optionally inject the paste chord afterwards.
    pub fn activate(&mut self) -> Option<ExitAction> {
        if self.visible.is_empty() {
            self.status = Some("没有可激活的条目".to_string());
            self.layout = None;
            return None;
        }
        let item_index = self.visible[self.selected];
        let item = &self.items[item_index];
        let (id, image_mime, preview) = match item {
            Item::ClipText { id, text } => (*id, None, text.chars().take(80).collect::<String>()),
            Item::ClipImage {
                id, preview, mime, ..
            } => (*id, Some(mime.clone()), preview.chars().take(80).collect()),
            Item::App { app } => {
                let name = app.name.clone();
                let desktop_path = app.desktop_path.to_string_lossy().to_string();
                let result = desktop::launch(app);
                self.logger.event(
                    "launch",
                    &[
                        ("mode", logger::json_string("launcher")),
                        ("name", logger::json_string(&name)),
                        ("desktop_path", logger::json_string(&desktop_path)),
                        ("ok", result.is_ok().to_string()),
                        (
                            "error",
                            match &result {
                                Ok(()) => "null".to_string(),
                                Err(error) => logger::json_string(error),
                            },
                        ),
                    ],
                );
                return Some(ExitAction::Launched {
                    name,
                    desktop_path,
                    result,
                });
            }
        };
        match cliphist::decode(id) {
            Ok(bytes) => match cliphist::copy(&bytes, image_mime.as_deref()) {
                Ok(()) => {
                    self.logger.event(
                        "copy",
                        &[
                            ("mode", logger::json_string("clipboard")),
                            (
                                "kind",
                                logger::json_string(if image_mime.is_some() {
                                    "image"
                                } else {
                                    "text"
                                }),
                            ),
                            ("bytes", bytes.len().to_string()),
                            ("preview", logger::json_string(&preview)),
                        ],
                    );
                    Some(ExitAction::ClipboardCopied {
                        is_image: image_mime.is_some(),
                        bytes: bytes.len(),
                        preview,
                    })
                }
                Err(error) => {
                    self.status = Some(format!("复制失败：{}", error));
                    self.layout = None;
                    self.logger
                        .event("copy_error", &[("error", logger::json_string(&error))]);
                    None
                }
            },
            Err(error) => {
                self.status = Some(format!("解码失败：{}", error));
                self.layout = None;
                self.logger
                    .event("decode_error", &[("error", logger::json_string(&error))]);
                None
            }
        }
    }

    pub fn close(&self, reason: &str) -> ExitAction {
        self.logger.event(
            "close",
            &[
                ("mode", logger::json_string(self.mode.name())),
                ("reason", logger::json_string(reason)),
            ],
        );
        ExitAction::Closed {
            reason: reason.to_string(),
        }
    }

    /// Handle one interpreted key. Returns an exit action when the overlay
    /// should be destroyed.
    pub fn handle_key(&mut self, key: Key) -> Option<ExitAction> {
        match key {
            Key::Escape => Some(self.close("escape")),
            Key::Enter | Key::Tab => self.activate(),
            Key::Up => {
                self.move_selection(-1);
                None
            }
            Key::Down => {
                self.move_selection(1);
                None
            }
            Key::PageUp => {
                let page = self
                    .layout
                    .as_ref()
                    .map(|layout| layout.capacity.max(1) as i64)
                    .unwrap_or(6);
                self.move_selection(-page);
                None
            }
            Key::PageDown => {
                let page = self
                    .layout
                    .as_ref()
                    .map(|layout| layout.capacity.max(1) as i64)
                    .unwrap_or(6);
                self.move_selection(page);
                None
            }
            Key::Home => {
                self.select(0);
                None
            }
            Key::End => {
                if !self.visible.is_empty() {
                    self.select(self.visible.len() - 1);
                }
                None
            }
            Key::Backspace => {
                if self.query.pop().is_some() {
                    self.refilter();
                }
                None
            }
            Key::CtrlChar('j') | Key::CtrlChar('n') => {
                self.move_selection(1);
                None
            }
            Key::CtrlChar('k') | Key::CtrlChar('p') => {
                self.move_selection(-1);
                None
            }
            Key::Char(ch) => {
                if !ch.is_control() {
                    self.query.push(ch);
                    self.refilter();
                }
                None
            }
            Key::Other | Key::CtrlChar(_) => None,
        }
    }

    /// Pointer click at surface-local logical coordinates. Clicking a row
    /// activates it immediately (launchers behave the same with mouse and
    /// keyboard); clicking outside the card dismisses the overlay.
    pub fn pointer_click(&mut self, x: f32, y: f32) -> Option<ExitAction> {
        let Some(layout) = self.layout.as_ref() else {
            return None;
        };
        let inside_card = x >= layout.card_x
            && x <= layout.card_x + layout.card_w
            && y >= layout.card_y
            && y <= layout.card_y + layout.card_h;
        if !inside_card {
            return Some(self.close("click-outside"));
        }
        let hit = layout
            .rows
            .iter()
            .find(|(_, row_x, row_y, row_w, row_h)| {
                x >= *row_x && x <= *row_x + *row_w && y >= *row_y && y <= *row_y + *row_h
            })
            .map(|(row_index, ..)| *row_index);
        match hit {
            Some(index) => {
                self.select(index);
                self.activate()
            }
            None => None,
        }
    }

    /// IPC command handling. The response is a single-line JSON object; the
    /// optional exit action tells the event loop to tear the surface down.
    pub fn ipc_command(&mut self, request: &str) -> (String, Option<ExitAction>) {
        let request = request.trim();
        let (command, rest) = match request.split_once(' ') {
            Some((command, rest)) => (command.trim(), rest.trim()),
            None => (request, ""),
        };
        match command {
            "" => (self.ipc_error("empty command"), None),
            "ping" => ("{\"ok\":true,\"pong\":true}".to_string(), None),
            "state" => (self.state_json(), None),
            "toggle" => (
                "{\"ok\":true,\"action\":\"close\"}".to_string(),
                Some(self.close("toggle")),
            ),
            "close" => (
                "{\"ok\":true,\"action\":\"close\"}".to_string(),
                Some(self.close("ipc-close")),
            ),
            "reload" => {
                if self.mode == Mode::Launcher {
                    self.reload_apps();
                }
                self.refilter();
                (self.state_json(), None)
            }
            "query" => {
                self.set_query(unescape_ipc(rest));
                (self.state_json(), None)
            }
            "select" => match rest.parse::<usize>() {
                Ok(index) if index < self.visible.len() => {
                    self.select(index);
                    (self.state_json(), None)
                }
                _ => (self.ipc_error("select requires a visible index"), None),
            },
            "activate" => {
                if !rest.is_empty() {
                    match rest.parse::<usize>() {
                        Ok(index) => self.select(index),
                        Err(_) => return (self.ipc_error("activate index is not a number"), None),
                    }
                }
                self.reply_to_action()
            }
            "click" => {
                let mut coords = rest.split_whitespace();
                let parsed = (
                    coords.next().and_then(|value| value.parse::<f32>().ok()),
                    coords.next().and_then(|value| value.parse::<f32>().ok()),
                );
                match parsed {
                    (Some(x), Some(y)) => {
                        let action = self.pointer_click(x, y);
                        self.reply_to_action_value(action)
                    }
                    _ => (self.ipc_error("click requires x and y"), None),
                }
            }
            _ => (
                self.ipc_error(&format!("unknown command {}", command)),
                None,
            ),
        }
    }

    fn reply_to_action(&mut self) -> (String, Option<ExitAction>) {
        let action = self.activate();
        self.reply_to_action_value(action)
    }

    fn reply_to_action_value(
        &mut self,
        action: Option<ExitAction>,
    ) -> (String, Option<ExitAction>) {
        let reply = match &action {
            Some(ExitAction::ClipboardCopied { is_image, .. }) => format!(
                "{{\"ok\":true,\"action\":\"copy\",\"kind\":\"{}\"}}",
                if *is_image { "image" } else { "text" }
            ),
            Some(ExitAction::Launched { result, .. }) => format!(
                "{{\"ok\":true,\"action\":\"launch\",\"result_ok\":{}}}",
                result.is_ok()
            ),
            Some(ExitAction::Closed { .. }) => "{\"ok\":true,\"action\":\"close\"}".to_string(),
            None => return (self.state_json(), None),
        };
        (reply, action)
    }

    fn ipc_error(&self, message: &str) -> String {
        format!(
            "{{\"ok\":false,\"error\":{}}}",
            logger::json_string(message)
        )
    }

    pub fn state_json(&self) -> String {
        let mut entries = String::new();
        for (position, item_index) in self.visible.iter().enumerate() {
            if position > 0 {
                entries.push(',');
            }
            let item = &self.items[*item_index];
            let (kind, preview) = match item {
                Item::ClipText { text, .. } => ("text", truncate_chars(text, 120)),
                Item::ClipImage { preview, .. } => ("image", truncate_chars(preview, 120)),
                Item::App { app } => ("app", truncate_chars(&app.name, 120)),
            };
            entries.push_str(&format!(
                "{{\"index\":{},\"kind\":{},\"preview\":{},\"selected\":{}}}",
                position,
                logger::json_string(kind),
                logger::json_string(&preview),
                position == self.selected
            ));
        }
        let layout_json = match &self.layout {
            Some(layout) => {
                let mut rows = String::new();
                let mut row_items = String::new();
                for (position, (row_index, x, y, w, h)) in layout.rows.iter().enumerate() {
                    if position > 0 {
                        rows.push(',');
                        row_items.push(',');
                    }
                    rows.push_str(&format!(
                        "{{\"x\":{:.1},\"y\":{:.1},\"w\":{:.1},\"h\":{:.1}}}",
                        x, y, w, h
                    ));
                    row_items.push_str(&row_index.to_string());
                }
                format!(
                    ",\"layout\":{{\"card\":{{\"x\":{:.1},\"y\":{:.1},\"w\":{:.1},\"h\":{:.1}}},\"rows\":[{}],\"row_items\":[{}],\"width\":{:.1},\"height\":{:.1},\"scale\":{:.2}}}",
                    layout.card_x,
                    layout.card_y,
                    layout.card_w,
                    layout.card_h,
                    rows,
                    row_items,
                    layout.width,
                    layout.height,
                    layout.scale
                )
            }
            None => String::new(),
        };
        format!(
            "{{\"ok\":true,\"mode\":{},\"query\":{},\"selected\":{},\"total\":{},\"status\":{}{},\"entries\":[{}]}}",
            logger::json_string(self.mode.name()),
            logger::json_string(&self.query),
            self.selected,
            self.visible.len(),
            match &self.status {
                Some(status) => logger::json_string(status),
                None => "null".to_string(),
            },
            layout_json,
            entries
        )
    }

    pub fn log_ready(&mut self) {
        if self.ready_logged {
            return;
        }
        if let Some(layout) = &self.layout {
            self.ready_logged = true;
            self.logger.event(
                "ready",
                &[
                    ("mode", logger::json_string(self.mode.name())),
                    ("width", format!("{:.0}", layout.width)),
                    ("height", format!("{:.0}", layout.height)),
                    ("scale", format!("{:.2}", layout.scale)),
                    ("total", self.visible.len().to_string()),
                ],
            );
        }
    }

    fn geometry(&self, width: f32, height: f32) -> Geometry {
        let (card_w, card_h_max) = match self.mode {
            Mode::Clipboard => ((width * 0.66).clamp(600.0, 1060.0), 660.0),
            Mode::Launcher => ((width * 0.62).clamp(560.0, 980.0), 640.0),
        };
        let card_h = (height * 0.74).min(card_h_max).max(280.0);
        let card_x = ((width - card_w) / 2.0).round();
        let card_y = ((height - card_h) / 2.0 - height * 0.02).round().max(20.0);
        let list_x = card_x + PAD;
        let list_y = card_y + PAD + 28.0 + SEARCH_H + 14.0;
        let list_w = card_w - PAD * 2.0;
        let list_h = (card_y + card_h - PAD - FOOTER_H - list_y).max(40.0);
        let row_h = self.mode.row_height();
        let capacity = (list_h / row_h).floor().max(1.0) as usize;
        Geometry {
            card_x,
            card_y,
            card_w,
            card_h,
            list_x,
            list_y,
            list_w,
            row_h,
            capacity,
        }
    }

    fn ensure_canvas(&mut self, width_px: u32, height_px: u32, scale: f32) {
        let recreate = match &self.canvas {
            Some(canvas) => canvas.width != width_px || canvas.height != height_px,
            None => true,
        };
        if recreate {
            let fonts = match self.fonts.take() {
                Some(fonts) => fonts,
                None => match self.canvas.take() {
                    Some(canvas) => canvas.fonts,
                    None => panic!("font database lost"),
                },
            };
            self.canvas = Some(Canvas::new(width_px, height_px, scale, fonts));
        } else if let Some(canvas) = &mut self.canvas {
            canvas.scale = scale;
        }
    }

    /// Draw one frame. `width_px`/`height_px` are buffer pixels and `scale` is
    /// the integer buffer scale; all layout is in logical pixels.
    pub fn draw(&mut self, width_px: u32, height_px: u32, scale: f32) {
        self.ensure_canvas(width_px, height_px, scale);
        let logical_w = width_px as f32 / scale;
        let logical_h = height_px as f32 / scale;
        let geo = self.geometry(logical_w, logical_h);

        // Keep selection inside the scroll window.
        if !self.visible.is_empty() {
            if self.selected < self.first_visible {
                self.first_visible = self.selected;
            }
            if self.selected >= self.first_visible + geo.capacity {
                self.first_visible = self.selected + 1 - geo.capacity;
            }
            let max_first = self.visible.len().saturating_sub(geo.capacity);
            if self.first_visible > max_first {
                self.first_visible = max_first;
            }
        } else {
            self.first_visible = 0;
        }

        let visible = self.visible.clone();
        let selected = self.selected;
        let first_visible = self.first_visible;
        let query = self.query.clone();
        let status = self.status.clone();
        let mode = self.mode;
        let canvas = self.canvas.as_mut().expect("canvas created");

        canvas.clear(colors::bg());
        canvas.fill_round_rect(
            geo.card_x + 3.0,
            geo.card_y + 7.0,
            geo.card_w,
            geo.card_h,
            18.0,
            colors::deep().with_alpha(150),
        );
        canvas.fill_round_rect_bordered(
            geo.card_x,
            geo.card_y,
            geo.card_w,
            geo.card_h,
            18.0,
            colors::border(),
            colors::surface(),
            1.5,
        );

        let title = match mode {
            Mode::Clipboard => "剪贴板历史",
            Mode::Launcher => "应用启动器",
        };
        canvas.draw_text(
            geo.card_x + PAD,
            geo.card_y + PAD + 4.0,
            title,
            TITLE_SIZE,
            colors::bright_fg(),
        );

        let search_y = geo.card_y + PAD + 28.0;
        let search_w = geo.card_w - PAD * 2.0;
        canvas.fill_round_rect(
            geo.card_x + PAD,
            search_y,
            search_w,
            SEARCH_H,
            10.0,
            colors::deep(),
        );
        canvas.fill_round_rect(
            geo.card_x + PAD,
            search_y,
            3.0,
            SEARCH_H,
            1.5,
            colors::blue(),
        );
        let search_text_x = geo.card_x + PAD + 16.0;
        let search_baseline = search_y + SEARCH_H / 2.0 + 5.0;
        if query.is_empty() {
            let hint = match mode {
                Mode::Clipboard => "输入以过滤文本；清空显示图片",
                Mode::Launcher => "输入应用名称或描述",
            };
            canvas.draw_text(
                search_text_x,
                search_baseline,
                hint,
                SEARCH_SIZE,
                colors::muted(),
            );
        } else {
            let width = canvas.draw_text(
                search_text_x,
                search_baseline,
                &query,
                SEARCH_SIZE,
                colors::bright_fg(),
            );
            canvas.fill_rect(
                search_text_x + width + 2.0,
                search_y + 10.0,
                2.0,
                SEARCH_H - 20.0,
                colors::blue(),
            );
        }

        let count = visible
            .len()
            .saturating_sub(first_visible)
            .min(geo.capacity);
        enum RowView {
            Text {
                text: String,
            },
            Image {
                id: i64,
                preview: String,
                dimensions: Option<(u32, u32)>,
            },
            App {
                name: String,
                subtitle: String,
            },
        }
        let row_views: Vec<(usize, RowView)> = (first_visible..(first_visible + count))
            .map(|position| {
                let item_index = visible[position];
                let view = match &self.items[item_index] {
                    Item::ClipText { text, .. } => RowView::Text {
                        text: text.replace('\n', " "),
                    },
                    Item::ClipImage {
                        id,
                        preview,
                        dimensions,
                        ..
                    } => RowView::Image {
                        id: *id,
                        preview: truncate_chars(preview, 90),
                        dimensions: *dimensions,
                    },
                    Item::App { app } => RowView::App {
                        name: app.name.clone(),
                        subtitle: app.subtitle(),
                    },
                };
                (position, view)
            })
            .collect();

        let mut rows = Vec::new();
        for (slot, (position, view)) in row_views.into_iter().enumerate() {
            let row_y = geo.list_y + slot as f32 * geo.row_h;
            if position == selected {
                canvas.fill_round_rect(
                    geo.list_x,
                    row_y + 2.0,
                    geo.list_w,
                    geo.row_h - 4.0,
                    9.0,
                    colors::selection(),
                );
                canvas.fill_round_rect(
                    geo.list_x + 6.0,
                    row_y + 10.0,
                    3.0,
                    geo.row_h - 20.0,
                    1.5,
                    colors::blue(),
                );
            }
            rows.push((position, geo.list_x, row_y, geo.list_w, geo.row_h));
            let text_x = geo.list_x + 18.0;
            let text_max_width = geo.list_w - 36.0;
            match view {
                RowView::Text { text } => {
                    canvas.draw_text_clipped(
                        text_x,
                        row_y + 30.0,
                        &text,
                        ROW_TEXT_SIZE,
                        colors::bright_fg(),
                        text_max_width,
                    );
                    canvas.draw_text(text_x, row_y + 54.0, "文本", ROW_SUB_SIZE, colors::muted());
                }
                RowView::Image {
                    id,
                    preview,
                    dimensions,
                } => {
                    let box_x = geo.list_x + 12.0;
                    let box_y = row_y + (geo.row_h - THUMB_H) / 2.0;
                    canvas.fill_round_rect(box_x, box_y, THUMB_W, THUMB_H, 6.0, colors::deep());
                    // Thumbnails are decoded when first displayed and cached,
                    // so a long history never decodes every image up front.
                    let cached = match thumb_cache_get(id) {
                        Some(value) => value,
                        None => {
                            let loaded = cliphist::decode(id)
                                .and_then(|bytes| cliphist::thumbnail(&bytes, 168, 112));
                            thumb_cache_put(id, loaded.clone());
                            loaded
                        }
                    };
                    match cached {
                        Ok(image) => {
                            let (target_w, target_h) = fit_aspect(
                                image.width(),
                                image.height(),
                                THUMB_W - 4.0,
                                THUMB_H - 4.0,
                            );
                            canvas.draw_rgba_image(
                                box_x + (THUMB_W - target_w) / 2.0,
                                box_y + (THUMB_H - target_h) / 2.0,
                                target_w,
                                target_h,
                                &image,
                            );
                        }
                        Err(_) => {
                            canvas.draw_text(
                                box_x + 10.0,
                                box_y + THUMB_H / 2.0 + 4.0,
                                "无法解码",
                                ROW_SUB_SIZE,
                                colors::red(),
                            );
                        }
                    }
                    let image_text_x = box_x + THUMB_W + 14.0;
                    let image_text_max = geo.list_w - (image_text_x - geo.list_x) - 20.0;
                    let label = match dimensions {
                        Some((width, height)) => format!("图片 {}×{}", width, height),
                        None => "图片".to_string(),
                    };
                    canvas.draw_text_clipped(
                        image_text_x,
                        row_y + 30.0,
                        &label,
                        ROW_TEXT_SIZE,
                        colors::bright_fg(),
                        image_text_max,
                    );
                    canvas.draw_text_clipped(
                        image_text_x,
                        row_y + 54.0,
                        &preview,
                        ROW_SUB_SIZE,
                        colors::muted(),
                        image_text_max,
                    );
                }
                RowView::App { name, subtitle } => {
                    let subtitle_width = if subtitle.is_empty() {
                        0.0
                    } else {
                        (text_max_width * 0.42).max(80.0)
                    };
                    let name_width = text_max_width - subtitle_width;
                    canvas.draw_text_clipped(
                        text_x,
                        row_y + geo.row_h / 2.0 + 5.0,
                        &name,
                        ROW_TEXT_SIZE,
                        colors::bright_fg(),
                        name_width,
                    );
                    if !subtitle.is_empty() {
                        let subtitle_x = geo.list_x + geo.list_w - 18.0 - subtitle_width;
                        canvas.draw_text_clipped(
                            subtitle_x,
                            row_y + geo.row_h / 2.0 + 5.0,
                            &subtitle,
                            ROW_SUB_SIZE,
                            colors::muted(),
                            subtitle_width,
                        );
                    }
                }
            }
        }

        if visible.is_empty() {
            let message = if status.is_some() {
                status.clone().unwrap_or_default()
            } else if query.is_empty() {
                match mode {
                    Mode::Clipboard => "剪贴板历史为空".to_string(),
                    Mode::Launcher => "没有找到应用".to_string(),
                }
            } else {
                "没有匹配的项目".to_string()
            };
            let color = if status.is_some() {
                colors::red()
            } else {
                colors::muted()
            };
            canvas.draw_text_clipped(
                geo.list_x,
                geo.list_y + 40.0,
                &message,
                ROW_TEXT_SIZE,
                color,
                geo.list_w,
            );
        }

        if visible.len() > geo.capacity {
            let track_x = geo.card_x + geo.card_w - PAD + 6.0;
            let track_y = geo.list_y;
            let track_h = geo.capacity as f32 * geo.row_h - 8.0;
            canvas.fill_round_rect(track_x, track_y, 3.0, track_h, 1.5, colors::deep());
            let thumb_h = (track_h * geo.capacity as f32 / visible.len() as f32)
                .max(24.0)
                .min(track_h);
            let max_first = (visible.len() - geo.capacity) as f32;
            let progress = if max_first > 0.0 {
                first_visible as f32 / max_first
            } else {
                0.0
            };
            let thumb_y = track_y + (track_h - thumb_h) * progress;
            canvas.fill_round_rect(track_x, thumb_y, 3.0, thumb_h, 1.5, colors::blue());
        }

        let footer_baseline = geo.card_y + geo.card_h - PAD + 2.0;
        let hints = match mode {
            Mode::Clipboard => "↑/↓ 选择 · Enter 复制 · Esc 关闭",
            Mode::Launcher => "↑/↓ 选择 · Enter 启动 · Esc 关闭",
        };
        canvas.draw_text(
            geo.card_x + PAD,
            footer_baseline,
            hints,
            FOOTER_SIZE,
            colors::muted(),
        );
        let count_text = format!("{} 项", visible.len());
        let count_width = canvas.text_width(&count_text, FOOTER_SIZE);
        canvas.draw_text(
            geo.card_x + geo.card_w - PAD - count_width,
            footer_baseline,
            &count_text,
            FOOTER_SIZE,
            colors::muted(),
        );

        self.first_visible = first_visible;
        self.layout = Some(Layout {
            width: logical_w,
            height: logical_h,
            scale,
            card_x: geo.card_x,
            card_y: geo.card_y,
            card_w: geo.card_w,
            card_h: geo.card_h,
            capacity: geo.capacity,
            rows,
        });
    }
}

fn parse_dimensions(preview: &str) -> Option<(u32, u32)> {
    for token in preview.split_whitespace().rev() {
        if let Some((width, height)) = token.split_once('x') {
            if let (Ok(width), Ok(height)) = (width.parse::<u32>(), height.parse::<u32>()) {
                return Some((width, height));
            }
        }
    }
    None
}

fn fit_aspect(width: u32, height: u32, max_width: f32, max_height: f32) -> (f32, f32) {
    let scale_x = max_width / width as f32;
    let scale_y = max_height / height as f32;
    let scale = scale_x.min(scale_y).max(0.01);
    (
        (width as f32 * scale).max(1.0),
        (height as f32 * scale).max(1.0),
    )
}

fn truncate_chars(text: &str, max: usize) -> String {
    if text.chars().count() <= max {
        text.to_string()
    } else {
        let mut out: String = text.chars().take(max).collect();
        out.push('…');
        out
    }
}

fn unescape_ipc(text: &str) -> String {
    text.replace("\\n", "\n").replace("\\t", "\t")
}

// The thumbnail cache lives in thread-local storage because it is only touched
// while drawing on the main thread. Keeping it out of `Overlay` avoids cloning
// decoded bitmaps when the item table is iterated mutably.
thread_local! {
    static THUMBS: std::cell::RefCell<std::collections::HashMap<i64, Result<image::RgbaImage, String>>> =
        std::cell::RefCell::new(std::collections::HashMap::new());
}

fn thumb_cache_get(id: i64) -> Option<Result<image::RgbaImage, String>> {
    THUMBS.with(|cache| cache.borrow().get(&id).cloned())
}

fn thumb_cache_put(id: i64, value: Result<image::RgbaImage, String>) {
    THUMBS.with(|cache| {
        cache.borrow_mut().insert(id, value);
    });
}
