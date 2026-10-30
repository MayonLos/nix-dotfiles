use crate::{
    actions,
    library::{Entry, Library},
    self_command, start_ocr,
};
use anyhow::Result;
use base64::{engine::general_purpose::STANDARD, Engine};
use chrono::{Local, TimeZone};
use crossterm::event::{self, Event, KeyCode, KeyEventKind, MouseEventKind};
use mayon_ui::{self as ui, input::TextInput, search::Matcher, theme::*};
use ratatui::{
    layout::{Constraint, Layout, Rect},
    widgets::{Paragraph, Wrap},
};
use std::{
    collections::hash_map::DefaultHasher,
    fs,
    hash::{Hash, Hasher},
    io::{self, Write},
    path::Path,
    process::{Command, Stdio},
    sync::mpsc,
    thread,
    time::{Duration, Instant},
};

#[derive(Default)]
struct State {
    page: usize,
    selected: usize,
    total: usize,
    offset: usize,
    query: String,
    source: String,
    date: String,
    input: Option<(char, TextInput)>,
    previous_filter: String,
    help: bool,
    delete: u8,
    delete_target: Option<Entry>,
    message: String,
}
fn clean(s: &str) -> String {
    s.chars()
        .filter(|c| !c.is_control() || *c == '\n')
        .collect()
}
fn date(e: &Entry) -> String {
    Local
        .timestamp_opt(e.modified, 0)
        .single()
        .map(|d| d.format("%Y-%m-%d").to_string())
        .unwrap_or_default()
}
fn time(e: &Entry) -> String {
    Local
        .timestamp_opt(e.modified, 0)
        .single()
        .map(|d| d.format("%H:%M").to_string())
        .unwrap_or_default()
}
fn entries(lib: &Library, s: &State) -> Result<Vec<Entry>> {
    let favorite = s.page == 1;
    Ok(lib
        .entries(
            &s.query,
            if s.source.is_empty() {
                None
            } else {
                Some(&s.source)
            },
            favorite,
        )?
        .into_iter()
        .filter(|e| s.date.is_empty() || date(e).starts_with(&s.date))
        .collect())
}
fn reload(lib: &Library, s: &mut State, data: &mut Vec<Entry>) -> Result<()> {
    let keep = data.get(s.selected).map(|e| e.path.clone());
    *data = entries(lib, s)?;
    s.total = lib.entries("", None, s.page == 1)?.len();
    s.selected = keep
        .and_then(|id| data.iter().position(|e| e.path == id))
        .unwrap_or(0);
    s.offset = s.offset.min(s.selected);
    Ok(())
}
fn update_filter(s: &mut State) {
    if let Some((which, text)) = &s.input {
        let value = text.as_str().to_owned();
        match which {
            's' => s.source = value,
            'D' => s.date = value,
            _ => s.query = value,
        }
    }
}
struct Preview {
    key: String,
    png: String,
    width: u32,
    height: u32,
}
fn preview_key(e: &Entry) -> String {
    let stamp = fs::symlink_metadata(&e.path)
        .ok()
        .map(|m| (m.len(), m.modified().ok()));
    format!("{}:{}:{stamp:?}", e.path, e.modified)
}
fn thumbnail(dir: &Path, e: &Entry) -> Result<Preview> {
    let key = preview_key(e);
    let mut hash = DefaultHasher::new();
    key.hash(&mut hash);
    let cache = dir.join("thumbs");
    fs::create_dir_all(&cache)?;
    let file = cache.join(format!("{:x}.png", hash.finish()));
    let bytes = if file.exists() {
        fs::read(file)?
    } else {
        let mut c = Command::new("timeout");
        c.args([
            "20s",
            "ffmpeg",
            "-v",
            "error",
            "-threads",
            "1",
            "-protocol_whitelist",
            "file,pipe",
        ]);
        let out = c
            .args([
                "-i",
                &e.path,
                "-vf",
                "scale=640:640:force_original_aspect_ratio=decrease",
                "-frames:v",
                "1",
                "-threads",
                "1",
                "-f",
                "image2pipe",
                "-vcodec",
                "png",
                "-",
            ])
            .stdin(Stdio::null())
            .output()?;
        anyhow::ensure!(out.status.success(), "无法生成缩略图");
        fs::write(&file, &out.stdout)?;
        out.stdout
    };
    anyhow::ensure!(
        bytes.len() > 24 && bytes.starts_with(b"\x89PNG\r\n\x1a\n"),
        "无效 PNG 缩略图"
    );
    let width = u32::from_be_bytes(bytes[16..20].try_into()?);
    let height = u32::from_be_bytes(bytes[20..24].try_into()?);
    Ok(Preview {
        key,
        png: STANDARD.encode(bytes),
        width,
        height,
    })
}
fn clear_image() {
    let _ = write!(io::stdout(), "\x1b_Ga=d,d=A,q=2\x1b\\");
}
fn draw_image(p: &Preview, a: Rect) -> io::Result<()> {
    if a.width < 2 || a.height < 2 {
        return Ok(());
    }
    // Kitty's cells are approximately twice as tall as they are wide.
    let ratio = p.width as f64 / p.height.max(1) as f64;
    let columns = (f64::from(a.height) * 2.0 * ratio)
        .min(f64::from(a.width))
        .max(1.0) as u16;
    let rows = (f64::from(columns) / (2.0 * ratio)).ceil().max(1.0) as u16;
    let mut stdout = io::stdout();
    write!(stdout, "\x1b7\x1b[{};{}H", a.y + 1, a.x + 1)?;
    let parts: Vec<_> = p.png.as_bytes().chunks(4096).collect();
    for (i, chunk) in parts.iter().enumerate() {
        let more = usize::from(i + 1 < parts.len());
        if i == 0 {
            write!(
                stdout,
                "\x1b_Ga=T,f=100,t=d,i=1,c={columns},r={rows},q=2,m={more};"
            )?;
        } else {
            write!(stdout, "\x1b_Gm={more};")?;
        }
        stdout.write_all(chunk)?;
        stdout.write_all(b"\x1b\\")?;
    }
    stdout.write_all(b"\x1b8")?;
    stdout.flush()
}
const HELP: &str = "1 截图  2 收藏\nj/k 或 ↑/↓ 移动 · PgUp/PgDn 翻页 · 鼠标选中/滚动\n/ 文件名 / OCR / 日期搜索 · s 来源过滤 · D 日期前缀\nEsc 清空过滤 · Enter/o 打开 · y 复制路径 · c 复制图片\nf 文件管理器定位 · e 标注 · * 收藏 · t 复制 OCR 文字\nd 删除：先确认对象，再按大写 Y 移入回收站（不会永久删除）\np 暂停/恢复后台 OCR · i 增量索引\n? 帮助 · q 退出\n\n未知来源不会猜测；已有截图通常没有来源窗口元数据。";

pub fn run(lib: Library) -> Result<()> {
    lib.index()?;
    start_ocr(&lib)?;
    let (mut terminal, _guard) = ui::terminal()?;
    // Match the shared One Dark canvas to Kitty's surrounding background.
    if let ratatui::style::Color::Rgb(r, g, b) = BG {
        print!("\x1b]11;#{r:02x}{g:02x}{b:02x}\x07");
    }
    io::stdout().flush()?;
    struct Images;
    impl Drop for Images {
        fn drop(&mut self) {
            clear_image();
            let _ = write!(io::stdout(), "\x1b]111\x07");
        }
    }
    let _images = Images;
    let mut s = State {
        message: "本地图库 · OCR 低优先级后台处理".into(),
        ..Default::default()
    };
    let (tx, rx) = mpsc::channel::<Result<Preview>>();
    let mut pending = false;
    let mut requested = String::new();
    let mut preview: Option<Preview> = None;
    let mut last_refresh = Instant::now();
    let mut last_index = Instant::now();
    let mut index_job: Option<std::process::Child> = None;
    let mut data = entries(&lib, &s)?;
    s.total = lib.entries("", None, s.page == 1)?.len();
    let mut list_area = Rect::default();
    let mut image_area = Rect::default();
    let kitty = std::env::var_os("KITTY_WINDOW_ID").is_some()
        || std::env::var("TERM").unwrap_or_default().contains("kitty");
    loop {
        if let Some(child) = index_job.as_mut() {
            if child.try_wait()?.is_some() {
                index_job = None;
            }
        }
        if index_job.is_none() && last_index.elapsed() > Duration::from_secs(20) {
            let mut command = self_command()?;
            index_job = Some(
                command
                    .arg("index")
                    .stdin(Stdio::null())
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .spawn()?,
            );
            last_index = Instant::now();
        }
        if let Ok(result) = rx.try_recv() {
            pending = false;
            match result {
                Ok(p) => preview = Some(p),
                Err(e) => s.message = format!("预览：{e}"),
            }
        }
        if last_refresh.elapsed() > Duration::from_secs(3) {
            reload(&lib, &mut s, &mut data)?;
            last_refresh = Instant::now();
        }
        s.selected = s.selected.min(data.len().saturating_sub(1));
        let selected = data.get(s.selected);
        let key = selected.map(preview_key).unwrap_or_default();
        if !pending && key != requested {
            requested = key.clone();
            preview = None;
            if let Some(e) = selected.cloned() {
                let dir = lib.dir.clone();
                let tx = tx.clone();
                pending = true;
                thread::spawn(move || {
                    let _ = tx.send(thumbnail(&dir, &e));
                });
            }
        }
        clear_image();
        terminal.draw(|f| {
            let total = s.total;
            let title = format!(
                " Shots · 截图库     {}/{} 项 · OCR {}",
                data.len(),
                total,
                if lib.paused() { "已暂停" } else { "后台" }
            );
            let body = ui::chrome(
                f,
                &title,
                &["截图", "收藏"],
                s.page,
                " / 搜索  Enter 打开  * 收藏  ? 帮助  q 退出",
                &s.message,
            );
            let chunks = Layout::vertical([Constraint::Length(1), Constraint::Min(4)]).split(body);
            f.render_widget(
                Paragraph::new(ui::theme::clip(
                    &format!(
                        " 搜索 {}  来源 {}  日期 {}",
                        if s.query.is_empty() {
                            "全部"
                        } else {
                            &s.query
                        },
                        if s.source.is_empty() {
                            "全部"
                        } else {
                            &s.source
                        },
                        if s.date.is_empty() { "全部" } else { &s.date }
                    ),
                    chunks[0].width as usize,
                ))
                .style(ui::base().fg(MUTED)),
                chunks[0],
            );
            let wide = body.width >= 112;
            let areas = if wide {
                Layout::horizontal([Constraint::Percentage(55), Constraint::Percentage(45)])
                    .split(chunks[1])
            } else {
                Layout::vertical([Constraint::Percentage(58), Constraint::Percentage(42)])
                    .split(chunks[1])
            };
            list_area = areas[0];
            let capacity = list_area.height.saturating_sub(3).max(1) as usize;
            if s.selected < s.offset {
                s.offset = s.selected;
            }
            if s.selected >= s.offset + capacity {
                s.offset = s.selected + 1 - capacity;
            }
            let mut previous = String::new();
            let rows = data
                .iter()
                .skip(s.offset)
                .take(capacity)
                .map(|e| {
                    let day = date(e);
                    let group = if day == previous {
                        String::new()
                    } else {
                        previous = day.clone();
                        day
                    };
                    vec![
                        group,
                        format!("{} {}", if e.favorite { "★" } else { " " }, time(e)),
                        clean(&e.name).replace('\n', " "),
                    ]
                    .into_iter()
                    .map(|text| {
                        Matcher::new(&format!("{} {} {}", s.query, s.source, s.date))
                            .highlight(&text)
                    })
                    .collect::<Vec<_>>()
                })
                .collect();
            ui::table_highlighted(
                f,
                list_area,
                " 时间线 ",
                vec!["日期", "时间", "截图"],
                rows,
                &[
                    Constraint::Length(10),
                    Constraint::Length(7),
                    Constraint::Min(8),
                ],
                s.selected.saturating_sub(s.offset),
            );
            let preview_box = ui::block(" 预览 · Kitty / OCR ", false);
            let inner = preview_box.inner(areas[1]);
            f.render_widget(preview_box, areas[1]);
            let pa =
                Layout::vertical([Constraint::Percentage(62), Constraint::Min(3)]).split(inner);
            image_area = pa[0];
            if let Some(e) = selected {
                let text = format!(
                    "{}\n{}\n{}",
                    clean(&e.source),
                    clean(&e.path),
                    if e.text.is_empty() {
                        "OCR 待处理 / 无文字".into()
                    } else {
                        clean(&e.text)
                    }
                );
                f.render_widget(
                    Paragraph::new(
                        text.lines()
                            .map(|line| {
                                Matcher::new(&format!("{} {} {}", s.query, s.source, s.date))
                                    .highlight(line)
                            })
                            .collect::<Vec<_>>(),
                    )
                    .style(ui::base().fg(MUTED))
                    .wrap(Wrap { trim: false }),
                    pa[1],
                );
                if !kitty {
                    f.render_widget(
                        Paragraph::new("使用 Kitty 查看图形缩略图").style(ui::base()),
                        pa[0],
                    );
                }
            } else {
                f.render_widget(
                    Paragraph::new("没有匹配文件\n/ 搜索 · Esc 清空过滤").style(ui::base()),
                    inner,
                );
            }
            if s.help {
                ui::help(f, HELP);
            }
            if let Some((which, text)) = &s.input {
                ui::input(
                    f,
                    match which {
                        's' => " 来源窗口过滤 ",
                        'D' => " 日期前缀 YYYY-MM-DD ",
                        _ => " 搜索 · 文件名 / OCR / 日期 ",
                    },
                    text,
                );
            }
            if s.delete > 0 {
                ui::dialog(
                    f,
                    if s.delete == 1 {
                        " 确认删除对象 "
                    } else {
                        " 第二次确认 · 移入回收站 "
                    },
                    &format!(
                        "{}\n\n{}",
                        s.delete_target
                            .as_ref()
                            .map(|e| clean(&e.name))
                            .unwrap_or_default(),
                        if s.delete == 1 {
                            "Enter 继续 · Esc 取消"
                        } else {
                            "大写 Y 移入回收站 · Esc 取消"
                        }
                    ),
                );
            }
        })?;
        if kitty && !s.help && s.input.is_none() && s.delete == 0 {
            if let Some(p) = preview.as_ref().filter(|p| p.key == key) {
                draw_image(p, image_area)?;
            }
        }
        if !event::poll(Duration::from_millis(250))? {
            continue;
        }
        match event::read()? {
            Event::Key(k) if k.kind == KeyEventKind::Press => {
                if s.input.is_some() {
                    match k.code {
                        KeyCode::Esc => {
                            let which = s.input.as_ref().unwrap().0;
                            let value = s.previous_filter.clone();
                            match which {
                                's' => s.source = value,
                                'D' => s.date = value,
                                _ => s.query = value,
                            }
                            s.input = None;
                            reload(&lib, &mut s, &mut data)?;
                        }
                        KeyCode::Enter => s.input = None,
                        KeyCode::Down => {
                            s.selected = (s.selected + 1).min(data.len().saturating_sub(1))
                        }
                        KeyCode::Up => s.selected = s.selected.saturating_sub(1),
                        _ => {
                            if s.input.as_mut().unwrap().1.handle_key(k) {
                                update_filter(&mut s);
                                reload(&lib, &mut s, &mut data)?;
                            }
                        }
                    }
                    continue;
                }
                if k.modifiers
                    .intersects(event::KeyModifiers::CONTROL | event::KeyModifiers::ALT)
                {
                    continue;
                }
                if s.help {
                    if matches!(
                        k.code,
                        KeyCode::Esc | KeyCode::Char('?') | KeyCode::Char('q')
                    ) {
                        s.help = false;
                    }
                    continue;
                }
                if s.delete > 0 {
                    match k.code {
                        KeyCode::Esc => {
                            s.delete = 0;
                            s.delete_target = None;
                        }
                        KeyCode::Enter if s.delete == 1 => s.delete = 2,
                        KeyCode::Char('Y') if s.delete == 2 => {
                            if let Some(e) = s.delete_target.as_ref() {
                                s.message = match actions::trash(e, &lib) {
                                    Ok(()) => "已移入回收站".into(),
                                    Err(e) => format!("{e:#}"),
                                };
                            }
                            s.delete = 0;
                            s.delete_target = None;
                            reload(&lib, &mut s, &mut data)?;
                        }
                        _ => {}
                    }
                    continue;
                }
                match k.code {
                    KeyCode::Char('q') => break,
                    KeyCode::Char('?') => s.help = true,
                    KeyCode::Char(c @ '1'..='2') => {
                        s.page = (c as u8 - b'1') as usize;
                        s.selected = 0;
                        s.offset = 0;
                        reload(&lib, &mut s, &mut data)?;
                    }
                    KeyCode::Char(c @ ('/' | 's' | 'D')) => {
                        s.previous_filter = match c {
                            's' => s.source.clone(),
                            'D' => s.date.clone(),
                            _ => s.query.clone(),
                        };
                        s.input = Some((c, TextInput::new(s.previous_filter.clone())));
                    }
                    KeyCode::Esc => {
                        s.query.clear();
                        s.source.clear();
                        s.date.clear();
                        reload(&lib, &mut s, &mut data)?;
                    }
                    KeyCode::Down | KeyCode::Char('j') => {
                        s.selected = (s.selected + 1).min(data.len().saturating_sub(1))
                    }
                    KeyCode::Up | KeyCode::Char('k') => s.selected = s.selected.saturating_sub(1),
                    KeyCode::Home | KeyCode::Char('g') => s.selected = 0,
                    KeyCode::End | KeyCode::Char('G') => s.selected = data.len().saturating_sub(1),
                    KeyCode::PageDown => {
                        s.selected = (s.selected + list_area.height.saturating_sub(3) as usize)
                            .min(data.len().saturating_sub(1))
                    }
                    KeyCode::PageUp => {
                        s.selected = s
                            .selected
                            .saturating_sub(list_area.height.saturating_sub(3) as usize)
                    }
                    KeyCode::Char('p') => {
                        lib.set_paused(!lib.paused())?;
                        if !lib.paused() {
                            start_ocr(&lib)?;
                        }
                        s.message = "OCR 暂停状态已更新".into();
                    }
                    KeyCode::Char('i') => {
                        s.message = format!("已索引 {} 项", lib.index()?);
                        start_ocr(&lib)?;
                        reload(&lib, &mut s, &mut data)?;
                    }
                    KeyCode::Char('d') if selected.is_some() => {
                        s.delete_target = selected.cloned();
                        s.delete = 1;
                    }
                    KeyCode::Enter => {
                        if let Some(e) = selected {
                            s.message =
                                actions::action(e, 'o', &lib).unwrap_or_else(|e| format!("{e:#}"));
                        }
                    }
                    KeyCode::Char(c @ ('o' | 'y' | 'c' | 't' | 'e' | 'f' | '*')) => {
                        if let Some(e) = selected {
                            s.message =
                                actions::action(e, c, &lib).unwrap_or_else(|e| format!("{e:#}"));
                            reload(&lib, &mut s, &mut data)?;
                        }
                    }
                    _ => {}
                }
            }
            Event::Paste(text)
                if s.input.is_some()
                    && !s.help
                    && s.delete == 0
                    && s.input.as_mut().unwrap().1.paste(&text) =>
            {
                update_filter(&mut s);
                reload(&lib, &mut s, &mut data)?;
            }
            Event::Mouse(m) if s.input.is_none() && !s.help && s.delete == 0 => match m.kind {
                MouseEventKind::ScrollDown => {
                    s.selected = (s.selected + 1).min(data.len().saturating_sub(1))
                }
                MouseEventKind::ScrollUp => s.selected = s.selected.saturating_sub(1),
                MouseEventKind::Down(_)
                    if s.input.is_none()
                        && !s.help
                        && s.delete == 0
                        && m.column > list_area.x
                        && m.column < list_area.right()
                        && m.row >= list_area.y + 2
                        && m.row < list_area.bottom() - 1 =>
                {
                    s.selected = (s.offset + (m.row - list_area.y - 2) as usize)
                        .min(data.len().saturating_sub(1));
                }
                _ => {}
            },
            Event::Resize(_, _) => {
                terminal.clear()?;
            }
            _ => {}
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn incremental_filter_preserves_path_and_empty_selection() {
        let home = tempfile::tempdir().unwrap();
        let root = home.path().join("Pictures/mark-shot");
        fs::create_dir_all(&root).unwrap();
        fs::write(root.join("Apple.png"), b"fixture").unwrap();
        fs::write(root.join("中文.png"), b"fixture").unwrap();
        let lib = Library::open_under(home.path().to_path_buf()).unwrap();
        lib.index().unwrap();
        let mut state = State::default();
        let mut data = entries(&lib, &state).unwrap();
        state.selected = data.iter().position(|e| e.name == "中文.png").unwrap();
        state.input = Some(('/', TextInput::from("zhongwen")));
        update_filter(&mut state);
        reload(&lib, &mut state, &mut data).unwrap();
        assert_eq!(data.len(), 1);
        assert_eq!(data[state.selected].name, "中文.png");
        state.input.as_mut().unwrap().1.set("没有匹配");
        update_filter(&mut state);
        reload(&lib, &mut state, &mut data).unwrap();
        assert!(data.is_empty());
        assert_eq!(state.selected, 0);
        state.query.clear();
        reload(&lib, &mut state, &mut data).unwrap();
        assert_eq!(data.len(), 2);
    }
}
