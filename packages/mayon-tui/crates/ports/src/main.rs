use crossterm::event::{
    self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers, MouseEventKind,
};
use mayon_ui::{
    base, block, chrome, dialog, help,
    input::TextInput,
    marker,
    search::{Matcher, SearchCache},
    terminal,
    theme::*,
    Refresh,
};
use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::{
    style::Style,
    text::Line,
    widgets::{Cell, Paragraph, Row, Table, TableState, Wrap},
};
use serde::Serialize;
use std::{
    collections::HashMap,
    env, fs, io,
    path::Path,
    time::{Duration, Instant},
};

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Listener {
    pub protocol: String,
    pub address: String,
    pub port: u16,
    pub pid: Option<i32>,
    pub process: String,
    pub command: String,
    pub user: String,
    pub age: String,
    pub inode: u64,
    pub start_ticks: Option<u64>,
    pub uid: Option<u32>,
    pub cwd: String,
    pub parent: Option<i32>,
    pub docker: String,
}
impl Listener {
    fn key(&self) -> (String, u16, Option<i32>, u64) {
        (self.protocol.clone(), self.port, self.pid, self.inode)
    }
}
fn decode_addr(hex: &str, ipv6: bool) -> Option<String> {
    if ipv6 {
        if hex.len() != 32 {
            return None;
        }
        let mut bytes = [0u8; 16];
        for (i, chunk) in hex.as_bytes().chunks(8).enumerate() {
            let s = std::str::from_utf8(chunk).ok()?;
            let v = u32::from_str_radix(s, 16).ok()?.to_le_bytes();
            bytes[i * 4..i * 4 + 4].copy_from_slice(&v);
        }
        Some(std::net::Ipv6Addr::from(bytes).to_string())
    } else {
        let n = u32::from_str_radix(hex, 16).ok()?;
        Some(std::net::Ipv4Addr::from(n.to_le_bytes()).to_string())
    }
}
fn socket_rows(
    path: &Path,
    proto: &str,
    ipv6: bool,
) -> io::Result<Vec<(String, String, u16, u64)>> {
    let src = fs::read_to_string(path)?;
    let mut out = vec![];
    for line in src.lines().skip(1) {
        let c: Vec<_> = line.split_whitespace().collect();
        if c.len() < 10 {
            continue;
        }
        if (proto == "TCP" && c[3] != "0A") || (proto == "UDP" && c[3] != "07") {
            continue;
        }
        let Some((addr, port)) = c[1].rsplit_once(':') else {
            continue;
        };
        let Some(ip) = decode_addr(addr, ipv6) else {
            continue;
        };
        let Ok(port) = u16::from_str_radix(port, 16) else {
            continue;
        };
        if port == 0 {
            continue;
        }
        let Ok(inode) = c[9].parse() else { continue };
        out.push((proto.to_string(), ip, port, inode));
    }
    Ok(out)
}
type ProcDetails = (
    String,
    String,
    String,
    String,
    Option<i32>,
    u64,
    u32,
    String,
);
fn same_process(identity: &ProcDetails, uid: u32, start: u64) -> bool {
    identity.6 == uid && identity.5 == start
}
fn proc_details(pid: i32) -> Option<ProcDetails> {
    let root = Path::new("/proc").join(pid.to_string());
    let stat = fs::read_to_string(root.join("stat")).ok()?;
    let end = stat.rfind(')')?;
    let fields: Vec<_> = stat[end + 2..].split_whitespace().collect();
    let parent = fields.get(1)?.parse().ok();
    let start = fields.get(19)?.parse().ok()?;
    let status = fs::read_to_string(root.join("status")).ok()?;
    let uid = status
        .lines()
        .find_map(|l| l.strip_prefix("Uid:"))
        .and_then(|v| v.split_whitespace().next())
        .and_then(|v| v.parse::<u32>().ok())?;
    let user = fs::read_to_string("/etc/passwd")
        .ok()
        .and_then(|p| {
            p.lines()
                .find(|l| l.split(':').nth(2) == Some(&uid.to_string()))
                .and_then(|l| l.split(':').next().map(str::to_owned))
        })
        .unwrap_or_else(|| uid.to_string());
    let comm = fs::read_to_string(root.join("comm"))
        .ok()
        .unwrap_or_else(|| "?".into())
        .trim()
        .to_string();
    let raw = fs::read(root.join("cmdline")).ok().unwrap_or_default();
    let command = String::from_utf8_lossy(&raw)
        .split('\0')
        .filter(|x| !x.is_empty())
        .collect::<Vec<_>>()
        .join(" ");
    let command = if command.is_empty() {
        comm.clone()
    } else {
        command
    };
    let cwd = fs::read_link(root.join("cwd"))
        .map(|p| p.display().to_string())
        .unwrap_or_else(|_| "系统 / 不可见".into());
    Some((comm, command, user, cwd, parent, start, uid, stat))
}
fn boot_age(start: u64) -> String {
    let uptime = fs::read_to_string("/proc/uptime")
        .ok()
        .and_then(|x| x.split_whitespace().next()?.parse::<f64>().ok())
        .unwrap_or(0.0);
    let ticks = unsafe { libc::sysconf(libc::_SC_CLK_TCK) }.max(1) as f64;
    let secs = (uptime - start as f64 / ticks).max(0.0) as u64;
    if secs < 60 {
        format!("{secs}s")
    } else if secs < 3600 {
        format!("{}m", secs / 60)
    } else if secs < 86400 {
        format!("{}h{}m", secs / 3600, (secs % 3600) / 60)
    } else {
        format!("{}d{}h", secs / 86400, (secs % 86400) / 3600)
    }
}
pub fn scan_proc() -> io::Result<Vec<Listener>> {
    let mut raw = vec![];
    for (file, p, ip6) in [
        ("tcp", "TCP", false),
        ("tcp6", "TCP", true),
        ("udp", "UDP", false),
        ("udp6", "UDP", true),
    ] {
        if let Ok(mut rows) = socket_rows(Path::new("/proc/net").join(file).as_path(), p, ip6) {
            raw.append(&mut rows)
        }
    }
    let mut inode_pid = HashMap::new();
    if let Ok(entries) = fs::read_dir("/proc") {
        for ent in entries.flatten() {
            let Some(n) = ent.file_name().to_str().and_then(|x| x.parse::<i32>().ok()) else {
                continue;
            };
            if let Ok(fds) = fs::read_dir(ent.path().join("fd")) {
                for fd in fds.flatten() {
                    if let Ok(link) = fs::read_link(fd.path()) {
                        let s = link.to_string_lossy();
                        if let Some(i) = s
                            .strip_prefix("socket:[")
                            .and_then(|v| v.strip_suffix(']'))
                            .and_then(|x| x.parse::<u64>().ok())
                        {
                            inode_pid.entry(i).or_insert(n);
                        }
                    }
                }
            }
        }
    }
    let own = unsafe { libc::geteuid() };
    let mut out = vec![];
    for (protocol, address, port, inode) in raw {
        let pid = inode_pid.get(&inode).copied();
        let details = pid.and_then(proc_details);
        let accessible = details.as_ref().is_some_and(|d| d.6 == own);
        let (process, command, user, cwd, parent, start_ticks, uid) = if let Some(d) = details {
            (
                d.0,
                d.1,
                if accessible { d.2 } else { "系统".into() },
                if accessible {
                    d.3
                } else {
                    "系统 / 不可见".into()
                },
                if accessible { d.4 } else { None },
                Some(d.5),
                Some(d.6),
            )
        } else {
            (
                "系统".into(),
                "系统 / 不可见".into(),
                "系统".into(),
                "系统 / 不可见".into(),
                None,
                None,
                None,
            )
        };
        let age = start_ticks.map(boot_age).unwrap_or_else(|| "--".into());
        out.push(Listener {
            protocol,
            address,
            port,
            pid,
            process,
            command,
            user,
            age,
            inode,
            start_ticks,
            uid,
            cwd,
            parent,
            docker: String::new(),
        });
    }
    out.sort_by(|a, b| {
        a.port
            .cmp(&b.port)
            .then(a.protocol.cmp(&b.protocol))
            .then(a.address.cmp(&b.address))
    });
    Ok(out)
}

#[derive(Clone, Copy)]
enum Sort {
    Port,
    Protocol,
    Pid,
    Process,
    Address,
}
type SelectionKey = (String, u16, Option<i32>, u64);
type FilterSnapshot = (String, Option<SelectionKey>);
struct App {
    rows: Vec<Listener>,
    selected: usize,
    filter: TextInput,
    filtering: bool,
    filter_snapshot: Option<FilterSnapshot>,
    search_cache: SearchCache,
    sort: Sort,
    message: String,
    help: bool,
    detail: bool,
    confirm: Option<(i32, u64, bool)>,
    detail_scroll: u16,
    last_body: Rect,
    last_table_offset: usize,
    last_table_rows: usize,
}
fn search_text(row: &Listener) -> String {
    format!(
        "{} {} {} {} {} {} {}",
        row.protocol,
        row.address,
        row.port,
        row.process,
        row.command,
        row.pid.map(|pid| pid.to_string()).unwrap_or_default(),
        row.user
    )
}

impl App {
    fn visible(&self) -> Vec<usize> {
        let matcher = Matcher::new(self.filter.as_str());
        self.rows
            .iter()
            .enumerate()
            .filter(|(_, row)| {
                self.filter.is_empty() || self.search_cache.matches(&matcher, &search_text(row))
            })
            .map(|(index, _)| index)
            .collect()
    }
    fn resort(&mut self) {
        let key = self.selected_row().map(Listener::key);
        match self.sort {
            Sort::Port => self.rows.sort_by_key(|r| r.port),
            Sort::Protocol => self.rows.sort_by(|a, b| a.protocol.cmp(&b.protocol)),
            Sort::Pid => self.rows.sort_by_key(|r| r.pid),
            Sort::Process => self.rows.sort_by(|a, b| a.process.cmp(&b.process)),
            Sort::Address => self.rows.sort_by(|a, b| a.address.cmp(&b.address)),
        }
        self.keep_selection(key);
    }
    fn selected_row(&self) -> Option<&Listener> {
        let ids = self.visible();
        ids.get(self.selected).and_then(|i| self.rows.get(*i))
    }
    fn keep_selection(&mut self, key: Option<SelectionKey>) {
        let visible = self.visible();
        self.selected = key
            .and_then(|key| {
                visible
                    .iter()
                    .position(|index| self.rows[*index].key() == key)
            })
            .unwrap_or(0);
        if !visible.is_empty() {
            self.selected = self.selected.min(visible.len() - 1);
        }
    }
    fn merge(&mut self, mut rows: Vec<Listener>) {
        let key = self.selected_row().map(Listener::key);
        rows.sort_by(|a, b| match self.sort {
            Sort::Port => a.port.cmp(&b.port),
            Sort::Protocol => a.protocol.cmp(&b.protocol),
            Sort::Pid => a.pid.cmp(&b.pid),
            Sort::Process => a.process.cmp(&b.process),
            Sort::Address => a.address.cmp(&b.address),
        });
        self.rows = rows;
        self.keep_selection(key);
    }
    fn move_by(&mut self, n: isize) {
        let len = self.visible().len();
        if len > 0 {
            self.selected = (self.selected as isize + n).clamp(0, len as isize - 1) as usize;
        }
    }
    fn begin_filter(&mut self) {
        self.filter_snapshot = Some((
            self.filter.to_string(),
            self.selected_row().map(Listener::key),
        ));
        self.filtering = true;
    }
    fn cancel_filter(&mut self) {
        if let Some((filter, key)) = self.filter_snapshot.take() {
            self.filter.set(filter);
            self.keep_selection(key);
        }
        self.filtering = false;
    }
    fn finish_filter(&mut self) {
        self.filtering = false;
        self.filter_snapshot = None;
    }
    fn filter_changed(&mut self, selected: Option<(String, u16, Option<i32>, u64)>) {
        self.keep_selection(selected);
    }
    fn signal(&mut self) {
        let Some(r) = self.selected_row().cloned() else {
            return;
        };
        let Some(pid) = r.pid else {
            self.message = "没有可见的属主进程".into();
            return;
        };
        if r.uid != Some(unsafe { libc::geteuid() }) {
            self.message = "只允许结束当前用户的进程".into();
            return;
        }
        let Some(start) = r.start_ticks else {
            self.message = "无法验证进程启动时间".into();
            return;
        };
        self.confirm = Some((pid, start, false));
    }
    fn send_signal(&mut self, pid: i32, start: u64, hard: bool) {
        let own = unsafe { libc::geteuid() };
        let Some(d) = proc_details(pid) else {
            self.message = "进程已退出或不可见".into();
            return;
        };
        if !same_process(&d, own, start) {
            self.message = "进程身份已变化，已取消信号".into();
            return;
        };
        let pidfd = unsafe { libc::syscall(libc::SYS_pidfd_open, pid, 0) } as i32;
        if pidfd < 0 {
            self.message = "pidfd_open 失败；为避免 PID 重用，没有发送信号".into();
            return;
        };
        let same = proc_details(pid).is_some_and(|p| same_process(&p, own, start));
        if !same {
            unsafe { libc::close(pidfd) };
            self.message = "pidfd 复核发现进程身份变化，已取消信号".into();
            return;
        }
        let sig = if hard { libc::SIGKILL } else { libc::SIGTERM };
        let rc = unsafe {
            libc::syscall(
                libc::SYS_pidfd_send_signal,
                pidfd,
                sig,
                std::ptr::null::<libc::siginfo_t>(),
                0,
            )
        };
        unsafe { libc::close(pidfd) };
        self.message = if rc == 0 {
            format!("已发送 SIG{} 给 {pid}", if hard { "KILL" } else { "TERM" })
        } else {
            format!("发送信号失败：{}", io::Error::last_os_error())
        };
    }
    #[cfg(test)]
    fn key(&mut self, k: KeyCode) {
        self.handle_key(KeyEvent::new(k, KeyModifiers::NONE));
    }
    fn handle_key(&mut self, key: KeyEvent) {
        let k = key.code;
        if self.filtering {
            match k {
                KeyCode::Esc => self.cancel_filter(),
                KeyCode::Enter => self.finish_filter(),
                KeyCode::Up if key.modifiers.is_empty() => self.move_by(-1),
                KeyCode::Down if key.modifiers.is_empty() => self.move_by(1),
                _ => {
                    let selected = self.selected_row().map(Listener::key);
                    if self.filter.handle_key(key) {
                        self.filter_changed(selected);
                    }
                }
            }
            return;
        }
        if matches!(k, KeyCode::Char(_))
            && key
                .modifiers
                .intersects(KeyModifiers::CONTROL | KeyModifiers::ALT | KeyModifiers::SUPER)
        {
            return;
        }
        if self.help {
            if matches!(k, KeyCode::Esc | KeyCode::Char('?')) {
                self.help = false
            }
            return;
        }
        if self.detail {
            match k {
                KeyCode::Esc | KeyCode::Enter | KeyCode::Char('d') => self.detail = false,
                KeyCode::Char('j') | KeyCode::Down => {
                    self.detail_scroll = self.detail_scroll.saturating_add(1)
                }
                KeyCode::Char('k') | KeyCode::Up => {
                    self.detail_scroll = self.detail_scroll.saturating_sub(1)
                }
                KeyCode::PageDown => self.detail_scroll = self.detail_scroll.saturating_add(20),
                KeyCode::PageUp => self.detail_scroll = self.detail_scroll.saturating_sub(8),
                KeyCode::Home => self.detail_scroll = 0,
                _ => {}
            }
            return;
        }
        if let Some((pid, start, hard)) = self.confirm {
            match k {
                KeyCode::Esc | KeyCode::Char('n') => self.confirm = None,
                KeyCode::Char('y') | KeyCode::Enter => {
                    self.confirm = None;
                    self.send_signal(pid, start, hard)
                }
                KeyCode::Char('k') if !hard => self.confirm = Some((pid, start, true)),
                _ => {}
            }
            return;
        }
        match k {
            KeyCode::Char('q') => {}
            KeyCode::Char('?') => self.help = true,
            KeyCode::Char('/') => self.begin_filter(),
            KeyCode::Char('j') | KeyCode::Down => self.move_by(1),
            KeyCode::Char('k') | KeyCode::Up => self.move_by(-1),
            KeyCode::PageUp => self.move_by(-(self.last_table_rows.max(1) as isize)),
            KeyCode::PageDown => self.move_by(self.last_table_rows.max(1) as isize),
            KeyCode::Char('g') => self.selected = 0,
            KeyCode::Char('G') => self.selected = self.visible().len().saturating_sub(1),
            KeyCode::Char('d') | KeyCode::Enter => {
                self.detail = true;
                self.detail_scroll = 0;
            }
            KeyCode::Char('o') => {
                if let Some(r) = self.selected_row() {
                    let status = std::process::Command::new("xdg-open")
                        .arg(format!("http://localhost:{}", r.port))
                        .stdin(std::process::Stdio::null())
                        .stdout(std::process::Stdio::null())
                        .stderr(std::process::Stdio::null())
                        .spawn();
                    self.message = if status.is_ok() {
                        format!("已打开 localhost:{}", r.port)
                    } else {
                        "无法启动 xdg-open".into()
                    }
                }
            }
            KeyCode::Char('c') => {
                if let Some(r) = self.selected_row() {
                    let txt = r.port.to_string();
                    let ok = std::process::Command::new("wl-copy")
                        .arg(txt)
                        .stdin(std::process::Stdio::null())
                        .stdout(std::process::Stdio::null())
                        .stderr(std::process::Stdio::null())
                        .status()
                        .is_ok_and(|s| s.success());
                    self.message = if ok {
                        "端口已复制".into()
                    } else {
                        "wl-copy 不可用".into()
                    }
                }
            }
            KeyCode::Char('x') => self.signal(),
            KeyCode::Char('s') => {
                self.sort = match self.sort {
                    Sort::Port => Sort::Protocol,
                    Sort::Protocol => Sort::Pid,
                    Sort::Pid => Sort::Process,
                    Sort::Process => Sort::Address,
                    Sort::Address => Sort::Port,
                };
                self.resort()
            }
            KeyCode::Esc if !self.filter.is_empty() => {
                let selected = self.selected_row().map(Listener::key);
                self.filter.clear();
                self.keep_selection(selected);
            }
            _ => {}
        }
    }
}
fn scope(address: &str) -> &'static str {
    match address.parse::<std::net::IpAddr>() {
        Ok(std::net::IpAddr::V4(ip)) if ip.is_unspecified() => "对外",
        Ok(std::net::IpAddr::V4(ip)) if ip.octets()[0] == 127 => "本机",
        Ok(std::net::IpAddr::V6(ip)) if ip.is_unspecified() => "对外",
        Ok(std::net::IpAddr::V6(ip)) if ip.is_loopback() => "本机",
        _ => "指定接口",
    }
}
fn docker_socket_path(
    docker_host: Option<&str>,
    runtime: Option<&Path>,
    force: bool,
) -> Option<std::path::PathBuf> {
    match docker_host {
        Some(host) => {
            let path = std::path::PathBuf::from(host.strip_prefix("unix://")?);
            if let Some(runtime) = runtime {
                if path == runtime.join("docker.sock")
                    && !force
                    && !runtime.join("docker-private.sock").exists()
                {
                    return None;
                }
            }
            Some(path)
        }
        None => {
            let runtime = runtime?;
            if !force && !runtime.join("docker-private.sock").exists() {
                return None;
            }
            Some(runtime.join("docker.sock"))
        }
    }
}
fn detail_text(r: &Listener) -> String {
    format!(
        "{} {}:{}\nPID：{}  用户：{}  运行：{}\n进程：{}\n工作目录：{}\n父 PID：{}\nDocker：{}\n\n完整命令行：\n{}\n\n j/k 或 ↑↓ 滚动  PgUp/PgDn 翻页  Esc 返回",
        r.protocol,
        r.address,
        r.port,
        r.pid
            .map(|x| x.to_string())
            .unwrap_or_else(|| "系统".into()),
        r.user,
        r.age,
        r.process,
        r.cwd,
        r.parent
            .map(|x| x.to_string())
            .unwrap_or_else(|| "--".into()),
        if r.docker.is_empty() { "--" } else { &r.docker },
        r.command
    )
}
fn render(f: &mut ratatui::Frame, app: &mut App) {
    let ids = app.visible();
    let body = chrome(
        f,
        &format!(
            " 󰈀 端口监听  ·  {}/{} 匹配  ·  排序 {}",
            ids.len(),
            app.rows.len(),
            match app.sort {
                Sort::Port => "端口",
                Sort::Protocol => "协议",
                Sort::Pid => "PID",
                Sort::Process => "进程",
                Sort::Address => "地址",
            }
        ),
        &["监听"],
        0,
        "j/k 选择  / 过滤  s 排序  d 详情  o 浏览器  c 复制  x 确认结束  ? 帮助  q 退出",
        &app.message,
    );
    let (filter_area, table_area) = if app.filtering {
        let areas = Layout::vertical([Constraint::Length(1), Constraint::Min(0)]).split(body);
        (Some(areas[0]), areas[1])
    } else {
        (None, body)
    };
    if let Some(area) = filter_area {
        app.filter.render(f, area, base().fg(BRIGHTFG));
    }
    let compact = f.area().width < 108;
    let widths = if compact {
        [5, 22, 5, 14, 8, 6, 9]
    } else {
        [8, 27, 7, 22, 12, 9, 10]
    };
    let headers = ["协议", "监听地址", "PID", "进程", "用户", "时长", "范围"];
    let column_widths = widths.map(|w| Constraint::Length(w as u16));
    let matcher = Matcher::new(app.filter.as_str());
    if ids.is_empty() {
        let text = if app.filter.is_empty() {
            "没有监听项"
        } else {
            "没有匹配的监听项 · Esc 清除过滤"
        };
        f.render_widget(
            Paragraph::new(text)
                .style(Style::default().fg(MUTED))
                .block(block(
                    format!(
                        " {}/{} 匹配{} ",
                        ids.len(),
                        app.rows.len(),
                        if app.filter.is_empty() {
                            String::new()
                        } else {
                            format!("· /{}", app.filter)
                        }
                    ),
                    true,
                )),
            table_area,
        );
        app.last_table_offset = 0;
        app.last_table_rows = 0;
    } else {
        let rows = ids.iter().enumerate().map(|(visible_index, i)| {
            let r = &app.rows[*i];
            let label = scope(&r.address);
            let address = format!(
                "{}:{}{}",
                r.address,
                r.port,
                if matches!(
                    r.port,
                    3000 | 5173 | 8000 | 8080 | 8081 | 4200 | 5000 | 9000
                ) {
                    " · DEV"
                } else {
                    ""
                }
            );
            let process = if r.docker.is_empty() {
                r.process.clone()
            } else {
                format!("{} · {}", r.process, r.docker)
            };
            let pid = r
                .pid
                .map(|x| x.to_string())
                .unwrap_or_else(|| "系统".into());
            let dev = matches!(
                r.port,
                3000 | 5173 | 8000 | 8080 | 8081 | 4200 | 5000 | 9000
            );
            let address_style = if dev {
                Style::default().fg(CYAN)
            } else if scope(&r.address) == "对外" {
                Style::default().fg(RED)
            } else {
                Style::default().fg(FG)
            };
            let scope_style = if label == "对外" {
                RED
            } else if label == "本机" {
                GREEN
            } else {
                YELLOW
            };
            let mut cells = vec![
                Cell::from(app.search_cache.highlight(&matcher, &r.protocol)),
                Cell::from(if app.filter.is_empty() {
                    Line::styled(address, address_style)
                } else {
                    app.search_cache.highlight(&matcher, &address)
                }),
                Cell::from(app.search_cache.highlight(&matcher, &pid)),
                Cell::from(app.search_cache.highlight(&matcher, &process)),
                Cell::from(app.search_cache.highlight(&matcher, &r.user)),
                Cell::from(app.search_cache.highlight(&matcher, &r.age)),
                Cell::from(if app.filter.is_empty() {
                    Line::styled(label, Style::default().fg(scope_style))
                } else {
                    app.search_cache.highlight(&matcher, label)
                }),
            ];
            let mut all = vec![Cell::from(marker(visible_index == app.selected))];
            all.append(&mut cells);
            Row::new(all).style(if visible_index == app.selected {
                base().bg(SELECTION)
            } else {
                base()
            })
        });
        let mut table_widths = vec![Constraint::Length(1)];
        table_widths.extend(column_widths);
        let mut table_headers = vec![Cell::from("")];
        table_headers.extend(headers.map(Cell::from));
        let table = Table::new(rows, table_widths)
            .header(Row::new(table_headers).style(Style::default().fg(MUTED)))
            .column_spacing(1)
            .block(block(
                format!(
                    " {}/{} 匹配{} ",
                    ids.len(),
                    app.rows.len(),
                    if app.filter.is_empty() {
                        String::new()
                    } else {
                        format!("· /{}", app.filter)
                    }
                ),
                true,
            ));
        let mut state = TableState::default()
            .with_selected(Some(app.selected.min(ids.len().saturating_sub(1))));
        f.render_stateful_widget(table, table_area, &mut state);
        app.last_table_offset = state.offset();
        app.last_table_rows = table_area.height.saturating_sub(3) as usize;
    }
    app.last_body = table_area;
    if app.help {
        help(f, "j/k 或 ↑↓ 选择；滚轮滚动。/ 输入过滤；输入中的 ↑↓ 仍可移动选中项，Enter 保留过滤，Esc 取消本次输入。列表 Esc 清除过滤。s 循环按端口/协议/PID/进程/地址排序。d/Enter 查看完整命令、cwd 与父进程。o 打开 localhost:<port>，c 复制端口。x 进入确认；确认中 y 发 SIGTERM，k 再确认后才能发 SIGKILL。系统进程显示为“系统”，不发送信号。
IPv4/IPv6 TCP 与 UDP 来自 /proc/net；每 2 秒刷新并按 socket 保留选择。0.0.0.0/:: 标为对外，127/8 与 ::1 标为本机，其他绑定标为指定接口.");
    }
    if app.detail {
        if let Some(r) = app.selected_row() {
            let a = mayon_ui::centered(f.area(), 88, f.area().height.saturating_sub(2).min(40));
            f.render_widget(ratatui::widgets::Clear, a);
            f.render_widget(
                Paragraph::new(detail_text(r))
                    .style(base())
                    .block(block(" 监听详情 ", true))
                    .wrap(Wrap { trim: false })
                    .scroll((app.detail_scroll, 0)),
                a,
            );
        }
    }
    if let Some((pid, _, hard)) = app.confirm {
        dialog(
            f,
            if hard {
                " 二次确认 · SIGKILL "
            } else {
                " 确认结束进程 "
            },
            &format!(
                "PID {pid}\n{}\n按 y 确认 · Esc 取消",
                if hard {
                    "发送 SIGKILL，进程将立即终止。"
                } else {
                    "向当前用户的进程发送 SIGTERM。按 k 可进入 SIGKILL 二次确认。"
                }
            ),
        );
    }
}

fn clicked_visible_row(
    body: Rect,
    offset: usize,
    visible_len: usize,
    table_rows: usize,
    x: u16,
    y: u16,
) -> Option<usize> {
    if !body.contains((x, y).into()) {
        return None;
    }
    let data_y = body.y.saturating_add(2);
    if y < data_y {
        return None;
    }
    let row = y.saturating_sub(data_y) as usize;
    if row >= table_rows {
        return None;
    }
    let index = offset.saturating_add(row);
    (index < visible_len).then_some(index)
}
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let force_docker = env::args().any(|x| x == "--docker-map");
    if env::args().any(|x| x == "--version") {
        println!("portstui-mayon 0.2.0");
        return Ok(());
    }
    let docker_host = env::var("DOCKER_HOST").ok();
    let runtime = env::var_os("XDG_RUNTIME_DIR").map(std::path::PathBuf::from);
    let docker_path = docker_socket_path(docker_host.as_deref(), runtime.as_deref(), force_docker);
    let docker_enabled = docker_path.as_ref().is_some_and(|path| path.exists());
    if env::args().any(|x| x == "--help" || x == "-h") {
        println!(
            "portstui-mayon 0.2.0\n--docker-map  query an existing DOCKER_HOST or $XDG_RUNTIME_DIR/docker.sock; may activate the on-demand daemon"
        );
        return Ok(());
    }
    let mut app = App {
        rows: scan_proc().unwrap_or_default(),
        selected: 0,
        filter: TextInput::default(),
        filtering: false,
        filter_snapshot: None,
        search_cache: SearchCache::default(),
        sort: Sort::Port,
        message: "/proc 扫描就绪".into(),
        help: false,
        detail: false,
        confirm: None,
        detail_scroll: 0,
        last_body: Rect::default(),
        last_table_offset: 0,
        last_table_rows: 0,
    };
    let (mut term, _guard) = terminal()?;
    let mut refresh = Refresh::<io::Result<Vec<Listener>>>::default();
    let mut last = Instant::now();
    let mut quit = false;
    while !quit {
        if last.elapsed() >= Duration::from_secs(2) {
            refresh.start(async move {
                let result = tokio::task::spawn_blocking(scan_proc)
                    .await
                    .unwrap_or_else(|e| Err(io::Error::other(e)));
                if docker_enabled {
                    if let Ok(mut rows) = result {
                        let names = tokio::time::timeout(
                            Duration::from_secs(1),
                            docker_names(force_docker),
                        )
                        .await
                        .unwrap_or_default();
                        for r in &mut rows {
                            let kind = if r.protocol == "UDP" { "udp" } else { "tcp" };
                            r.docker = docker_for_listener(&names, kind, r.port, &r.address);
                        }
                        Ok(rows)
                    } else {
                        result
                    }
                } else {
                    result
                }
            });
            last = Instant::now()
        }
        if let Some(Ok(rows)) = refresh.take() {
            app.merge(rows)
        }
        term.draw(|f| render(f, &mut app))?;
        if event::poll(Duration::from_millis(80))? {
            match event::read()? {
                Event::Key(k) if k.kind != KeyEventKind::Release => {
                    if k.code == KeyCode::Char('q')
                        && k.modifiers.is_empty()
                        && !app.help
                        && !app.detail
                        && app.confirm.is_none()
                        && !app.filtering
                    {
                        quit = true
                    } else {
                        app.handle_key(k)
                    }
                }
                Event::Paste(text)
                    if app.filtering && !app.help && !app.detail && app.confirm.is_none() =>
                {
                    let selected = app.selected_row().map(Listener::key);
                    if app.filter.paste(&text) {
                        app.filter_changed(selected);
                    }
                }
                Event::Mouse(m)
                    if !app.help && !app.detail && app.confirm.is_none() && !app.filtering =>
                {
                    match m.kind {
                        MouseEventKind::ScrollDown
                            if app.last_body.contains((m.column, m.row).into()) =>
                        {
                            app.move_by(3)
                        }
                        MouseEventKind::ScrollUp
                            if app.last_body.contains((m.column, m.row).into()) =>
                        {
                            app.move_by(-3)
                        }
                        MouseEventKind::Down(_) => {
                            if let Some(index) = clicked_visible_row(
                                app.last_body,
                                app.last_table_offset,
                                app.visible().len(),
                                app.last_table_rows,
                                m.column,
                                m.row,
                            ) {
                                app.selected = index;
                            }
                        }
                        _ => {}
                    }
                }
                _ => {}
            }
        }
    }
    Ok(())
}

#[derive(serde::Deserialize)]
struct DockerContainer {
    #[serde(default, rename = "Names")]
    names: Vec<String>,
    #[serde(default, rename = "Ports")]
    ports: Vec<DockerPort>,
}
#[allow(non_snake_case)]
#[derive(serde::Deserialize)]
struct DockerPort {
    PublicPort: Option<u16>,
    #[serde(default)]
    IP: Option<String>,
    #[serde(default)]
    Type: String,
}
type DockerBindings = HashMap<(String, u16), Vec<(Option<std::net::IpAddr>, String)>>;
fn docker_for_listener(
    bindings: &DockerBindings,
    protocol: &str,
    port: u16,
    address: &str,
) -> String {
    let Ok(listener) = address.parse::<std::net::IpAddr>() else {
        return String::new();
    };
    let mut names = Vec::new();
    if let Some(entries) = bindings.get(&(protocol.to_owned(), port)) {
        for (published, name) in entries {
            let compatible = match published {
                Some(ip) if ip.is_unspecified() => ip.is_ipv4() == listener.is_ipv4(),
                Some(ip) => *ip == listener,
                None => listener.is_unspecified(),
            };
            if compatible && !names.contains(name) {
                names.push(name.clone());
            }
        }
    }
    names.join(", ")
}
async fn docker_names(force: bool) -> DockerBindings {
    use tokio::{
        io::{AsyncReadExt, AsyncWriteExt},
        net::UnixStream,
    };
    let docker_host = env::var("DOCKER_HOST").ok();
    let runtime = env::var_os("XDG_RUNTIME_DIR").map(std::path::PathBuf::from);
    let Some(path) = docker_socket_path(docker_host.as_deref(), runtime.as_deref(), force) else {
        return HashMap::new();
    };
    if !path.exists() {
        return HashMap::new();
    };
    let Ok(mut stream) = UnixStream::connect(path).await else {
        return HashMap::new();
    };
    let _ = stream
        .write_all(
            b"GET /containers/json?all=1 HTTP/1.1\r\nHost: docker\r\nConnection: close\r\n\r\n",
        )
        .await;
    let mut bytes = Vec::new();
    if stream.read_to_end(&mut bytes).await.is_err() {
        return HashMap::new();
    };
    let Some(split) = bytes.windows(4).position(|x| x == b"\r\n\r\n") else {
        return HashMap::new();
    };
    let mut body = &bytes[split + 4..];
    let headers = String::from_utf8_lossy(&bytes[..split]).to_lowercase();
    let decoded;
    if headers.contains("transfer-encoding: chunked") {
        let mut out = Vec::new();
        let mut rest = body;
        while let Some(end) = rest.windows(2).position(|x| x == b"\r\n") {
            let Ok(n) = usize::from_str_radix(
                std::str::from_utf8(&rest[..end])
                    .unwrap_or("0")
                    .split(';')
                    .next()
                    .unwrap_or("0"),
                16,
            ) else {
                break;
            };
            rest = &rest[end + 2..];
            if n == 0 || rest.len() < n + 2 {
                break;
            }
            out.extend_from_slice(&rest[..n]);
            rest = &rest[n + 2..]
        }
        decoded = out;
        body = &decoded;
    }
    let containers: Vec<DockerContainer> = serde_json::from_slice(body).unwrap_or_default();
    let mut map: DockerBindings = HashMap::new();
    for c in containers {
        let name = c
            .names
            .first()
            .map(|s| s.trim_start_matches('/').to_owned())
            .unwrap_or_default();
        if name.is_empty() {
            continue;
        }
        for p in c.ports {
            if let Some(port) = p.PublicPort {
                let ip =
                    p.IP.as_deref()
                        .and_then(|raw| raw.parse::<std::net::IpAddr>().ok());
                map.entry((p.Type, port))
                    .or_default()
                    .push((ip, name.clone()));
            }
        }
    }
    map
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn filter_keeps_selection_cancel_restores_and_empty_state_is_safe() {
        use ratatui::{backend::TestBackend, Terminal as TestTerminal};
        let make = |port, process: &str| Listener {
            protocol: "TCP".into(),
            address: "127.0.0.1".into(),
            port,
            pid: Some(port as i32),
            process: process.into(),
            command: process.into(),
            user: "me".into(),
            age: "1s".into(),
            inode: port as u64,
            start_ticks: Some(1),
            uid: Some(1000),
            cwd: "/tmp".into(),
            parent: None,
            docker: String::new(),
        };
        let mut app = App {
            rows: vec![make(1001, "alpha"), make(1002, "apple"), make(1003, "beta")],
            selected: 1,
            filter: TextInput::default(),
            filtering: false,
            filter_snapshot: None,
            search_cache: SearchCache::default(),
            sort: Sort::Port,
            message: String::new(),
            help: false,
            detail: false,
            confirm: None,
            detail_scroll: 0,
            last_body: Rect::default(),
            last_table_offset: 0,
            last_table_rows: 0,
        };
        app.handle_key(KeyEvent::new(KeyCode::Char('G'), KeyModifiers::SHIFT));
        assert_eq!(app.selected_row().unwrap().process, "beta");
        app.handle_key(KeyEvent::new(KeyCode::Char('g'), KeyModifiers::NONE));
        app.handle_key(KeyEvent::new(KeyCode::Down, KeyModifiers::NONE));
        app.handle_key(KeyEvent::new(KeyCode::Char('/'), KeyModifiers::NONE));
        app.handle_key(KeyEvent::new(KeyCode::Char('a'), KeyModifiers::NONE));
        app.handle_key(KeyEvent::new(KeyCode::Char('p'), KeyModifiers::NONE));
        app.handle_key(KeyEvent::new(KeyCode::Char('p'), KeyModifiers::NONE));
        app.handle_key(KeyEvent::new(KeyCode::Char('l'), KeyModifiers::NONE));
        app.handle_key(KeyEvent::new(KeyCode::Char('e'), KeyModifiers::NONE));
        assert_eq!(app.visible().len(), 1);
        assert_eq!(app.selected_row().unwrap().process, "apple");
        app.handle_key(KeyEvent::new(KeyCode::Up, KeyModifiers::NONE));
        app.handle_key(KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE));
        assert_eq!(app.filter.as_str(), "");
        assert_eq!(app.selected_row().unwrap().process, "apple");

        app.handle_key(KeyEvent::new(KeyCode::Char('/'), KeyModifiers::NONE));
        app.filter.paste("no-such-listener");
        let selected_key = app.selected_row().map(Listener::key);
        app.filter_changed(selected_key);
        let mut term = TestTerminal::new(TestBackend::new(90, 20)).unwrap();
        term.draw(|frame| render(frame, &mut app)).unwrap();
        let text = term
            .backend()
            .buffer()
            .content()
            .iter()
            .map(|cell| cell.symbol())
            .collect::<String>()
            .replace(' ', "");
        assert!(app.visible().is_empty());
        assert!(
            text.contains("没有匹配的监听项"),
            "empty state missing: {text:?}"
        );
        assert!(text.contains("Esc"));
        assert!(text.contains("清除过滤"));
        app.handle_key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE));
        term.draw(|frame| render(frame, &mut app)).unwrap();
        let committed = term
            .backend()
            .buffer()
            .content()
            .iter()
            .map(|cell| cell.symbol())
            .collect::<String>()
            .replace(' ', "");
        assert!(
            committed.contains("no-such-listener"),
            "committed filter disappeared: {committed:?}"
        );
    }

    #[test]
    fn ipv4_and_ipv6_proc_hex_decode() {
        assert_eq!(decode_addr("0100007F", false).as_deref(), Some("127.0.0.1"));
        assert_eq!(
            decode_addr("00000000000000000000000001000000", true).as_deref(),
            Some("::1")
        );
    }
    #[test]
    fn parses_only_listening_tcp() {
        let p = std::env::temp_dir().join(format!("ports-fixture-{}", std::process::id()));
        fs::write(&p,"sl local_address rem_address st tx_queue tr tm->when retrnsmt uid timeout inode\n 0: 0100007F:1F90 00000000:0000 0A 00000000:00000000 00:00000000 00000000 1000 0 42\n 1: 0100007F:1F91 00000000:0000 01 00000000:00000000 00:00000000 00000000 1000 0 43\n").unwrap();
        let rows = socket_rows(&p, "TCP", false).unwrap();
        let _ = fs::remove_file(p);
        assert_eq!(rows, vec![("TCP".into(), "127.0.0.1".into(), 8080, 42)]);
    }
    #[test]
    fn parses_only_unconnected_udp_bindings() {
        let p = std::env::temp_dir().join(format!("ports-udp-fixture-{}", std::process::id()));
        fs::write(
            &p,
            "sl local_address rem_address st tx_queue tr tm->when retrnsmt uid timeout inode\n 0: 0100007F:1F90 00000000:0000 07 00000000:00000000 00:00000000 00000000 1000 0 42\n 1: 0100007F:1F91 00000000:0000 01 00000000:00000000 00:00000000 00000000 1000 0 43\n",
        )
        .unwrap();
        let rows = socket_rows(&p, "UDP", false).unwrap();
        let _ = fs::remove_file(p);
        assert_eq!(rows, vec![("UDP".into(), "127.0.0.1".into(), 8080, 42)]);
    }
    #[test]
    fn refuses_uid_or_start_time_mismatch() {
        let d = (
            "x".into(),
            "x".into(),
            "x".into(),
            "x".into(),
            None,
            123,
            1000,
            String::new(),
        );
        assert!(same_process(&d, 1000, 123));
        assert!(!same_process(&d, 1001, 123));
        assert!(!same_process(&d, 1000, 124));
    }
    #[test]
    fn exposure_scope_distinguishes_loopback_wildcard_and_interface() {
        assert_eq!(scope("0.0.0.0"), "对外");
        assert_eq!(scope("::"), "对外");
        assert_eq!(scope("127.0.0.1"), "本机");
        assert_eq!(scope("127.42.0.7"), "本机");
        assert_eq!(scope("::1"), "本机");
        assert_eq!(scope("192.168.1.8"), "指定接口");
        assert_eq!(scope("2001:db8::8"), "指定接口");
    }
    #[test]
    fn docker_default_does_not_activate_demand_socket() {
        let runtime = std::env::temp_dir().join(format!("ports-docker-{}", std::process::id()));
        fs::create_dir_all(&runtime).unwrap();
        let public = runtime.join("docker.sock");
        assert_eq!(docker_socket_path(None, Some(&runtime), false), None);
        assert_eq!(
            docker_socket_path(
                Some(&format!("unix://{}", public.display())),
                Some(&runtime),
                false
            ),
            None
        );
        assert_eq!(
            docker_socket_path(Some("tcp://127.0.0.1:2375"), Some(&runtime), true),
            None
        );
        assert_eq!(
            docker_socket_path(None, Some(&runtime), true),
            Some(public.clone())
        );
        let private = runtime.join("docker-private.sock");
        fs::write(&private, b"fixture").unwrap();
        assert_eq!(
            docker_socket_path(None, Some(&runtime), false),
            Some(public.clone())
        );
        assert_eq!(
            docker_socket_path(
                Some(&format!("unix://{}", public.display())),
                Some(&runtime),
                false
            ),
            Some(public)
        );
        let custom = runtime.join("custom.sock");
        assert_eq!(
            docker_socket_path(
                Some(&format!("unix://{}", custom.display())),
                Some(&runtime),
                false
            ),
            Some(custom)
        );
        let _ = fs::remove_file(private);
        let _ = fs::remove_dir(runtime);
    }
    #[test]
    fn kill_requires_explicit_escalation_and_cancellable_second_confirmation() {
        let mut app = App {
            rows: vec![Listener {
                protocol: "TCP".into(),
                address: "127.0.0.1".into(),
                port: 32001,
                pid: Some(1),
                process: "test".into(),
                command: "fixture".into(),
                user: "me".into(),
                age: "1s".into(),
                inode: 1,
                start_ticks: Some(1),
                uid: Some(unsafe { libc::geteuid() }),
                cwd: "/tmp".into(),
                parent: None,
                docker: String::new(),
            }],
            selected: 0,
            filter: TextInput::default(),
            filtering: false,
            filter_snapshot: None,
            search_cache: SearchCache::default(),
            sort: Sort::Port,
            message: String::new(),
            help: false,
            detail: false,
            confirm: None,
            detail_scroll: 0,
            last_body: Rect::default(),
            last_table_offset: 0,
            last_table_rows: 0,
        };
        app.key(KeyCode::Char('x'));
        assert_eq!(app.confirm, Some((1, 1, false)));
        app.key(KeyCode::Char('k'));
        assert_eq!(app.confirm, Some((1, 1, true)));
        app.key(KeyCode::Esc);
        assert_eq!(app.confirm, None);
    }
    #[test]
    fn compact_and_wide_tables_keep_address_pid_process_and_scope_visible() {
        use ratatui::{backend::TestBackend, Terminal as TestTerminal};
        for width in [90, 120] {
            let mut app = App {
                rows: vec![Listener {
                    protocol: "TCP".into(),
                    address: "0.0.0.0".into(),
                    port: 5173,
                    pid: Some(4242),
                    process: "vite".into(),
                    command: format!("node {} tail_marker", "argument ".repeat(250)),
                    user: "mayon".into(),
                    age: "2m".into(),
                    inode: 7,
                    start_ticks: Some(1),
                    uid: Some(unsafe { libc::geteuid() }),
                    cwd: "/project".into(),
                    parent: Some(123),
                    docker: String::new(),
                }],
                selected: 0,
                filter: TextInput::default(),
                filtering: false,
                filter_snapshot: None,
                search_cache: SearchCache::default(),
                sort: Sort::Port,
                message: String::new(),
                help: false,
                detail: false,
                confirm: None,
                detail_scroll: 0,
                last_body: Rect::default(),
                last_table_offset: 0,
                last_table_rows: 0,
            };
            let mut term = TestTerminal::new(TestBackend::new(width, 32)).unwrap();
            term.draw(|f| render(f, &mut app)).unwrap();
            let buffer = term.backend().buffer();
            let text = buffer
                .content()
                .iter()
                .map(|c| c.symbol())
                .collect::<String>()
                .replace(' ', "");
            for expected in ["0.0.0.0:5173", "4242", "vite", "对外"] {
                assert!(
                    text.contains(expected),
                    "{expected} missing at width {width}"
                );
            }
            let red = buffer
                .content()
                .iter()
                .any(|cell| cell.symbol() == "对" && cell.fg == RED);
            let cyan = buffer
                .content()
                .iter()
                .any(|cell| cell.symbol() == "D" && cell.fg == CYAN);
            assert!(red, "external binding is not highlighted at width {width}");
            assert!(cyan, "development port is not highlighted at width {width}");
            app.detail = true;
            term.draw(|f| render(f, &mut app)).unwrap();
            let details = term
                .backend()
                .buffer()
                .content()
                .iter()
                .map(|c| c.symbol())
                .collect::<String>()
                .replace(' ', "");
            assert!(details.contains("完整命令行"));
            assert!(details.contains("/project"), "cwd is missing: {details:?}");
            assert!(
                !details.contains("tail_marker"),
                "long command unexpectedly fits without scrolling"
            );
            app.key(KeyCode::PageDown);
            term.draw(|f| render(f, &mut app)).unwrap();
            let tail = term
                .backend()
                .buffer()
                .content()
                .iter()
                .map(|c| c.symbol())
                .collect::<String>()
                .replace(' ', "");
            assert!(
                tail.contains("tail_marker"),
                "scroll did not expose command tail at width {width}"
            );
        }
    }
    #[test]
    fn filtered_first_row_gets_blue_selected_marker() {
        use ratatui::{backend::TestBackend, Terminal as TestTerminal};
        let make = |port, process: &str| Listener {
            protocol: "TCP".into(),
            address: "127.0.0.1".into(),
            port,
            pid: Some(port as i32),
            process: process.into(),
            command: process.into(),
            user: "me".into(),
            age: "1s".into(),
            inode: port as u64,
            start_ticks: Some(1),
            uid: Some(unsafe { libc::geteuid() }),
            cwd: "/tmp".into(),
            parent: None,
            docker: String::new(),
        };
        let mut app = App {
            rows: vec![make(1001, "other"), make(1002, "unique-filter")],
            selected: 0,
            filter: "unique-filter".into(),
            filtering: false,
            filter_snapshot: None,
            search_cache: SearchCache::default(),
            sort: Sort::Port,
            message: String::new(),
            help: false,
            detail: false,
            confirm: None,
            detail_scroll: 0,
            last_body: Rect::default(),
            last_table_offset: 0,
            last_table_rows: 0,
        };
        let mut term = TestTerminal::new(TestBackend::new(90, 20)).unwrap();
        term.draw(|f| render(f, &mut app)).unwrap();
        let marker_cell = term
            .backend()
            .buffer()
            .cell((app.last_body.x + 1, app.last_body.y + 2))
            .unwrap();
        assert_eq!(marker_cell.symbol(), "▏");
        assert_eq!(marker_cell.fg, BLUE);
        let selected_text = term
            .backend()
            .buffer()
            .cell((app.last_body.x + 3, app.last_body.y + 2))
            .unwrap();
        assert_eq!(selected_text.bg, SELECTION);
    }
    #[test]
    fn mouse_click_uses_table_offset_and_ignores_header_padding_and_overlay_space() {
        let body = Rect::new(0, 3, 90, 15);
        assert_eq!(clicked_visible_row(body, 10, 40, 11, 3, 5), Some(10));
        assert_eq!(clicked_visible_row(body, 10, 40, 11, 3, 6), Some(11));
        assert_eq!(clicked_visible_row(body, 10, 40, 11, 3, 4), None); // table header
        assert_eq!(clicked_visible_row(body, 10, 40, 11, 3, 14), Some(19));
        assert_eq!(clicked_visible_row(body, 10, 40, 12, 3, 16), Some(21)); // last visible data row
        assert_eq!(clicked_visible_row(body, 10, 40, 12, 3, 17), None); // blank row after table data
    }
    #[test]
    fn docker_mapping_respects_protocol_and_published_address() {
        use std::net::IpAddr;
        let mut bindings = DockerBindings::new();
        bindings.insert(
            ("tcp".into(), 8080),
            vec![
                (
                    Some("127.0.0.1".parse::<IpAddr>().unwrap()),
                    "web-local".into(),
                ),
                (
                    Some("192.0.2.10".parse::<IpAddr>().unwrap()),
                    "web-public".into(),
                ),
            ],
        );
        bindings.insert(
            ("udp".into(), 8080),
            vec![(Some("127.0.0.1".parse::<IpAddr>().unwrap()), "dns".into())],
        );
        assert_eq!(
            docker_for_listener(&bindings, "tcp", 8080, "127.0.0.1"),
            "web-local"
        );
        assert_eq!(
            docker_for_listener(&bindings, "tcp", 8080, "192.0.2.10"),
            "web-public"
        );
        assert_eq!(docker_for_listener(&bindings, "tcp", 8080, "127.0.0.2"), "");
        assert_eq!(
            docker_for_listener(&bindings, "udp", 8080, "127.0.0.1"),
            "dns"
        );
        assert_eq!(docker_for_listener(&bindings, "tcp", 8080, "::1"), "");
        bindings.insert(
            ("tcp".into(), 9000),
            vec![(Some("0.0.0.0".parse().unwrap()), "web-wildcard".into())],
        );
        assert_eq!(
            docker_for_listener(&bindings, "tcp", 9000, "192.0.2.10"),
            "web-wildcard"
        );
    }
    #[test]
    fn selected_socket_key_is_stable() {
        let a = Listener {
            protocol: "TCP".into(),
            address: "127.0.0.1".into(),
            port: 3000,
            pid: Some(10),
            process: "fixture".into(),
            command: "fixture".into(),
            user: "me".into(),
            age: "1s".into(),
            inode: 77,
            start_ticks: Some(1),
            uid: Some(1000),
            cwd: "/tmp".into(),
            parent: None,
            docker: String::new(),
        };
        let b = a.clone();
        assert_eq!(a.key(), b.key());
    }
}
