use crate::{
    config::Config,
    index::{self, Hit},
    open, qa,
};
use anyhow::Result;
use crossterm::event::{self, Event, KeyCode, KeyEventKind, MouseEventKind};
use mayon_ui::{self as ui, theme::*};
use ratatui::{
    layout::{Constraint, Layout, Rect},
    style::Style,
    text::{Line, Span},
    widgets::{Block, Paragraph, Wrap},
    Frame,
};
use std::{
    path::Path,
    sync::mpsc,
    thread,
    time::{Duration, Instant},
};
struct State {
    query: String,
    hits: Vec<Hit>,
    selected: usize,
    page: usize,
    editing: bool,
    help: bool,
    preview: bool,
    scroll: u16,
    message: String,
    answer: String,
    confirm: bool,
    busy: bool,
    searching: bool,
}
fn clean(s: &str) -> String {
    s.chars()
        .filter(|c| !c.is_control() || *c == '\n' || *c == '\t')
        .collect()
}
fn location(h: &Hit) -> String {
    let ext = Path::new(&h.chunk.path)
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    let page = h.chunk.page.map_or("段落".into(), |p| match ext.as_str() {
        "pptx" => format!("第 {p} 张"),
        "xlsx" => format!("工作表 {p}"),
        _ => format!("第 {p} 页"),
    });
    format!("{page} · L{}–{}", h.chunk.line_start, h.chunk.line_end)
}
fn display_path(path: &str, c: &Config) -> String {
    let p = Path::new(path);
    for root in &c.include {
        if let Ok(relative) = p.strip_prefix(root) {
            return format!(
                "{}/{}",
                root.file_name().unwrap_or_default().to_string_lossy(),
                relative.display()
            );
        }
    }
    clean(path)
}
fn icon(path: &str) -> &'static str {
    match Path::new(path)
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
    {
        "pdf" => "󰈙",
        "md" | "txt" => "󰍔",
        "pptx" => "󰈧",
        "docx" => "󰈭",
        "xlsx" => "󰈛",
        _ => "󰅩",
    }
}
fn highlight(text: &str, query: &str) -> Line<'static> {
    let mut spans = vec![];
    let tokens = index::terms(query);
    let mut buffer = String::new();
    let mut marked = false;
    for word in text.split_inclusive(char::is_whitespace) {
        let hit = tokens.iter().any(|t| word.to_lowercase().contains(t));
        if hit != marked && !buffer.is_empty() {
            spans.push(Span::styled(
                std::mem::take(&mut buffer),
                Style::default().fg(if marked { YELLOW } else { FG }),
            ));
        }
        marked = hit;
        buffer.push_str(word);
    }
    if !buffer.is_empty() {
        spans.push(Span::styled(
            buffer,
            Style::default().fg(if marked { YELLOW } else { FG }),
        ));
    }
    Line::from(spans)
}
fn render(f: &mut Frame, s: &State, c: &Config, data: &Path) {
    let area = ui::chrome(
        f,
        if s.busy {
            " SEEK  /  显式问答请求中  ·  正在发送所选片段"
        } else if s.page == 1 {
            " SEEK  /  显式问答  ·  发送前需确认"
        } else {
            " SEEK  /  本地资料  ·  只检索不外发"
        },
        &["搜索", "问答", "索引"],
        s.page,
        "/ 搜索  ↑↓ 移动  Enter 打开  a 问答  Tab 预览  ? 帮助  q 退出",
        &s.message,
    );
    if s.page == 0 {
        let rows = Layout::vertical([Constraint::Length(3), Constraint::Min(1)]).split(area);
        f.render_widget(
            Paragraph::new(format!(
                "{}{}",
                clean(&s.query),
                if s.editing { "▏" } else { "" }
            ))
            .style(ui::base())
            .block(ui::block(
                if s.searching {
                    " 自然语言搜索 · 检索中… "
                } else {
                    " 自然语言搜索 · / 编辑 · Esc 完成 "
                },
                s.editing,
            )),
            rows[0],
        );
        let wide = rows[1].width >= 110;
        let columns = Layout::horizontal([Constraint::Percentage(52), Constraint::Percentage(48)])
            .split(rows[1]);
        let list = if wide { columns[0] } else { rows[1] };
        if wide || !s.preview {
            render_list(f, list, s, c);
        }
        if wide || s.preview {
            let pane = if wide { columns[1] } else { rows[1] };
            let body = s
                .hits
                .get(s.selected)
                .map(|h| {
                    format!(
                        "{}\n{}\n{}\n\n{}",
                        clean(&h.chunk.path),
                        location(h),
                        clean(&h.chunk.title),
                        clean(&h.chunk.text)
                    )
                })
                .unwrap_or(
                    "输入问题开始搜索。\n\n所有检索在本地完成。\n问答需按 a 并确认发送片段。"
                        .into(),
                );
            f.render_widget(
                Paragraph::new(body)
                    .style(ui::base())
                    .block(ui::block(" 片段预览 · PgUp/PgDn 滚动 ", false))
                    .wrap(Wrap { trim: false })
                    .scroll((s.scroll, 0)),
                pane,
            );
        }
    } else if s.page == 1 {
        let rows = Layout::vertical([Constraint::Length(4), Constraint::Min(1)]).split(area);
        f.render_widget(
            Paragraph::new(format!(
                "{}{}\n后端 {} · Enter 预览发送确认 · / 编辑问题",
                clean(&s.query),
                if s.editing { "▏" } else { "" },
                c.qa.backend
            ))
            .style(ui::base())
            .block(ui::block(" 显式问答 · 仅发送 top-5 片段 ", s.editing))
            .wrap(Wrap { trim: false }),
            rows[0],
        );
        f.render_widget(
            Paragraph::new(clean(&s.answer))
                .style(ui::base())
                .block(ui::block(" 带引用的回答 ", false))
                .wrap(Wrap { trim: false })
                .scroll((s.scroll, 0)),
            rows[1],
        );
    } else {
        let body=match index::status(data){Ok(r)=>format!("文件         {}\n片段         {}\n索引模式     {}\n上次更新     Unix {}\n本次更新     {}\n本次移除     {}\n失败项       {}\n\n{}\n\n手动增量：seek index\n范围由 config.toml 的 include / exclude 决定。\n后台 timer 在电池供电时推迟；无常驻守护。",r.files,r.chunks,if r.hybrid{"BM25 + BGE + RRF"}else{"BM25 / Jieba"},r.updated_at,r.updated,r.removed,r.failures.len(),r.failures.iter().map(|(p,e)|format!("{}\n  {}",clean(p),clean(e))).collect::<Vec<_>>().join("\n")),Err(e)=>format!("{e:#}\n\n先运行 seek index")};
        f.render_widget(
            Paragraph::new(body)
                .style(ui::base())
                .block(ui::block(" 索引状态 ", true))
                .wrap(Wrap { trim: false })
                .scroll((s.scroll, 0)),
            area,
        );
    }
    if s.help {
        ui::help(f,"1 搜索 · 2 问答 · 3 索引状态\n/ 编辑自然语言问题 · Esc 完成\n↑/↓ 或 j/k 移动 · 滚轮移动 · 鼠标点击选中\nEnter 打开文件（PDF 尝试跳页）\na 问答视图 · Enter 后 y 确认发送 top-5 片段\nTab 窄窗切换列表/预览 · PgUp/PgDn 滚动\n? 帮助 · q 退出\n\n检索不访问网络。首次模型下载请用 seek model download。\n索引文件包含明文片段，目录权限为 0700。");
    }
    if s.confirm {
        ui::dialog(f," 发送片段确认 ",&format!("后端：{}\n问题：{}\n\n将发送前 {} 个检索片段及文件路径/页码，不发送整文件。\n资料中可能含个人信息。\n\ny 确认发送 · Esc 取消",c.qa.backend,clean(&s.query),s.hits.len().min(5)));
    }
}
fn render_list(f: &mut Frame, area: Rect, s: &State, c: &Config) {
    f.render_widget(
        Block::default()
            .style(ui::base())
            .borders(ratatui::widgets::Borders::ALL)
            .border_type(ratatui::widgets::BorderType::Rounded)
            .border_style(Style::default().fg(BORDER))
            .title(format!(" 检索结果 · {} ", s.hits.len())),
        area,
    );
    let inner = area.inner(ratatui::layout::Margin {
        horizontal: 1,
        vertical: 1,
    });
    let visible = (inner.height / 5).max(1) as usize;
    let offset = s.selected / visible * visible;
    for (i, h) in s.hits.iter().enumerate().skip(offset).take(visible) {
        let selected = i == s.selected;
        let name = Path::new(&h.chunk.path)
            .file_name()
            .unwrap_or_default()
            .to_string_lossy();
        let w = inner.width.saturating_sub(3) as usize;
        let spans = vec![
            Line::from(vec![
                ui::marker(selected),
                Span::styled(
                    clip(&format!(" {}  {}", icon(&h.chunk.path), clean(&name)), w),
                    Style::default().fg(if selected { BRIGHTFG } else { FG }),
                ),
            ]),
            Line::from(ui::muted(clip(
                &format!("   {}", display_path(&h.chunk.path, c)),
                w + 2,
            ))),
            Line::from(ui::muted(clip(&format!("   {}", location(h)), w + 2))),
            Line::from(vec![Span::raw("   ")]).patch_style(ui::base()),
        ];
        let rect = Rect::new(
            inner.x,
            inner.y + (i - offset) as u16 * 5,
            inner.width,
            4.min(inner.height),
        );
        let mut lines = spans;
        lines[3] = highlight(
            &clip(
                &format!("   {}", clean(&h.chunk.text).replace('\n', " ")),
                w + 2,
            ),
            &s.query,
        );
        f.render_widget(
            Paragraph::new(lines).style(ui::base().bg(if selected { SELECTION } else { BG })),
            rect,
        );
    }
    if s.hits.is_empty() {
        f.render_widget(
            Paragraph::new("\n  暂无结果\n\n  / 输入问题，检索本地资料")
                .style(ui::base().fg(MUTED)),
            inner,
        );
    }
}
pub fn run(c: Config, data: &Path, query: String, lexical: bool, viewer: String) -> Result<()> {
    let (tx, rx) = mpsc::channel::<(u64, String)>();
    let (out, results) = mpsc::channel();
    let root = data.to_path_buf();
    let hybrid = c.embeddings && !lexical;
    thread::spawn(move || {
        let mut search = index::Search::open(&root, hybrid);
        while let Ok(mut job) = rx.recv() {
            while let Ok(new) = rx.try_recv() {
                job = new;
            }
            let start = Instant::now();
            let hits = match &mut search {
                Ok(s) => s.query(&job.1, 30),
                Err(e) => Err(anyhow::anyhow!("{e:#}")),
            };
            if out.send((job.0, hits, start.elapsed())).is_err() {
                break;
            }
        }
    });
    let (qa_tx, qa_rx) = mpsc::channel();
    let mut s = State {
        query,
        hits: vec![],
        selected: 0,
        page: 0,
        editing: false,
        help: false,
        preview: false,
        scroll: 0,
        message: "本地检索 · 无资料外发".into(),
        answer: "按 / 编辑问题，Enter 后确认发送。\n\n仅显式问答使用后端，搜索不会读取 API 密钥。"
            .into(),
        confirm: false,
        busy: false,
        searching: true,
    };
    let mut revision = 0;
    tx.send((revision, s.query.clone()))?;
    let mut pending = None;
    let (mut terminal, _guard) = ui::terminal()?;
    loop {
        while let Ok((rev, hits, duration)) = results.try_recv() {
            if rev == revision {
                s.searching = false;
                match hits {
                    Ok(h) => {
                        s.hits = h;
                        s.selected = 0;
                        s.message = format!(
                            "{} 个片段 · {} ms · {} · 仅本地检索",
                            s.hits.len(),
                            duration.as_millis(),
                            if hybrid {
                                "Hybrid / RRF"
                            } else {
                                "BM25 / Jieba"
                            }
                        );
                    }
                    Err(e) => s.message = format!("{e:#}"),
                }
            }
        }
        if let Ok(answer) = qa_rx.try_recv() {
            s.busy = false;
            s.answer = match answer {
                Ok(a) => a,
                Err(e) => format!("{e:#}"),
            };
            s.message = "问答结束 · 请核对引用".into();
        }
        if pending.is_some_and(|t: Instant| t.elapsed() > Duration::from_millis(120)) {
            tx.send((revision, s.query.clone()))?;
            pending = None;
        }
        terminal.draw(|f| render(f, &s, &c, data))?;
        if !event::poll(Duration::from_millis(40))? {
            continue;
        }
        match event::read()? {
            Event::Key(k) if k.kind == KeyEventKind::Press => {
                if s.confirm {
                    match k.code {
                        KeyCode::Char('y') => {
                            s.confirm = false;
                            s.busy = true;
                            s.answer = "正在生成引用回答…".into();
                            s.message = "问答请求中（最多 90 秒）".into();
                            let tx = qa_tx.clone();
                            let q = s.query.clone();
                            let hits = s.hits.iter().take(5).cloned().collect::<Vec<_>>();
                            let backend = c.qa.clone();
                            thread::spawn(move || {
                                let _ = tx.send(qa::ask(&q, &hits, &backend));
                            });
                        }
                        KeyCode::Esc => s.confirm = false,
                        _ => {}
                    }
                    continue;
                }
                if s.help {
                    s.help = false;
                    continue;
                }
                if s.editing {
                    match k.code {
                        KeyCode::Esc => s.editing = false,
                        KeyCode::Enter => {
                            s.editing = false;
                            if s.page == 1 && !s.busy && !s.searching && !s.hits.is_empty() {
                                s.confirm = true;
                            }
                        }
                        KeyCode::Backspace => {
                            s.query.pop();
                            revision += 1;
                            pending = Some(Instant::now());
                            s.searching = true;
                        }
                        KeyCode::Char(ch) if s.query.chars().count() < 2000 => {
                            s.query.push(ch);
                            revision += 1;
                            pending = Some(Instant::now());
                            s.searching = true;
                        }
                        _ => {}
                    }
                    continue;
                }
                match k.code {
                    KeyCode::Char('q') => break,
                    KeyCode::Char('?') => s.help = true,
                    KeyCode::Char('/') => s.editing = true,
                    KeyCode::Char('1') => {
                        s.page = 0;
                        s.scroll = 0;
                    }
                    KeyCode::Char('2') | KeyCode::Char('a') => {
                        s.page = 1;
                        s.scroll = 0;
                    }
                    KeyCode::Char('3') => {
                        s.page = 2;
                        s.scroll = 0;
                    }
                    KeyCode::Down | KeyCode::Char('j') => {
                        s.selected = (s.selected + 1).min(s.hits.len().saturating_sub(1))
                    }
                    KeyCode::Up | KeyCode::Char('k') => s.selected = s.selected.saturating_sub(1),
                    KeyCode::Tab => s.preview = !s.preview,
                    KeyCode::PageDown => s.scroll = s.scroll.saturating_add(8),
                    KeyCode::PageUp => s.scroll = s.scroll.saturating_sub(8),
                    KeyCode::Enter if s.page == 0 => {
                        if let Some(h) = s.hits.get(s.selected) {
                            s.message = match open::open(h, &viewer) {
                                Ok(()) => "已请求默认程序打开 · PDF 跳页取决于 viewer".into(),
                                Err(e) => format!("{e:#}"),
                            };
                        }
                    }
                    KeyCode::Enter
                        if s.page == 1 && !s.busy && !s.searching && !s.hits.is_empty() =>
                    {
                        s.confirm = true
                    }
                    _ => {}
                }
            }
            Event::Mouse(m) => match m.kind {
                MouseEventKind::ScrollDown => {
                    s.selected = (s.selected + 1).min(s.hits.len().saturating_sub(1))
                }
                MouseEventKind::ScrollUp => s.selected = s.selected.saturating_sub(1),
                MouseEventKind::Down(_) => {
                    let row = m.row.saturating_sub(7) as usize / 5;
                    let visible = (terminal.size()?.height.saturating_sub(10) / 5).max(1) as usize;
                    s.selected =
                        (s.selected / visible * visible + row).min(s.hits.len().saturating_sub(1));
                }
                _ => {}
            },
            _ => {}
        }
    }
    Ok(())
}
