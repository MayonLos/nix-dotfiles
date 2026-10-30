//! Chinese-first terminal interface for the `mcsrv-mayon` command.
//! All potentially slow CLI calls run on worker threads; drawing stays responsive.
use anyhow::{Context, Result};
use crossterm::{
    cursor::Show,
    event::{
        self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEvent, KeyEventKind,
        KeyModifiers, MouseButton, MouseEventKind,
    },
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout, Rect},
    style::{Modifier, Style},
    text::{Line, Span, Text},
    widgets::{Block, Borders, Cell, Clear, Paragraph, Row, Table, Wrap},
    Frame, Terminal,
};
use serde::{Deserialize, Deserializer};
use serde_json::Value;
use std::{
    io,
    path::PathBuf,
    process::{Command, Stdio},
    sync::mpsc::{self, Receiver, Sender},
    thread,
    time::{Duration, Instant},
};
use unicode_segmentation::UnicodeSegmentation;
use unicode_width::UnicodeWidthStr;

#[allow(dead_code)]
mod palette {
    include!(concat!(env!("OUT_DIR"), "/palette.rs"));
}
use palette::*;

const PAGES: [&str; 6] = ["实例", "控制台", "玩家", "备份", "模组", "联机"];
const HELP: &str = "数字键 1–6 切页 · j/k 或 ↑/↓ 选择 · 鼠标点击\n\
n 新建实例 · s 启动 · x 停止 · b 立即备份 · r 回滚\n\
/ 过滤/搜索 · Enter 执行 · Ctrl+A 清空默认项 · ? 帮助 · q 退出\n\
控制台输入指令后 Enter 发送；玩家页 Enter 预填 op，a 自定义命令；支持 whitelist/op/kick/ban。\n\
备份页 v 设置保留数；联机页 l/L 切换局域网，c 设置备份间隔，t 显示 Tailscale 接入说明。回滚要输入快照 ID。";

#[derive(Clone, Debug, Deserialize)]
struct Instance {
    name: String,
    #[serde(default)]
    kind: String,
    #[serde(default)]
    version: String,
    #[serde(default)]
    memory_mb: u64,
    #[serde(default)]
    port: u16,
    #[serde(default)]
    online_mode: bool,
    #[serde(default)]
    whitelist: bool,
    #[serde(default)]
    java: String,
    #[serde(default)]
    backup_minutes: u64,
    #[serde(default)]
    lan: bool,
}

#[derive(Clone, Debug, Default, Deserialize)]
struct Status {
    #[serde(default)]
    state: String,
    #[serde(default, deserialize_with = "deserialize_players")]
    players: Vec<String>,
    #[serde(default, deserialize_with = "deserialize_text")]
    memory: String,
    #[serde(default, deserialize_with = "deserialize_text")]
    tps: String,
    #[serde(default, deserialize_with = "deserialize_text")]
    mspt: String,
    #[serde(default, deserialize_with = "deserialize_addresses")]
    addresses: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Modal {
    Help,
    Output,
    Input(InputKind),
    ConfirmCreate,
    ConfirmRestore,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum InputKind {
    Filter,
    Create,
    Console,
    ModSearch,
    ModInstall,
    Restore,
    PrismDiff,
    Config,
    Retention,
}

fn deserialize_text<'de, D>(deserializer: D) -> std::result::Result<String, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Value::deserialize(deserializer)?;
    Ok(match value {
        Value::String(value) => value,
        Value::Number(value) => value.to_string(),
        Value::Bool(value) => value.to_string(),
        Value::Null => String::new(),
        other => other.to_string(),
    })
}

fn deserialize_players<'de, D>(deserializer: D) -> std::result::Result<Vec<String>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Value::deserialize(deserializer)?;
    let names = match value {
        Value::Array(values) => values
            .into_iter()
            .filter_map(|value| value.as_str().map(str::to_owned))
            .collect(),
        Value::String(text) => {
            let tail = text
                .rsplit_once(':')
                .map_or(text.as_str(), |(_, tail)| tail)
                .trim();
            if tail.is_empty() || tail == "—" || tail.to_lowercase().contains("0 players") {
                Vec::new()
            } else {
                tail.split(',')
                    .map(str::trim)
                    .filter(|name| !name.is_empty())
                    .map(str::to_owned)
                    .collect()
            }
        }
        _ => Vec::new(),
    };
    Ok(names)
}

fn deserialize_addresses<'de, D>(deserializer: D) -> std::result::Result<String, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Value::deserialize(deserializer)?;
    Ok(match value {
        Value::Array(values) => values
            .into_iter()
            .filter_map(|value| value.as_str().map(str::to_owned))
            .collect::<Vec<_>>()
            .join("\n"),
        Value::String(text) => text,
        Value::Null => String::new(),
        other => other.to_string(),
    })
}

struct Reply {
    action: String,
    result: Result<String, String>,
}
struct App {
    root: PathBuf,
    demo: bool,
    executable: PathBuf,
    tx: Sender<Reply>,
    rx: Receiver<Reply>,
    busy: bool,
    page: usize,
    /// Instance choice persists across pages; `selected` is only a row within the current page.
    instance_selected: usize,
    selected: usize,
    instances: Vec<Instance>,
    status: Status,
    logs: Vec<String>,
    backups: Vec<Value>,
    mods: Vec<Value>,
    filter: Option<String>,
    input: String,
    prompt: String,
    modal: Option<Modal>,
    message: String,
    scroll: usize,
    next_refresh: Instant,
    exit_when_idle: bool,
    create_step: usize,
    create_values: Vec<String>,
    create_name: String,
    restore_snapshot: String,
    output_title: String,
    output_lines: Vec<String>,
    output_scroll: usize,
}
impl App {
    fn new(root: PathBuf, demo: bool, executable: PathBuf) -> Self {
        let (tx, rx) = mpsc::channel();
        Self {
            root,
            demo,
            executable,
            tx,
            rx,
            busy: false,
            page: 0,
            instance_selected: 0,
            selected: 0,
            instances: Vec::new(),
            status: Status::default(),
            logs: Vec::new(),
            backups: Vec::new(),
            mods: Vec::new(),
            filter: None,
            input: String::new(),
            prompt: String::new(),
            modal: None,
            message: String::from("正在读取服务器实例…"),
            scroll: 0,
            next_refresh: Instant::now(),
            exit_when_idle: false,
            create_step: 0,
            create_values: Vec::new(),
            create_name: String::new(),
            restore_snapshot: String::new(),
            output_title: String::new(),
            output_lines: Vec::new(),
            output_scroll: 0,
        }
    }
    fn selected_instance(&self) -> Option<&Instance> {
        self.instances.get(self.instance_selected)
    }
    fn selected_name(&self) -> Option<String> {
        self.selected_instance()
            .map(|instance| instance.name.clone())
    }
    fn visible_instances(&self) -> Vec<usize> {
        self.instances
            .iter()
            .enumerate()
            .filter(|(_, instance)| {
                self.filter.as_ref().is_none_or(|filter| {
                    instance
                        .name
                        .to_lowercase()
                        .contains(&filter.to_lowercase())
                        || instance
                            .kind
                            .to_lowercase()
                            .contains(&filter.to_lowercase())
                        || instance
                            .version
                            .to_lowercase()
                            .contains(&filter.to_lowercase())
                })
            })
            .map(|(index, _)| index)
            .collect()
    }
    fn select_instance_row(&mut self, row: usize) {
        let Some(&index) = self.visible_instances().get(row) else {
            return;
        };
        if self.busy && index != self.instance_selected {
            self.message = "后台操作完成前暂不能切换实例".into();
            return;
        }
        self.selected = row;
        if index == self.instance_selected {
            return;
        }
        self.instance_selected = index;
        self.clear_instance_data();
        self.selected = row;
        self.refresh_selected();
    }
    fn clear_instance_data(&mut self) {
        self.status = Status::default();
        self.logs.clear();
        self.backups.clear();
        self.mods.clear();
        self.selected = 0;
    }
    fn apply_filter(&mut self, filter: Option<String>) {
        let previous = self.instance_selected;
        let next_filter = filter;
        let visible = self
            .instances
            .iter()
            .enumerate()
            .filter(|(_, instance)| {
                next_filter.as_ref().is_none_or(|filter| {
                    instance
                        .name
                        .to_lowercase()
                        .contains(&filter.to_lowercase())
                        || instance
                            .kind
                            .to_lowercase()
                            .contains(&filter.to_lowercase())
                        || instance
                            .version
                            .to_lowercase()
                            .contains(&filter.to_lowercase())
                })
            })
            .map(|(index, _)| index)
            .collect::<Vec<_>>();
        let next = if visible.contains(&previous) {
            previous
        } else {
            visible.first().copied().unwrap_or(previous)
        };
        if self.busy && next != previous {
            self.message = "后台操作完成前不能切换到筛选出的其他实例".into();
            return;
        }
        self.filter = next_filter;
        if let Some(row) = visible.iter().position(|index| *index == next) {
            self.selected = row;
        } else {
            self.selected = 0;
        }
        if next != previous {
            self.instance_selected = next;
            self.clear_instance_data();
            self.selected = visible.iter().position(|index| *index == next).unwrap_or(0);
            self.refresh_selected();
        }
    }
    fn spawn(&mut self, action: &str, args: Vec<String>) {
        if self.demo {
            if !matches!(
                action,
                "读取实例" | "刷新状态" | "读取控制台" | "读取备份" | "读取模组"
            ) {
                self.message = format!("演示操作：模拟 {action}，未执行真实操作");
            }
            return;
        }
        if self.busy {
            self.message = "后台操作仍在执行，请稍候".into();
            return;
        }
        let executable = self.executable.clone();
        let root = self.root.clone();
        let tx = self.tx.clone();
        let action_name = action.to_owned();
        self.busy = true;
        self.message = format!("正在执行：{action}…");
        thread::spawn(move || {
            let result = Command::new(executable)
                .arg("--root")
                .arg(root)
                .args(args)
                .stdin(Stdio::null())
                .stdout(Stdio::piped())
                .stderr(Stdio::piped())
                .output()
                .map_err(|error| format!("无法启动命令：{error}"))
                .and_then(|output| {
                    if output.status.success() {
                        Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
                    } else {
                        let error = String::from_utf8_lossy(&output.stderr).trim().to_string();
                        Err(if error.is_empty() {
                            format!("命令退出码：{}", output.status)
                        } else {
                            error
                        })
                    }
                });
            let _ = tx.send(Reply {
                action: action_name,
                result,
            });
        });
    }
    fn list(&mut self) {
        self.spawn("读取实例", vec!["list".into()]);
    }
    fn refresh_selected(&mut self) {
        self.next_refresh = Instant::now() + Duration::from_secs(3);
        let Some(name) = self.selected_name() else {
            return;
        };
        match self.page {
            1 => self.spawn("读取控制台", vec!["logs".into(), name]),
            3 => self.spawn("读取备份", vec!["backups".into(), name]),
            _ => self.spawn("刷新状态", vec!["status".into(), name]),
        }
    }
    fn pull(&mut self) {
        while let Ok(reply) = self.rx.try_recv() {
            self.busy = false;
            match reply.result {
                Ok(output) => {
                    if is_mod_result_action(&reply.action) {
                        self.show_output(&reply.action, &output);
                    } else {
                        self.message = if matches!(
                            reply.action.as_str(),
                            "读取实例" | "刷新状态" | "读取控制台" | "读取备份" | "读取模组"
                        ) {
                            format!("{}：已更新", reply.action)
                        } else if output.is_empty() {
                            format!("{}：完成", reply.action)
                        } else {
                            output.lines().next().unwrap_or("操作完成").to_string()
                        };
                        self.accept_output(&reply.action, &output);
                    }
                }
                Err(error) => {
                    self.message = format!(
                        "{}：{}",
                        reply.action,
                        error.lines().next().unwrap_or("操作失败")
                    );
                    if is_mod_result_action(&reply.action) {
                        self.show_output(&reply.action, &error);
                    }
                }
            }
            self.next_refresh = Instant::now() + Duration::from_secs(1);
        }
    }
    fn accept_output(&mut self, action: &str, output: &str) {
        if is_mod_result_action(action) {
            self.show_output(action, output);
            return;
        }
        if matches!(
            action,
            "创建实例" | "更新定时备份" | "更新快照保留数" | "开启局域网放行" | "关闭局域网放行"
        ) {
            self.list();
            return;
        }
        if action == "读取实例" {
            let previous_name = self.selected_name();
            match serde_json::from_str::<Vec<Instance>>(output) {
                Ok(instances) => {
                    self.instances = instances;
                    self.instance_selected = previous_name
                        .and_then(|name| {
                            self.instances
                                .iter()
                                .position(|instance| instance.name == name)
                        })
                        .unwrap_or_else(|| {
                            self.instance_selected
                                .min(self.instances.len().saturating_sub(1))
                        });
                    self.selected = self
                        .visible_instances()
                        .iter()
                        .position(|index| *index == self.instance_selected)
                        .unwrap_or(0);
                    self.status = Status::default();
                }
                Err(error) => self.message = format!("实例列表格式错误：{error}"),
            }
            return;
        }
        if action == "读取控制台" {
            self.logs = output.lines().rev().take(500).map(str::to_string).collect();
            self.logs.reverse();
            self.scroll = self.logs.len().saturating_sub(1);
            return;
        }
        if action == "读取备份" {
            match serde_json::from_str::<Value>(output) {
                Ok(value) => self.backups = value.as_array().cloned().unwrap_or_default(),
                Err(error) => self.message = format!("备份列表格式错误：{error}"),
            }
            return;
        }
        if action == "读取模组" {
            match serde_json::from_str::<Value>(output) {
                Ok(value) => self.mods = value.as_array().cloned().unwrap_or_default(),
                Err(error) => self.message = format!("模组搜索结果格式错误：{error}"),
            }
            return;
        }
        if action == "刷新状态" {
            match serde_json::from_str::<Status>(output) {
                Ok(status) => self.status = status,
                Err(error) => self.message = format!("服务器状态格式错误：{error}"),
            }
        }
    }
    fn show_output(&mut self, action: &str, output: &str) {
        self.output_title = match action {
            "比较 Prism 模组" => "Prism 模组差异".into(),
            "更新模组" => "模组更新结果".into(),
            "安装模组" => "模组安装结果".into(),
            _ => "操作结果".into(),
        };
        self.output_lines = serde_json::from_str::<Vec<String>>(output)
            .unwrap_or_else(|_| output.lines().map(str::to_owned).collect());
        if self.output_lines.is_empty() {
            self.output_lines.push("没有输出结果。".into());
        }
        self.output_scroll = 0;
        self.message = format!("{}：{} 条结果", self.output_title, self.output_lines.len());
        self.modal = Some(Modal::Output);
    }
    fn poll_tick(&mut self) {
        self.pull();
        if Instant::now() >= self.next_refresh && !self.busy {
            if self.instances.is_empty() {
                self.list();
            } else {
                self.refresh_selected();
            }
        }
    }
    fn switch_page(&mut self, page: usize) {
        self.page = page.min(PAGES.len() - 1);
        self.selected = if self.page == 0 {
            self.visible_instances()
                .iter()
                .position(|index| *index == self.instance_selected)
                .unwrap_or(0)
        } else {
            0
        };
        self.scroll = 0;
        self.refresh_selected();
    }
    fn start_create(&mut self) {
        self.create_step = 0;
        self.create_values.clear();
        self.input.clear();
        self.prompt = "实例名称（仅字母、数字、-、_）".into();
        self.modal = Some(Modal::Input(InputKind::Create));
    }
    fn next_create(&mut self, value: String) {
        let step = self.create_step;
        if value.trim().is_empty() && !matches!(step, 3) {
            self.message = "此项不能为空".into();
            return;
        }
        if step == 0 {
            if !value
                .chars()
                .all(|character| character.is_ascii_alphanumeric() || "-_".contains(character))
            {
                self.message = "名称仅可包含英文字母、数字、- 和 _".into();
                return;
            }
            self.create_name = value.trim().to_string();
        }
        self.create_values.push(value.trim().to_string());
        self.create_step += 1;
        let prompts = [
            "类型：vanilla / paper / fabric / forge / neoforge / gtnh / mrpack / prism（默认 paper）",
            "Minecraft 版本或整合包版本（默认 latest；GTNH 默认 2.9.0-RC-2）",
            "服务器包/本地 Prism 实例路径或 URL（无需时留空）",
            "内存 MiB（512–24576；默认 Paper 2048、GTNH 8192）",
            "游戏端口（1–55535，默认 25565）",
            "正版验证 online-mode：输入 y 开启，n 离线",
            "启用白名单：输入 y 开启，n 关闭",
            "Aikar JVM 参数：仅 Paper 可选，输入 y 启用，n 跳过",
        ];
        if self.create_step <= prompts.len() {
            self.prompt = prompts[self.create_step - 1].into();
            self.input.clear();
            self.input = match self.create_step {
                1 => "paper",
                2 if self.create_values.get(1).is_some_and(|kind| kind == "gtnh") => "2.9.0-RC-2",
                2 => "latest",
                4 if self.create_values.get(1).is_some_and(|kind| kind == "gtnh") => "8192",
                4 => "2048",
                5 => "25565",
                6 | 7 => "y",
                8 if self
                    .create_values
                    .get(1)
                    .is_some_and(|kind| kind == "paper") =>
                {
                    "y"
                }
                8 => "n",
                _ => "",
            }
            .into();
        } else {
            self.prompt = "确认接受 Minecraft EULA 并创建？请输入 YES".into();
            self.input.clear();
            self.modal = Some(Modal::ConfirmCreate);
        }
    }
    fn submit_create(&mut self) {
        if self.input != "YES" {
            self.message = "请输入 YES 明确接受 EULA 后继续".into();
            return;
        }
        self.modal = None;
        let values = self.create_values.clone();
        let name = self.create_name.clone();
        let mut args = vec![
            "create".into(),
            name,
            "--kind".into(),
            values[1].clone(),
            "--version".into(),
            values[2].clone(),
        ];
        // The prompt order is name, kind, version, source, memory, port, online mode, whitelist, Aikar.
        if !values[3].is_empty() {
            args.extend(["--source".into(), values[3].clone()]);
        }
        args.extend([
            "--memory".into(),
            values[4].clone(),
            "--port".into(),
            values[5].clone(),
        ]);
        if values[6].eq_ignore_ascii_case("n") {
            args.push("--offline".into());
        }
        if values[7].eq_ignore_ascii_case("y") {
            args.push("--whitelist".into());
        }
        if values[8].eq_ignore_ascii_case("y") {
            args.push("--aikar".into());
        }
        args.push("--accept-eula".into());
        self.spawn("创建实例", args);
    }
    fn open_input(&mut self, kind: InputKind, prompt: &str) {
        self.input.clear();
        self.prompt = prompt.to_string();
        self.modal = Some(Modal::Input(kind));
    }
    fn selected_backup(&self) -> Option<String> {
        self.backups.get(self.selected).and_then(|snapshot| {
            snapshot
                .get("short_id")
                .or_else(|| snapshot.get("id"))
                .or_else(|| snapshot.get("snapshot"))
                .and_then(Value::as_str)
                .map(str::to_owned)
        })
    }
    fn selected_mod_id(&self) -> Option<String> {
        self.mods.get(self.selected).and_then(|value| {
            value
                .get("project_id")
                .or_else(|| value.get("id"))
                .and_then(Value::as_str)
                .map(str::to_owned)
        })
    }
    fn handle_input_submit(&mut self, kind: InputKind) {
        let value = self.input.trim().to_owned();
        match kind {
            InputKind::Filter => {
                self.modal = None;
                self.apply_filter((!value.is_empty()).then_some(value));
            }
            InputKind::Create => self.next_create(value),
            InputKind::Console => {
                self.modal = None;
                if let Some(name) = self.selected_name() {
                    self.spawn("发送命令", vec!["command".into(), name, value]);
                }
            }
            InputKind::ModSearch => {
                self.modal = None;
                if let Some(name) = self.selected_name() {
                    self.spawn(
                        "读取模组",
                        vec!["mods".into(), name, "search".into(), value],
                    );
                }
            }
            InputKind::ModInstall => {
                self.modal = None;
                if let (Some(name), false) = (self.selected_name(), value.is_empty()) {
                    self.spawn(
                        "安装模组",
                        vec!["mods".into(), name, "install".into(), value],
                    );
                }
            }
            InputKind::Restore => {
                if value.is_empty() {
                    self.message = "快照 ID 不能为空".into();
                    return;
                }
                self.restore_snapshot = value;
                self.prompt = format!(
                    "恢复快照 {}？将先对当前实例备份。输入 RESTORE",
                    self.restore_snapshot
                );
                self.input.clear();
                self.modal = Some(Modal::ConfirmRestore);
            }
            InputKind::Config => {
                let Ok(minutes) = value.parse::<u32>() else {
                    self.message = "请输入备份间隔分钟数（0–1440，0 表示关闭）".into();
                    return;
                };
                if minutes > 1440 {
                    self.message = "备份间隔须为 0–1440 分钟，0 表示关闭".into();
                    return;
                }
                self.modal = None;
                if let Some(name) = self.selected_name() {
                    self.spawn(
                        "更新定时备份",
                        vec![
                            "config".into(),
                            name,
                            "--backup-minutes".into(),
                            minutes.to_string(),
                        ],
                    );
                }
            }
            InputKind::Retention => {
                let Ok(count) = value.parse::<u32>() else {
                    self.message = "请输入保留快照数（1–1000）".into();
                    return;
                };
                if !(1..=1000).contains(&count) {
                    self.message = "快照保留数须为 1–1000".into();
                    return;
                }
                self.modal = None;
                if let Some(name) = self.selected_name() {
                    self.spawn(
                        "更新快照保留数",
                        vec![
                            "config".into(),
                            name,
                            "--keep-last".into(),
                            count.to_string(),
                        ],
                    );
                }
            }
            InputKind::PrismDiff => {
                self.modal = None;
                if let Some(name) = self.selected_name() {
                    self.spawn(
                        "比较 Prism 模组",
                        vec!["mods".into(), name, "diff".into(), value],
                    );
                }
            }
        }
    }
    fn handle_key(&mut self, key: KeyEvent) -> bool {
        if key.kind == KeyEventKind::Release {
            return false;
        }
        if let Some(modal) = self.modal {
            match modal {
                Modal::Help => {
                    if matches!(key.code, KeyCode::Esc | KeyCode::Enter | KeyCode::Char('?')) {
                        self.modal = None;
                    }
                }
                Modal::Output => match key.code {
                    KeyCode::Esc | KeyCode::Char('q') | KeyCode::Char('?') => self.modal = None,
                    KeyCode::Up | KeyCode::Char('k') => {
                        self.output_scroll = self.output_scroll.saturating_sub(1);
                    }
                    KeyCode::Down | KeyCode::Char('j') => {
                        self.output_scroll =
                            (self.output_scroll + 1).min(self.output_lines.len().saturating_sub(1));
                    }
                    _ => {}
                },
                Modal::Input(kind) => match key.code {
                    KeyCode::Esc => self.modal = None,
                    KeyCode::Enter => self.handle_input_submit(kind),
                    KeyCode::Backspace => {
                        self.input.pop();
                    }
                    KeyCode::Char('a') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                        self.input.clear();
                    }
                    KeyCode::Char(character) => self.input.push(character),
                    _ => {}
                },
                Modal::ConfirmCreate => match key.code {
                    KeyCode::Esc => self.modal = None,
                    KeyCode::Enter => self.submit_create(),
                    KeyCode::Backspace => {
                        self.input.pop();
                    }
                    KeyCode::Char('a') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                        self.input.clear();
                    }
                    KeyCode::Char(character) => self.input.push(character),
                    _ => {}
                },
                Modal::ConfirmRestore => match key.code {
                    KeyCode::Esc => self.modal = None,
                    KeyCode::Enter if self.input == "RESTORE" => {
                        self.modal = None;
                        if let Some(name) = self.selected_name() {
                            let snapshot = self.restore_snapshot.clone();
                            self.spawn(
                                "回滚存档",
                                vec![
                                    "restore".into(),
                                    name,
                                    snapshot.clone(),
                                    "--confirm".into(),
                                    snapshot,
                                ],
                            );
                        }
                    }
                    KeyCode::Backspace => {
                        self.input.pop();
                    }
                    KeyCode::Char('a') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                        self.input.clear();
                    }
                    KeyCode::Char(character) => self.input.push(character),
                    _ => {}
                },
            }
            return false;
        }
        match key.code {
            KeyCode::Char('q') if self.busy => {
                self.exit_when_idle = true;
                self.message = "当前操作完成后退出；再次 q 也会等待完成".into();
            }
            KeyCode::Char('q') => return true,
            KeyCode::Char('?') => self.modal = Some(Modal::Help),
            KeyCode::Char('/') => {
                if self.page == 4 {
                    self.open_input(InputKind::ModSearch, "按 Modrinth 项目名搜索服务端模组");
                } else {
                    self.open_input(InputKind::Filter, "过滤实例名称、类型或版本");
                }
            }
            KeyCode::Char('n') if self.page == 0 => self.start_create(),
            KeyCode::Char('s') if self.page == 0 => {
                if let Some(name) = self.selected_name() {
                    self.spawn("启动服务器", vec!["start".into(), name]);
                }
            }
            KeyCode::Char('x') if self.page == 0 => {
                if let Some(name) = self.selected_name() {
                    self.spawn("停止服务器", vec!["stop".into(), name]);
                }
            }
            KeyCode::Char('b') if self.page == 3 => {
                if let Some(name) = self.selected_name() {
                    self.spawn("创建备份", vec!["backup".into(), name]);
                }
            }
            KeyCode::Char('v') if self.page == 3 => {
                self.open_input(InputKind::Retention, "保留快照数（默认 20，输入 1–1000）");
                self.input = "20".into();
            }
            KeyCode::Char('r') if self.page == 3 => {
                if self.backups.is_empty() {
                    self.message = "没有可恢复的备份".into();
                } else {
                    let id = self.selected_backup().unwrap_or_default();
                    self.input = id;
                    self.open_input(
                        InputKind::Restore,
                        "确认快照 ID（默认当前选择），Enter 后还需输入 RESTORE",
                    );
                    self.input = self.selected_backup().unwrap_or_default();
                }
            }
            KeyCode::Char('i') if self.page == 4 => {
                if let Some(id) = self.selected_mod_id() {
                    self.input = id;
                    self.modal = Some(Modal::Input(InputKind::ModInstall));
                    self.prompt = "安装 Modrinth 项目 ID（可编辑）".into();
                }
            }
            KeyCode::Char('u') if self.page == 4 => {
                if let Some(name) = self.selected_name() {
                    self.spawn("更新模组", vec!["mods".into(), name, "update".into()]);
                }
            }
            KeyCode::Char('d') if self.page == 4 => {
                self.open_input(InputKind::PrismDiff, "Prism 实例 mods/ 路径（只读比较）");
            }
            KeyCode::Char('l' | 'L') if self.page == 5 => {
                if let Some(server) = self.selected_instance().cloned() {
                    if self.status.state.contains("运行") || self.status.state.contains("启动")
                    {
                        self.message = "请先停止服务器，再切换局域网临时放行".into();
                    } else {
                        let mut args = vec!["config".into(), server.name];
                        args.push(if server.lan { "--no-lan" } else { "--lan" }.into());
                        self.spawn(
                            if server.lan {
                                "关闭局域网放行"
                            } else {
                                "开启局域网放行"
                            },
                            args,
                        );
                    }
                }
            }
            KeyCode::Char('t') if self.page == 5 => {
                if let Some(name) = self.selected_name() {
                    self.message = format!(
                        "Tailscale 需先启用主机服务；运行 mcsrv-mayon network {name} --connect 连接，登录 URL 只在终端显示。"
                    );
                }
            }
            KeyCode::Char('c') if self.page == 5 => {
                if let Some(name) = self.selected_name() {
                    self.open_input(
                        InputKind::Config,
                        "定时备份间隔（分钟，0–1440；0 表示关闭）",
                    );
                    self.input = "30".into();
                    self.prompt = format!("修改 {name} 的定时备份间隔；输入分钟数后 Enter 保存");
                }
            }
            KeyCode::Char(character @ '1'..='6') => {
                self.switch_page((character as usize) - ('1' as usize))
            }
            KeyCode::Tab => self.switch_page((self.page + 1) % PAGES.len()),
            KeyCode::BackTab => self.switch_page((self.page + PAGES.len() - 1) % PAGES.len()),
            KeyCode::Up | KeyCode::Char('k') => {
                if self.page == 0 {
                    self.select_instance_row(self.selected.saturating_sub(1));
                } else {
                    self.selected = self.selected.saturating_sub(1);
                }
                if self.page == 1 {
                    self.scroll = self.scroll.saturating_sub(1);
                }
                if self.page != 0 {
                    self.refresh_selected();
                }
            }
            KeyCode::Down | KeyCode::Char('j') => {
                let max = match self.page {
                    0 => self.visible_instances().len(),
                    1 => self.logs.len(),
                    2 => self.status.players.len(),
                    3 => self.backups.len(),
                    4 => self.mods.len(),
                    _ => 0,
                };
                if max > 0 {
                    if self.page == 0 {
                        self.select_instance_row((self.selected + 1).min(max - 1));
                    } else {
                        self.selected = (self.selected + 1).min(max - 1);
                    }
                }
                if self.page == 1 {
                    self.scroll = (self.scroll + 1).min(self.logs.len().saturating_sub(1));
                }
                if self.page != 0 {
                    self.refresh_selected();
                }
            }
            KeyCode::Enter if self.page == 1 => {
                self.open_input(InputKind::Console, "输入 Minecraft 服务端命令（不含 /）");
            }
            KeyCode::Enter if self.page == 2 => self.open_player_action(),
            KeyCode::Char('a') if self.page == 2 => {
                self.open_input(
                    InputKind::Console,
                    "发送玩家管理命令（whitelist / op / kick / ban 等）",
                );
            }
            KeyCode::Enter if self.page == 4 => {
                if let Some(id) = self.selected_mod_id() {
                    self.input = id;
                    self.prompt = "安装 Modrinth 项目 ID".into();
                    self.modal = Some(Modal::Input(InputKind::ModInstall));
                }
            }
            _ => {}
        }
        false
    }
    fn open_player_action(&mut self) {
        let Some(player) = self.status.players.get(self.selected).cloned() else {
            return;
        };
        let commands = if self.status.state.contains("运行") || self.status.state == "running" {
            format!("目标玩家：{player}\n输入命令：whitelist add/remove {player}、op/deop {player}、kick/ban {player}")
        } else {
            format!("目标玩家：{player}\n请输入服务器命令；实例未运行时无法踢出玩家")
        };
        self.prompt = commands;
        self.input = format!("op {player}");
        self.modal = Some(Modal::Input(InputKind::Console));
    }
    fn mouse(&mut self, kind: MouseEventKind, column: u16, row: u16) {
        if self.modal == Some(Modal::Output) {
            match kind {
                MouseEventKind::ScrollDown => {
                    self.output_scroll =
                        (self.output_scroll + 3).min(self.output_lines.len().saturating_sub(1));
                }
                MouseEventKind::ScrollUp => {
                    self.output_scroll = self.output_scroll.saturating_sub(3);
                }
                _ => {}
            }
            return;
        }
        if self.modal.is_some() {
            return;
        }
        if kind == MouseEventKind::Down(MouseButton::Left) {
            if row <= 3 {
                let page = (column / 12) as usize;
                if page < PAGES.len() {
                    self.switch_page(page);
                }
            } else if self.page == 0 {
                let index = row.saturating_sub(6) as usize;
                self.select_instance_row(index);
            }
        }
        match kind {
            MouseEventKind::ScrollDown => {
                if self.page == 1 {
                    self.scroll = (self.scroll + 3).min(self.logs.len().saturating_sub(1));
                } else if self.page == 0 {
                    let max = self.visible_instances().len();
                    if max > 0 {
                        self.select_instance_row((self.selected + 1).min(max - 1));
                    }
                } else {
                    let max = match self.page {
                        2 => self.status.players.len(),
                        3 => self.backups.len(),
                        4 => self.mods.len(),
                        _ => 0,
                    };
                    if max > 0 {
                        self.selected = (self.selected + 1).min(max - 1);
                    }
                }
            }
            MouseEventKind::ScrollUp => {
                if self.page == 1 {
                    self.scroll = self.scroll.saturating_sub(3);
                } else if self.page == 0 {
                    self.select_instance_row(self.selected.saturating_sub(1));
                } else if matches!(self.page, 2..=4) {
                    self.selected = self.selected.saturating_sub(1);
                }
            }
            _ => {}
        }
    }
}

/// Start the full-screen TUI. The caller decides whether `--demo` is enabled.
pub fn run(root: PathBuf, demo: bool) -> Result<()> {
    let executable = std::env::current_exe().context("定位 mcsrv-mayon 可执行文件")?;
    let mut app = App::new(root, demo, executable);
    if demo {
        app.message = "演示数据已载入 · 所有操作均为模拟".into();
        app.instances = vec![
            Instance {
                name: "gtnh-friends".into(),
                kind: "GTNH 官方服务端".into(),
                version: "2.9".into(),
                memory_mb: 8192,
                port: 25565,
                online_mode: true,
                whitelist: true,
                java: "21".into(),
                backup_minutes: 30,
                lan: false,
            },
            Instance {
                name: "fabric-test".into(),
                kind: "Fabric".into(),
                version: "1.21.10".into(),
                memory_mb: 2048,
                port: 25566,
                online_mode: true,
                whitelist: false,
                java: "21".into(),
                backup_minutes: 15,
                lan: true,
            },
        ];
        app.status = Status {
            state: "运行中".into(),
            players: vec!["Alex".into(), "Steve".into()],
            memory: "3.2 GiB / 8 GiB".into(),
            tps: "20.0".into(),
            mspt: "18.4 ms".into(),
            addresses: "192.168.1.20:25565".into(),
        };
        app.logs = vec![
            "[Server thread/INFO]: Starting minecraft server version 1.7.10".into(),
            "[Server thread/INFO]: Preparing level \"world\"".into(),
            "[Server thread/INFO]: Done (42.381s)! For help, type \"help\" or \"?\"".into(),
            "[Server thread/INFO]: Alex joined the game".into(),
        ];
        app.backups = vec![
            serde_json::json!({"short_id":"a1b2c3d4","time":"2026-10-30 19:20:00","paths":["world"]}),
            serde_json::json!({"short_id":"e5f6a7b8","time":"2026-10-30 18:50:00","paths":["world"]}),
        ];
        app.mods = vec![
            serde_json::json!({"id":"fabric-api","title":"Fabric API","description":"Fabric 模组 API，服务器侧支持","server_side":"required","client_side":"required"}),
            serde_json::json!({"id":"lithium","title":"Lithium","description":"服务器性能优化","server_side":"required","client_side":"unsupported"}),
        ];
    } else {
        app.list();
    }
    let mut terminal = Terminal::new(CrosstermBackend::new(io::stdout()))?;
    let guard = TerminalGuard::enter()?;
    let result = event_loop(&mut terminal, &mut app);
    drop(guard);
    result
}

struct TerminalGuard;
impl TerminalGuard {
    fn enter() -> io::Result<Self> {
        enable_raw_mode()?;
        if let Err(error) = execute!(io::stdout(), EnterAlternateScreen, EnableMouseCapture) {
            let _ = disable_raw_mode();
            return Err(error);
        }
        Ok(Self)
    }
}
impl Drop for TerminalGuard {
    fn drop(&mut self) {
        let _ = disable_raw_mode();
        let _ = execute!(
            io::stdout(),
            DisableMouseCapture,
            LeaveAlternateScreen,
            Show
        );
    }
}

fn event_loop(terminal: &mut Terminal<CrosstermBackend<io::Stdout>>, app: &mut App) -> Result<()> {
    loop {
        app.poll_tick();
        if app.exit_when_idle && !app.busy {
            return Ok(());
        }
        terminal.draw(|frame| draw(frame, app))?;
        if event::poll(Duration::from_millis(120))? {
            match event::read()? {
                Event::Key(key) if app.handle_key(key) => return Ok(()),
                Event::Mouse(mouse) => app.mouse(mouse.kind, mouse.column, mouse.row),
                Event::Resize(_, _) => {}
                _ => {}
            }
        }
    }
}

fn draw(frame: &mut Frame, app: &App) {
    let area = frame.area();
    frame.render_widget(Block::default().style(Style::default().bg(BG).fg(FG)), area);
    let layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(1),
            Constraint::Length(2),
            Constraint::Min(4),
            Constraint::Length(2),
        ])
        .split(area);
    let instance_label = app.selected_name().unwrap_or_else(|| "未选择实例".into());
    let state = if app.demo {
        "演示模式 · 无真实操作"
    } else {
        &app.status.state
    };
    let title = format!(" mcsrv-mayon  │  {instance_label}  │  {state}");
    frame.render_widget(
        Paragraph::new(clip(&title, area.width as usize))
            .style(Style::default().fg(BRIGHT_FG).bg(DEEP)),
        layout[0],
    );
    let tabs = PAGES.iter().enumerate().map(|(index, name)| {
        let style = if index == app.page {
            Style::default()
                .fg(BLUE)
                .add_modifier(Modifier::BOLD | Modifier::UNDERLINED)
        } else {
            Style::default().fg(MUTED)
        };
        Span::styled(format!(" {} {} ", index + 1, name), style)
    });
    frame.render_widget(
        Paragraph::new(Line::from(tabs.collect::<Vec<_>>())).block(
            Block::default()
                .borders(Borders::BOTTOM)
                .border_style(Style::default().fg(BORDER)),
        ),
        layout[1],
    );
    match app.page {
        0 => draw_instances(frame, layout[2], app),
        1 => draw_console(frame, layout[2], app),
        2 => draw_players(frame, layout[2], app),
        3 => draw_backups(frame, layout[2], app),
        4 => draw_mods(frame, layout[2], app),
        _ => draw_network(frame, layout[2], app),
    }
    let hint = match app.page {
        0 => "n 新建  s 启动  x 停止  / 过滤",
        1 => "Enter 命令  j/k 浏览日志",
        2 => "Enter 玩家命令  a 输入自定义管理命令",
        3 => "b 备份  r 回滚（需输入快照 ID）",
        4 => "/ 搜索  Enter/i 安装  u 更新  d 比较 Prism",
        _ => "l/L 切换局域网  t Tailscale说明  c 备份间隔  ? 帮助",
    };
    frame.render_widget(
        Paragraph::new(Text::from(vec![
            Line::from(Span::styled(
                fit_hint(hint, area.width as usize),
                Style::default().fg(MUTED),
            )),
            Line::from(Span::styled(
                clip(&app.message, area.width as usize),
                Style::default().fg(BLUE),
            )),
        ])),
        layout[3],
    );
    if let Some(modal) = app.modal {
        draw_modal(frame, modal, app);
    }
}

fn draw_instances(frame: &mut Frame, area: Rect, app: &App) {
    let visible = app.visible_instances();
    let short_info = app
        .selected_instance()
        .map(|server| {
            format!(
                "{} · {} {} · {}\nJava {} · {} MiB · TCP {}\n正版 {} · 白名单 {} · 定时备份 {} 分钟\nTPS {} · MSPT {} · 玩家 {} · 内存 {}\n局域网 {} · 地址 {}",
                server.name,
                server.kind,
                server.version,
                app.status.state,
                server.java,
                server.memory_mb,
                server.port,
                yes_no(server.online_mode),
                yes_no(server.whitelist),
                server.backup_minutes,
                if app.status.tps.is_empty() { "—" } else { &app.status.tps },
                if app.status.mspt.is_empty() { "—" } else { &app.status.mspt },
                app.status.players.len(),
                app.status.memory,
                yes_no(server.lan),
                if app.status.addresses.is_empty() { "—" } else { &app.status.addresses },
            )
        })
        .unwrap_or_else(|| {
            "还没有实例。\nn 新建服务器".to_owned()
        });
    if area.width < 112 {
        let split = Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Length(12), Constraint::Min(8)])
            .split(area);
        let narrow_rows = visible.iter().map(|index| {
            let server = &app.instances[*index];
            Row::new(vec![
                Cell::from(if *index == app.instance_selected {
                    "▏"
                } else {
                    " "
                })
                .style(Style::default().fg(BLUE)),
                Cell::from(server.name.clone()),
                Cell::from(format!("{} {}", server.kind, server.version)),
            ])
            .style(if *index == app.instance_selected {
                Style::default().bg(SELECTION).fg(BRIGHT_FG)
            } else {
                Style::default().fg(FG)
            })
        });
        let table = Table::new(
            narrow_rows,
            [
                Constraint::Length(2),
                Constraint::Percentage(40),
                Constraint::Percentage(52),
            ],
        )
        .header(Row::new(["", "实例", "类型 / 版本"]).style(Style::default().fg(MUTED)))
        .column_spacing(1)
        .block(block("服务器实例", true));
        frame.render_widget(table, split[0]);
        frame.render_widget(
            Paragraph::new(short_info)
                .block(block("实例状态", false))
                .wrap(Wrap { trim: false }),
            split[1],
        );
    } else {
        let split = Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Percentage(63), Constraint::Percentage(37)])
            .split(area);
        let rows = visible.iter().map(|index| {
            let server = &app.instances[*index];
            Row::new(vec![
                Cell::from(if *index == app.instance_selected {
                    "▏"
                } else {
                    " "
                })
                .style(Style::default().fg(BLUE)),
                Cell::from(server.name.clone()),
                Cell::from(format!("{} {}", server.kind, server.version)),
                Cell::from(format!("{} MiB", server.memory_mb)),
                Cell::from(server.port.to_string()),
            ])
            .style(if *index == app.instance_selected {
                Style::default().bg(SELECTION).fg(BRIGHT_FG)
            } else {
                Style::default().fg(FG)
            })
        });
        let table = Table::new(
            rows,
            [
                Constraint::Length(2),
                Constraint::Percentage(32),
                Constraint::Percentage(34),
                Constraint::Length(12),
                Constraint::Length(8),
            ],
        )
        .header(
            Row::new(["", "实例", "类型 / 版本", "内存", "端口"]).style(Style::default().fg(MUTED)),
        )
        .column_spacing(1)
        .block(block("服务器实例", true));
        frame.render_widget(table, split[0]);
        let info = app.selected_instance().map(|server| {
            format!(
                "名称     {}\n类型     {}\n版本     {}\n状态     {}\nJava     {}\n内存     {} MiB\n端口     {}\n正版验证 {}\n白名单   {}\n定时备份 {} 分钟\n局域网   {}\n\nTPS      {}\nMSPT     {}\n玩家     {}\n已用内存 {}\n地址     {}",
                server.name, server.kind, server.version,
                if app.status.state.is_empty() { "未知" } else { &app.status.state },
                server.java, server.memory_mb, server.port,
                yes_no(server.online_mode), yes_no(server.whitelist), server.backup_minutes, yes_no(server.lan),
                if app.status.tps.is_empty() { "—" } else { &app.status.tps },
                if app.status.mspt.is_empty() { "—" } else { &app.status.mspt },
                app.status.players.len(), app.status.memory,
                if app.status.addresses.is_empty() { "—" } else { &app.status.addresses },
            )
        }).unwrap_or_else(|| "还没有服务器实例。\n\nn 新建服务器\n支持 vanilla、Paper、Fabric、Forge、NeoForge、GTNH、Modrinth 和 Prism 导出。".into());
        frame.render_widget(
            Paragraph::new(info)
                .block(block("实例详情", false))
                .wrap(Wrap { trim: false }),
            split[1],
        );
    }
}

fn draw_console(frame: &mut Frame, area: Rect, app: &App) {
    let lines: Vec<Line> = app
        .logs
        .iter()
        .map(|line| {
            let color = if line.contains("Done (") {
                GREEN
            } else if line.contains("WARN") {
                YELLOW
            } else if line.contains("ERROR") {
                RED
            } else {
                FG
            };
            Line::from(Span::styled(line.clone(), Style::default().fg(color)))
        })
        .collect();
    frame.render_widget(
        Paragraph::new(Text::from(lines))
            .scroll((app.scroll as u16, 0))
            .block(block("服务端实时日志  ·  Enter 输入命令", true))
            .wrap(Wrap { trim: false }),
        area,
    );
}
fn draw_players(frame: &mut Frame, area: Rect, app: &App) {
    let split = if area.width < 112 {
        Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Length(10), Constraint::Min(8)])
            .split(area)
    } else {
        Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Percentage(55), Constraint::Percentage(45)])
            .split(area)
    };
    let rows = app
        .status
        .players
        .iter()
        .enumerate()
        .map(|(index, player)| {
            Row::new(vec![
                Cell::from(if index == app.selected { "▏" } else { " " }),
                Cell::from(player.clone()),
                Cell::from("在线"),
            ])
            .style(if index == app.selected {
                Style::default().bg(SELECTION).fg(BRIGHT_FG)
            } else {
                Style::default().fg(FG)
            })
        });
    frame.render_widget(
        Table::new(
            rows,
            [
                Constraint::Length(2),
                Constraint::Percentage(70),
                Constraint::Percentage(25),
            ],
        )
        .header(Row::new(["", "玩家", "状态"]).style(Style::default().fg(MUTED)))
        .block(block("在线玩家", true)),
        split[0],
    );
    let text = "管理命令会发送给服务端：\n\nwhitelist add <玩家>\nwhitelist remove <玩家>\nop <玩家>\ndeop <玩家>\nkick <玩家> [原因]\nban <玩家> [原因]\npardon <玩家>\n\n选择玩家后 Enter 预填 op 命令并可编辑；a 输入 whitelist/kick/ban 等命令。\n\n正版验证与白名单在实例配置中管理。";
    frame.render_widget(
        Paragraph::new(text)
            .block(block("玩家管理", false))
            .wrap(Wrap { trim: false }),
        split[1],
    );
}
fn draw_backups(frame: &mut Frame, area: Rect, app: &App) {
    let narrow = area.width < 112;
    let widths = if narrow {
        vec![
            Constraint::Length(2),
            Constraint::Length(14),
            Constraint::Min(12),
        ]
    } else {
        vec![
            Constraint::Length(2),
            Constraint::Length(14),
            Constraint::Length(24),
            Constraint::Min(10),
        ]
    };
    let header = if narrow {
        Row::new(["", "快照 ID", "时间"]).style(Style::default().fg(MUTED))
    } else {
        Row::new(["", "快照 ID", "时间", "内容"]).style(Style::default().fg(MUTED))
    };
    let rows = app.backups.iter().enumerate().map(|(index, backup)| {
        let id = json_str(backup, &["short_id", "id", "snapshot"]).unwrap_or("未知");
        let time = json_str(backup, &["time", "time_formatted"]).unwrap_or("—");
        let mut cells = vec![
            Cell::from(if index == app.selected { "▏" } else { " " }),
            Cell::from(id.to_owned()),
            Cell::from(time.to_owned()),
        ];
        if !narrow {
            let paths = backup
                .get("paths")
                .and_then(Value::as_array)
                .map(|paths| {
                    paths
                        .iter()
                        .filter_map(Value::as_str)
                        .collect::<Vec<_>>()
                        .join(", ")
                })
                .unwrap_or_else(|| "世界存档".into());
            cells.push(Cell::from(paths));
        }
        Row::new(cells).style(if index == app.selected {
            Style::default().bg(SELECTION).fg(BRIGHT_FG)
        } else {
            Style::default().fg(FG)
        })
    });
    frame.render_widget(
        Table::new(rows, widths).header(header).block(block(
            "增量备份  ·  b 立即备份  ·  r 回滚  ·  v 保留数",
            true,
        )),
        area,
    );
}
fn draw_mods(frame: &mut Frame, area: Rect, app: &App) {
    let rows = app.mods.iter().enumerate().map(|(index, item)| {
        let id = json_str(item, &["project_id", "id"]).unwrap_or("—");
        let title = json_str(item, &["title", "name"]).unwrap_or("未知项目");
        let desc = json_str(item, &["description"]).unwrap_or("");
        Row::new(vec![
            Cell::from(if index == app.selected { "▏" } else { " " }),
            Cell::from(title.to_owned()),
            Cell::from(id.to_owned()),
            Cell::from(desc.to_owned()),
        ])
        .style(if index == app.selected {
            Style::default().bg(SELECTION).fg(BRIGHT_FG)
        } else {
            Style::default().fg(FG)
        })
    });
    let split = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Min(5), Constraint::Length(4)])
        .split(area);
    let widths = if area.width < 112 {
        vec![
            Constraint::Length(2),
            Constraint::Percentage(30),
            Constraint::Length(18),
            Constraint::Min(12),
        ]
    } else {
        vec![
            Constraint::Length(2),
            Constraint::Percentage(28),
            Constraint::Length(18),
            Constraint::Min(20),
        ]
    };
    frame.render_widget(
        Table::new(rows, widths)
            .header(Row::new(["", "项目", "Modrinth ID", "说明"]).style(Style::default().fg(MUTED)))
            .block(block("Modrinth 服务端模组", true)),
        split[0],
    );
    frame.render_widget(Paragraph::new("/ 搜索 · Enter / i 安装所选 · u 更新当前版本 · d 与 Prism 实例比较\n安装前会按 MC 版本及 loader 筛选，服务端不兼容项目会被跳过。")
        .style(Style::default().fg(MUTED)).block(block("模组管理", false)).wrap(Wrap { trim: false }), split[1]);
}
fn draw_network(frame: &mut Frame, area: Rect, app: &App) {
    let info = app.selected_instance().map(|server| format!(
        "实例：{}\n监听端口：{}\n局域网共享：{}\n\n本机与 Tailscale 可用地址\n{}\n\n外网联机推荐 Tailscale：将同学加入 tailnet 后使用设备名与端口连接。\n主机需启用 services.tailscale.enable；显式连接时终端显示登录 URL。也可按文档配置 playit.gg agent 或自建 frp。\n\nClash TUN：本机回环及 RFC1918/ULA 直连规则应覆盖游戏端口；避免把服务器流量送入代理。\n路由器端口转发只适用于用户主动配置。防火墙临时放行须与开服同启，关服撤销。",
        server.name, server.port, yes_no(server.lan),
        if app.status.addresses.is_empty() { "按 l 刷新本机地址".into() } else { app.status.addresses.clone() },
    )).unwrap_or_else(|| "请选择一个实例以查看网络与联机选项。".into());
    frame.render_widget(
        Paragraph::new(info)
            .block(block("局域网与远程联机", true))
            .wrap(Wrap { trim: false }),
        area,
    );
}
fn draw_modal(frame: &mut Frame, modal: Modal, app: &App) {
    let width = 74.min(frame.area().width.saturating_sub(4));
    let height = match modal {
        Modal::Help => 12.min(frame.area().height.saturating_sub(2)),
        Modal::Output => 22.min(frame.area().height.saturating_sub(2)),
        Modal::Input(_) | Modal::ConfirmCreate | Modal::ConfirmRestore => {
            8.min(frame.area().height.saturating_sub(2))
        }
    };
    let area = centered(frame.area(), width, height);
    frame.render_widget(Clear, area);
    let (title, body) = match modal {
        Modal::Help => ("帮助", HELP.to_owned()),
        Modal::Output => (
            app.output_title.as_str(),
            format!(
                "{}\n\nj/k 或滚轮翻动 · ? / Esc / q 关闭",
                app.output_lines.join("\n")
            ),
        ),
        Modal::Input(_) => (
            "输入",
            format!(
                "{}\n\n› {}▏\nEnter 确认 · Esc 取消 · Ctrl+A 清空",
                app.prompt, app.input
            ),
        ),
        Modal::ConfirmCreate => (
            "接受 EULA",
            format!(
                "{}\n\n› {}▏\nEnter 确认 · Esc 取消 · Ctrl+A 清空",
                app.prompt, app.input
            ),
        ),
        Modal::ConfirmRestore => (
            "确认回滚",
            format!(
                "{}\n\n› {}▏\nEnter 确认 · Esc 取消 · Ctrl+A 清空",
                app.prompt, app.input
            ),
        ),
    };
    let scroll = if modal == Modal::Output {
        app.output_scroll.min(u16::MAX as usize) as u16
    } else {
        0
    };
    frame.render_widget(
        Paragraph::new(body)
            .style(Style::default().fg(FG).bg(BG))
            .block(block(title, true).style(Style::default().bg(BG)))
            .wrap(Wrap { trim: false })
            .scroll((scroll, 0)),
        area,
    );
}
fn block(title: &str, focused: bool) -> Block<'static> {
    Block::default()
        .borders(Borders::ALL)
        .border_type(ratatui::widgets::BorderType::Rounded)
        .border_style(Style::default().fg(if focused { BLUE } else { BORDER }))
        .title(Span::styled(
            title.to_owned(),
            Style::default().fg(if focused { BLUE } else { FG }),
        ))
}
fn centered(area: Rect, width: u16, height: u16) -> Rect {
    let width = width.min(area.width.saturating_sub(2));
    let height = height.min(area.height.saturating_sub(2));
    Rect::new(
        area.x + (area.width - width) / 2,
        area.y + (area.height - height) / 2,
        width,
        height,
    )
}
fn fit_hint(hint: &str, width: usize) -> String {
    if hint.width() <= width {
        return hint.to_owned();
    }
    let more = "? 帮助";
    let mut output = String::new();
    for action in hint
        .split("  ")
        .map(str::trim)
        .filter(|part| !part.is_empty())
    {
        let candidate = if output.is_empty() {
            action.to_owned()
        } else {
            format!("{output}  {action}")
        };
        if candidate.width() + 2 + more.width() > width {
            break;
        }
        output = candidate;
    }
    if output.is_empty() {
        clip(more, width)
    } else {
        format!("{output}  {more}")
    }
}

fn clip(value: &str, width: usize) -> String {
    if value.width() <= width {
        return value.to_owned();
    }
    if width == 0 {
        return String::new();
    }
    let mut output = String::new();
    let mut used = 0;
    for grapheme in value.graphemes(true) {
        let grapheme_width = UnicodeWidthStr::width(grapheme);
        if used + grapheme_width > width.saturating_sub(1) {
            break;
        }
        output.push_str(grapheme);
        used += grapheme_width;
    }
    output.push('…');
    output
}

fn yes_no(value: bool) -> &'static str {
    if value {
        "开启"
    } else {
        "关闭"
    }
}
fn is_mod_result_action(action: &str) -> bool {
    matches!(action, "比较 Prism 模组" | "更新模组" | "安装模组")
}
fn json_str<'a>(value: &'a Value, keys: &[&str]) -> Option<&'a str> {
    keys.iter()
        .find_map(|key| value.get(*key).and_then(Value::as_str))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn demo_app() -> App {
        let mut app = App::new(PathBuf::new(), true, PathBuf::from("unused"));
        app.instances = vec![
            Instance {
                name: "server1".into(),
                kind: "Paper".into(),
                version: "1.21.1".into(),
                memory_mb: 2048,
                port: 25565,
                online_mode: true,
                whitelist: false,
                java: "21".into(),
                backup_minutes: 30,
                lan: false,
            },
            Instance {
                name: "server2".into(),
                kind: "Fabric".into(),
                version: "1.21.10".into(),
                memory_mb: 4096,
                port: 25566,
                online_mode: true,
                whitelist: true,
                java: "21".into(),
                backup_minutes: 15,
                lan: false,
            },
        ];
        app.status.players = vec!["Alex".into(), "Steve".into()];
        app.backups = vec![
            serde_json::json!({"short_id":"snap-one"}),
            serde_json::json!({"short_id":"snap-two"}),
        ];
        app.mods = vec![serde_json::json!({"id":"mod-one"})];
        app.logs = vec!["line one".into(), "line two".into()];
        app
    }

    fn key(code: KeyCode) -> KeyEvent {
        KeyEvent::new(code, KeyModifiers::NONE)
    }

    #[test]
    fn backup_row_navigation_does_not_change_selected_instance() {
        let mut app = demo_app();
        app.select_instance_row(1);
        assert_eq!(app.selected_name().as_deref(), Some("server2"));
        app.backups = vec![
            serde_json::json!({"short_id":"snap-one"}),
            serde_json::json!({"short_id":"snap-two"}),
        ];

        app.switch_page(3);
        app.handle_key(key(KeyCode::Char('j')));
        assert_eq!(app.selected, 1);
        assert_eq!(app.selected_name().as_deref(), Some("server2"));
        app.handle_key(key(KeyCode::Char('k')));
        assert_eq!(app.selected, 0);
        assert_eq!(app.selected_name().as_deref(), Some("server2"));
    }

    #[test]
    fn player_action_uses_persistently_selected_instance() {
        let mut app = demo_app();
        app.select_instance_row(1);
        app.status.state = "running".into();
        app.status.players = vec!["Alex".into(), "Steve".into()];
        app.switch_page(2);
        app.handle_key(key(KeyCode::Char('j')));
        app.handle_key(key(KeyCode::Enter));
        assert_eq!(app.selected_name().as_deref(), Some("server2"));
        assert!(app.prompt.contains("Steve"));
        assert_eq!(app.input, "op Steve");

        app.handle_input_submit(InputKind::Console);
        assert_eq!(app.selected_name().as_deref(), Some("server2"));
        assert!(app.message.contains("模拟"));
    }

    #[test]
    fn filtered_instance_navigation_maps_visible_rows_to_instances() {
        let mut app = demo_app();
        app.apply_filter(Some("server2".into()));
        assert_eq!(app.visible_instances(), vec![1]);
        assert_eq!(app.selected, 0);
        assert_eq!(app.selected_name().as_deref(), Some("server2"));

        app.handle_key(key(KeyCode::Char('j')));
        app.handle_key(key(KeyCode::Char('k')));
        assert_eq!(app.instance_selected, 1);
        assert_eq!(app.selected_name().as_deref(), Some("server2"));
    }

    #[test]
    fn busy_operation_blocks_instance_switch_and_switch_clears_old_data() {
        let mut app = demo_app();
        app.busy = true;
        app.select_instance_row(1);
        assert_eq!(app.selected_name().as_deref(), Some("server1"));
        assert_eq!(app.status.players, vec!["Alex", "Steve"]);

        app.busy = false;
        app.select_instance_row(1);
        assert_eq!(app.selected_name().as_deref(), Some("server2"));
        assert!(app.status.players.is_empty());
        assert!(app.logs.is_empty());
        assert!(app.backups.is_empty());
        assert!(app.mods.is_empty());
    }

    #[test]
    fn zero_backup_interval_is_accepted_as_disabled() {
        let mut app = demo_app();
        app.page = 5;
        app.input = "0".into();
        app.handle_input_submit(InputKind::Config);
        assert!(app.message.contains("模拟"));
        assert_eq!(app.selected_name().as_deref(), Some("server1"));
    }

    #[test]
    fn prism_diff_result_shows_every_array_entry_in_scrollable_modal() {
        let mut app = demo_app();
        app.accept_output(
            "比较 Prism 模组",
            r#"["仅服务器：example-server-mod","Prism 独有：example-client-mod"]"#,
        );
        assert_eq!(app.modal, Some(Modal::Output));
        assert_eq!(app.output_lines.len(), 2);
        assert!(app.output_lines[0].contains("example-server-mod"));
        assert!(app.output_lines[1].contains("example-client-mod"));
        assert!(!app.message.contains('['));

        app.output_lines = (0..30).map(|line| format!("差异 {line}")).collect();
        app.handle_key(key(KeyCode::Char('j')));
        assert_eq!(app.output_scroll, 1);
        app.mouse(MouseEventKind::ScrollDown, 0, 0);
        assert_eq!(app.output_scroll, 4);
        app.handle_key(key(KeyCode::Char('q')));
        assert_eq!(app.modal, None);
    }
}
