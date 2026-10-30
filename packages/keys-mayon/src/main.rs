mod model;

use anyhow::{bail, Context, Result};
use crossterm::event::{
    self, Event, KeyCode, KeyEventKind, KeyModifiers, MouseButton, MouseEventKind,
};
use mayon_ui::{
    self as ui,
    input::TextInput,
    search::{Matcher, SearchText},
    theme::*,
};
use model::{entries, Entry, Export, GROUPS};
use ratatui::{
    layout::{Constraint, Layout, Rect},
    style::Modifier,
    text::{Line, Span},
    widgets::{Block, Paragraph, Wrap},
    Frame,
};
use std::{fs, path::PathBuf, time::Duration};

fn config_path() -> Result<PathBuf> {
    if let Some(path) = std::env::var_os("KEYS_MAYON_DATA") {
        return Ok(path.into());
    }
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))
        .context("缺少 XDG_CONFIG_HOME / HOME，请用 --data 指定生成的 JSON")?;
    Ok(base.join("keys-mayon/bindings.json"))
}

fn main() -> Result<()> {
    let mut path = None;
    let mut list = false;
    let mut json = false;
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--data" => path = Some(PathBuf::from(args.next().context("--data 需要路径")?)),
            "list" if !list => list = true,
            "--json" => json = true,
            "--help" | "-h" => {
                println!("keys-mayon [--data PATH] [list [--json]]\n\nMango 快捷键速查（生成数据，只读）\n默认读取 $XDG_CONFIG_HOME/keys-mayon/bindings.json\n可用 KEYS_MAYON_DATA 或 --data 覆盖。\n\n/ 模糊搜索 · 0 全部 / 1–7 分组 · j/k 移动 · 鼠标滚动\nEnter 原始动作 · ? 帮助 · q / Esc 关闭");
                return Ok(());
            }
            "--version" | "-V" => {
                println!("keys-mayon {}", env!("CARGO_PKG_VERSION"));
                return Ok(());
            }
            _ => bail!("未知参数 {arg}，请运行 keys-mayon --help"),
        }
    }
    if json && !list {
        bail!("--json 需要 list 子命令");
    }
    let path = path.map_or_else(config_path, Ok)?;
    let export: Export = serde_json::from_slice(&fs::read(&path).with_context(|| {
        format!(
            "无法读取 {}；请先构建并安装 Mango 导出的 JSON，或指定 --data",
            path.display()
        )
    })?)
    .context("快捷键 JSON 格式无效")?;
    let items = entries(export)?;
    if list {
        if json {
            println!("{}", serde_json::to_string_pretty(&items.iter().map(|e| serde_json::json!({
                "mode": e.binding.mode, "kind": e.binding.kind, "raw": e.binding.raw,
                "chord": e.chord, "group": GROUPS[e.group], "description": e.description,
                "conflict": e.conflict
            })).collect::<Vec<_>>())?);
        } else {
            for (group, title) in GROUPS.iter().enumerate() {
                println!("\n{title}");
                for e in items.iter().filter(|e| e.group == group) {
                    println!(
                        "{}{} [{} · {}] {}\n  {}",
                        if e.conflict { "冲突 " } else { "" },
                        e.chord,
                        e.binding.mode,
                        e.binding.kind,
                        e.description,
                        e.binding.raw
                    );
                }
            }
        }
        return Ok(());
    }
    run(items, path)
}

#[derive(Default)]
struct App {
    group: Option<usize>,
    search: Vec<SearchText>,
    query: TextInput,
    previous_query: TextInput,
    editing: bool,
    selected: usize,
    scroll: usize,
    help: bool,
    details: bool,
    detail_scroll: u16,
    hits: Vec<(Rect, usize)>,
    tabs: Vec<(Rect, Option<usize>)>,
    viewport: usize,
    total_rows: usize,
}

impl App {
    fn new(items: &[Entry]) -> Self {
        Self {
            search: items
                .iter()
                .map(|e| {
                    SearchText::new(&format!(
                        "{} {} {} {} {}",
                        e.chord, e.description, e.binding.mode, e.binding.kind, e.binding.raw
                    ))
                })
                .collect(),
            ..Default::default()
        }
    }
    fn visible(&self, items: &[Entry]) -> Vec<usize> {
        let matcher = Matcher::new(&self.query);
        let mut out = items
            .iter()
            .enumerate()
            .filter(|(i, e)| {
                self.group.is_none_or(|g| e.group == g)
                    && self
                        .search
                        .get(*i)
                        .is_some_and(|text| matcher.matches_in(text))
            })
            .map(|(i, _)| i)
            .collect::<Vec<_>>();
        out.sort_by_key(|i| items[*i].group);
        out
    }
    fn keep_selected(&mut self, items: &[Entry], selected: Option<usize>) {
        self.selected = selected
            .and_then(|id| self.visible(items).iter().position(|i| *i == id))
            .unwrap_or(0);
    }
    fn reset(&mut self) {
        self.selected = 0;
        self.scroll = 0;
    }
    fn move_selection(&mut self, delta: isize, count: usize) {
        self.selected = self
            .selected
            .saturating_add_signed(delta)
            .min(count.saturating_sub(1));
    }
}

type Position = (usize, usize, usize, Option<usize>);

// Groups occupy columns; a single filtered group flows across all columns.
// At 90 cells each shortcut gets two full lines;
// long commands remain available in the detail pane and machine-readable list.
fn positions(items: &[Entry], visible: &[usize], columns: usize) -> (Vec<Position>, usize) {
    if let Some(first) = visible.first() {
        let group = items[*first].group;
        if visible.iter().all(|i| items[*i].group == group) {
            let per_column = visible.len().div_ceil(columns);
            let mut out = Vec::new();
            for (col, chunk) in visible.chunks(per_column).enumerate() {
                out.push((col, 0, group, None));
                for (row, _) in chunk.iter().enumerate() {
                    out.push((col, 2 + row * 3, group, Some(col * per_column + row)));
                }
            }
            return (out, 3 + per_column * 3);
        }
    }
    let mut heights = vec![0usize; columns];
    let mut out = Vec::new();
    for group in 0..GROUPS.len() {
        let rows = visible
            .iter()
            .enumerate()
            .filter(|(_, i)| items[**i].group == group)
            .collect::<Vec<_>>();
        if rows.is_empty() {
            continue;
        }
        let col = heights
            .iter()
            .enumerate()
            .min_by_key(|(_, h)| **h)
            .unwrap()
            .0;
        out.push((col, heights[col], group, None));
        heights[col] += 2;
        for (selection, _) in rows {
            out.push((col, heights[col], group, Some(selection)));
            heights[col] += 3;
        }
        heights[col] += 1;
    }
    (out, heights.into_iter().max().unwrap_or(0))
}

fn draw(f: &mut Frame, app: &mut App, items: &[Entry], path: &std::path::Path, follow: bool) {
    let area = f.area();
    f.render_widget(Block::default().style(ui::base()), area);
    let c = Layout::vertical([
        Constraint::Length(1),
        Constraint::Length(2),
        Constraint::Length(1),
        Constraint::Min(1),
        Constraint::Length(3),
        Constraint::Length(2),
    ])
    .split(area);
    let visible = app.visible(items);
    app.selected = app.selected.min(visible.len().saturating_sub(1));
    let conflicts = items.iter().filter(|e| e.conflict).count();
    ui::status(
        f,
        c[0],
        &format!(
            " 快捷键速查  Mango · {} / {} 条 · {} 条冲突",
            visible.len(),
            items.len(),
            conflicts
        ),
    );
    app.tabs.clear();
    let mut x = c[1].x;
    for (number, group) in std::iter::once(None).chain((0..7).map(Some)).enumerate() {
        let title = format!(" {number} {} ", group.map_or("全部", |g| GROUPS[g]));
        // All eight labels fit in 90 terminal cells, measured as cells, not bytes.
        let width = if group == Some(3) {
            12
        } else if group == Some(1) {
            10
        } else {
            8
        };
        let r = Rect::new(x, c[1].y, width.min(area.right().saturating_sub(x)), 1);
        f.render_widget(
            Paragraph::new(title).style(if group == app.group {
                ui::base().fg(BLUE).add_modifier(Modifier::UNDERLINED)
            } else {
                ui::base().fg(MUTED)
            }),
            r,
        );
        app.tabs.push((r, group));
        x = x.saturating_add(width);
    }
    if app.editing {
        app.query.render(f, c[2], ui::base().fg(BLUE));
    } else {
        f.render_widget(
            Paragraph::new(format!(" / 过滤 {}", app.query)).style(ui::base().fg(MUTED)),
            c[2],
        );
    }
    let columns = if c[3].width >= 138 {
        3
    } else if c[3].width >= 88 {
        2
    } else {
        1
    };
    let cols = Layout::horizontal(vec![Constraint::Ratio(1, columns as u32); columns])
        .spacing(1)
        .split(c[3]);
    let (positions, total) = positions(items, &visible, columns);
    app.total_rows = total;
    app.viewport = c[3].height.saturating_sub(2) as usize;
    if follow {
        if let Some((_, y, _, _)) = positions
            .iter()
            .find(|(_, _, _, s)| *s == Some(app.selected))
        {
            if *y < app.scroll {
                app.scroll = *y;
            }
            if y + 2 > app.scroll + app.viewport {
                app.scroll = (y + 2).saturating_sub(app.viewport);
            }
        }
    }
    app.scroll = app.scroll.min(total.saturating_sub(app.viewport));
    app.hits.clear();
    for (index, col) in cols.iter().enumerate() {
        let block = ui::block(if index == 0 { " 分组速查 " } else { " " }, false);
        let inner = block.inner(*col);
        f.render_widget(block, *col);
        for (column, y, group, selection) in positions
            .iter()
            .filter(|(column, _, _, _)| *column == index)
        {
            let _ = column;
            if *y + 2 <= app.scroll || *y >= app.scroll + inner.height as usize {
                continue;
            }
            let mut lines = if let Some(selection) = selection {
                let e = &items[visible[*selection]];
                let selected = app.selected == *selection;
                let style = ui::base().bg(if selected { SELECTION } else { BG });
                let color = if e.conflict { RED } else { BRIGHTFG };
                let chord = format!("{}{}", if e.conflict { "! " } else { "" }, e.chord);
                let matcher = Matcher::new(&app.query);
                let mut first =
                    matcher.highlight(&clip(&chord, inner.width.saturating_sub(1) as usize));
                first.spans.insert(0, ui::marker(selected));
                let mut second = matcher.highlight(&clip(
                    &format!("{} · {}", e.description, e.binding.mode),
                    inner.width.saturating_sub(1) as usize,
                ));
                second.spans.insert(0, Span::raw(" "));
                vec![
                    first.style(style.fg(color)),
                    second.style(style.fg(if e.conflict { RED } else { FG })),
                ]
            } else {
                vec![
                    Line::from(Span::styled(
                        format!(" {}", GROUPS[*group]),
                        ui::base().fg(BLUE).add_modifier(Modifier::BOLD),
                    )),
                    Line::default(),
                ]
            };
            let skip = app.scroll.saturating_sub(*y).min(2);
            lines.drain(..skip);
            let ry = inner.y + y.saturating_sub(app.scroll) as u16;
            let r = Rect::new(
                inner.x,
                ry,
                inner.width,
                (lines.len() as u16).min(inner.bottom().saturating_sub(ry)),
            );
            f.render_widget(
                Paragraph::new(lines).style(if *selection == Some(app.selected) {
                    ui::base().bg(SELECTION)
                } else {
                    ui::base()
                }),
                r,
            );
            if let Some(selection) = selection {
                app.hits.push((r, *selection));
            }
        }
    }
    if visible.is_empty() {
        f.render_widget(
            Paragraph::new("没有匹配。Esc 清除过滤；/ 修改搜索；0 查看全部分组。")
                .style(ui::base().fg(MUTED))
                .wrap(Wrap { trim: false }),
            c[3],
        );
    }
    let detail = visible
        .get(app.selected)
        .map(|i| {
            let e = &items[*i];
            format!(
                " {}  [{} · {}] {}\n {}",
                e.chord, e.binding.mode, e.binding.kind, e.description, e.binding.raw
            )
        })
        .unwrap_or_default();
    f.render_widget(
        Paragraph::new(detail)
            .style(ui::base().fg(MUTED))
            .wrap(Wrap { trim: false }),
        c[4],
    );
    ui::footer(
        f,
        c[5],
        " / 搜索  0–7 分组  j/k 移动  Enter 原文  q/Esc 关闭  ? 帮助",
        &format!(
            " 行 {}–{} / {} · 数据：生成的 Mango 配置",
            app.scroll + usize::from(total > 0),
            (app.scroll + app.viewport).min(total),
            total
        ),
    );
    if app.help {
        ui::help(f, &format!("0 全部 · 1 窗口 · 2 工作区 · 3 应用 · 4 TUI 工具\n5 截图 · 6 媒体 · 7 系统\n\n/ 按键名或中文说明模糊搜索（跨分组保留过滤）\nEnter 结束输入 · Ctrl+U 清到行首 · Backspace 删除\nj/k 或 ↑/↓ 选择 · PgUp/PgDn 翻页 · Home/End 首尾\n鼠标滚轮滚动 · 点击条目选择 · 点击顶部分组切页\nEnter 查看完整原始动作（↑/↓、滚轮可滚动）\n红色 ! = 同设备、重叠模式的相同组合\ncommon 在所有模式生效；resize 需先按 SUPER+R\n搜索输入时 ↑/↓ 选择；Esc 恢复编辑前过滤；列表 Esc 先清过滤再退出\n\n数据文件：{}", path.display()));
    } else if app.details {
        if let Some(i) = visible.get(app.selected) {
            let e = &items[*i];
            let a = ui::centered(area, 100, 20);
            f.render_widget(ratatui::widgets::Clear, a);
            f.render_widget(
                Paragraph::new(format!(
                    "{}\n{} · {} · {}\n\n{}\n\n原始 Mango 动作\n{}",
                    e.chord,
                    GROUPS[e.group],
                    e.binding.mode,
                    e.binding.kind,
                    e.description,
                    e.binding.raw
                ))
                .style(ui::base())
                .block(ui::block(" 原始动作 · ↑/↓ 滚动 · Enter/Esc 返回 ", true))
                .wrap(Wrap { trim: false })
                .scroll((app.detail_scroll, 0)),
                a,
            );
        }
    }
}

// Synchronize Kitty padding with the shared app background, then restore its
// configured default on every exit (including unwinding).
struct BackgroundGuard;
impl BackgroundGuard {
    fn new() -> std::io::Result<Self> {
        use std::io::Write;
        if let ratatui::style::Color::Rgb(r, g, b) = BG {
            write!(std::io::stdout(), "\x1b]11;#{r:02x}{g:02x}{b:02x}\x07")?;
            std::io::stdout().flush()?;
        }
        Ok(Self)
    }
}
impl Drop for BackgroundGuard {
    fn drop(&mut self) {
        use std::io::Write;
        let _ = write!(std::io::stdout(), "\x1b]111\x07");
        let _ = std::io::stdout().flush();
    }
}

fn run(items: Vec<Entry>, path: PathBuf) -> Result<()> {
    let _background = BackgroundGuard::new()?;
    let (mut terminal, _guard) = ui::terminal()?;
    let mut app = App::new(&items);
    let mut follow = true;
    loop {
        terminal.draw(|f| draw(f, &mut app, &items, &path, follow))?;
        follow = false;
        if !event::poll(Duration::from_millis(250))? {
            continue;
        }
        let count = app.visible(&items).len();
        match event::read()? {
            Event::Key(key) if key.kind != KeyEventKind::Release => {
                if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
                    break;
                }
                if app.help {
                    match key.code {
                        KeyCode::Esc | KeyCode::Char('?') => app.help = false,
                        KeyCode::Char('q') => break,
                        _ => {}
                    }
                } else if app.details {
                    match key.code {
                        KeyCode::Esc | KeyCode::Enter => app.details = false,
                        KeyCode::Char('q') => break,
                        KeyCode::Up => app.detail_scroll = app.detail_scroll.saturating_sub(1),
                        KeyCode::Down => app.detail_scroll = app.detail_scroll.saturating_add(1),
                        _ => {}
                    }
                } else if app.editing {
                    let selected = app.visible(&items).get(app.selected).copied();
                    match key.code {
                        KeyCode::Esc => {
                            app.query = app.previous_query.clone();
                            app.editing = false;
                            app.keep_selected(&items, selected);
                        }
                        KeyCode::Enter => app.editing = false,
                        KeyCode::Down => app.move_selection(1, count),
                        KeyCode::Up => app.move_selection(-1, count),
                        _ => {
                            if app.query.handle_key(key) {
                                app.keep_selected(&items, selected);
                            }
                        }
                    }
                    follow = true;
                } else if key.code == KeyCode::Esc {
                    if app.query.is_empty() {
                        break;
                    }
                    let selected = app.visible(&items).get(app.selected).copied();
                    app.query.clear();
                    app.keep_selected(&items, selected);
                    follow = true;
                } else {
                    if key
                        .modifiers
                        .intersects(KeyModifiers::CONTROL | KeyModifiers::ALT)
                    {
                        continue;
                    }
                    match key.code {
                        KeyCode::Char('q') => break,
                        KeyCode::Char('/') => {
                            app.previous_query = app.query.clone();
                            app.editing = true;
                        }
                        KeyCode::Char('?') => app.help = true,
                        KeyCode::Enter => {
                            app.details = true;
                            app.detail_scroll = 0;
                        }
                        KeyCode::Char('0'..='7') => {
                            if let KeyCode::Char(c) = key.code {
                                app.group = c
                                    .to_digit(10)
                                    .and_then(|n| n.checked_sub(1))
                                    .map(|n| n as usize);
                                app.reset();
                                follow = true;
                            }
                        }
                        KeyCode::Char('j') | KeyCode::Down => {
                            app.move_selection(1, count);
                            follow = true;
                        }
                        KeyCode::Char('k') | KeyCode::Up => {
                            app.move_selection(-1, count);
                            follow = true;
                        }
                        KeyCode::PageDown => {
                            app.scroll = app.scroll.saturating_add(app.viewport.saturating_sub(2))
                        }
                        KeyCode::PageUp => {
                            app.scroll = app.scroll.saturating_sub(app.viewport.saturating_sub(2))
                        }
                        KeyCode::Home | KeyCode::Char('g') => {
                            app.selected = 0;
                            follow = true;
                        }
                        KeyCode::End | KeyCode::Char('G') => {
                            app.selected = count.saturating_sub(1);
                            follow = true;
                        }
                        _ => {}
                    }
                }
            }
            Event::Mouse(mouse) if !app.help => {
                if app.details {
                    match mouse.kind {
                        MouseEventKind::ScrollDown => {
                            app.detail_scroll = app.detail_scroll.saturating_add(2)
                        }
                        MouseEventKind::ScrollUp => {
                            app.detail_scroll = app.detail_scroll.saturating_sub(2)
                        }
                        _ => {}
                    }
                } else {
                    match mouse.kind {
                        MouseEventKind::ScrollDown => app.scroll = app.scroll.saturating_add(3),
                        MouseEventKind::ScrollUp => app.scroll = app.scroll.saturating_sub(3),
                        MouseEventKind::Down(MouseButton::Left) => {
                            let pos = (mouse.column, mouse.row).into();
                            if let Some((_, group)) = app.tabs.iter().find(|(r, _)| r.contains(pos))
                            {
                                app.group = *group;
                                app.reset();
                                follow = true;
                            } else if let Some((_, selection)) =
                                app.hits.iter().find(|(r, _)| r.contains(pos))
                            {
                                app.selected = *selection;
                            }
                        }
                        _ => {}
                    }
                }
            }
            Event::Paste(text) if app.editing && !app.help && !app.details => {
                let selected = app.visible(&items).get(app.selected).copied();
                if app.query.paste(&text) {
                    app.keep_selected(&items, selected);
                }
                follow = true;
            }
            Event::Resize(_, _) => follow = true,
            _ => {}
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use ratatui::{backend::TestBackend, Terminal};

    fn sample() -> Vec<Entry> {
        entries(
            serde_json::from_value(serde_json::json!({"version":1,"bindings":[
                {"mode":"default","kind":"bind","raw":"SUPER+SHIFT,K,focusdir,up"},
                {"mode":"default","kind":"bind","raw":"SHIFT+SUPER,k,spawn,未知动作中文测试"},
                {"mode":"resize","kind":"bind","raw":"NONE,Escape,setkeymode,default"}
            ]}))
            .unwrap(),
        )
        .unwrap()
    }
    #[test]
    fn all_sizes_search_and_raw_detail_render() {
        let items = sample();
        for width in [35, 60, 90, 140] {
            let mut terminal = Terminal::new(TestBackend::new(width, 30)).unwrap();
            let mut app = App::new(&items);
            terminal
                .draw(|f| {
                    draw(
                        f,
                        &mut app,
                        &items,
                        std::path::Path::new("/generated/bindings.json"),
                        true,
                    )
                })
                .unwrap();
            let text = terminal
                .backend()
                .buffer()
                .content
                .iter()
                .map(|c| c.symbol())
                .collect::<String>();
            assert_eq!(terminal.backend().buffer()[(1, 0)].symbol(), "快");
            assert!(terminal
                .backend()
                .buffer()
                .content
                .iter()
                .any(|c| c.fg == RED));
            assert!(text.contains("Super"));
            app.details = true;
            terminal
                .draw(|f| {
                    draw(
                        f,
                        &mut app,
                        &items,
                        std::path::Path::new("/generated/bindings.json"),
                        true,
                    )
                })
                .unwrap();
            app.details = false;
            app.query = "没有任何匹配".into();
            terminal
                .draw(|f| {
                    draw(
                        f,
                        &mut app,
                        &items,
                        std::path::Path::new("/generated/bindings.json"),
                        true,
                    )
                })
                .unwrap();
            assert!(app.visible(&items).is_empty());
        }
    }
    #[test]
    fn filter_keeps_identity_and_reports_empty() {
        let items = sample();
        let mut app = App::new(&items);
        app.selected = 1;
        let keep = app.visible(&items).get(app.selected).copied();
        app.query = "zhongwen".into();
        app.keep_selected(&items, keep);
        assert_eq!(app.visible(&items).len(), 1);
        assert_eq!(app.visible(&items).get(app.selected).copied(), Some(1));
        app.query = "zzzzzzzzzz".into();
        app.keep_selected(&items, Some(1));
        assert_eq!(app.selected, 0);
        let mut terminal = Terminal::new(TestBackend::new(90, 30)).unwrap();
        terminal
            .draw(|f| draw(f, &mut app, &items, std::path::Path::new("fixture"), true))
            .unwrap();
        let text = terminal
            .backend()
            .buffer()
            .content
            .iter()
            .map(|c| c.symbol())
            .collect::<String>();
        assert!(text.replace(' ', "").contains("没有匹配"));
        assert!(text.contains("Esc"));
    }
    #[test]
    fn tiny_windows_render_without_panicking() {
        let items = sample();
        for width in [1, 2, 8, 20] {
            for height in [1, 2, 5] {
                let mut terminal = Terminal::new(TestBackend::new(width, height)).unwrap();
                let mut app = App::new(&items);
                app.editing = true;
                terminal
                    .draw(|f| draw(f, &mut app, &items, std::path::Path::new("fixture"), true))
                    .unwrap();
            }
        }
    }
    #[test]
    fn group_layout_covers_every_binding_once() {
        let items = sample();
        let visible = App::new(&items).visible(&items);
        for columns in 1..=3 {
            let (pos, _) = positions(&items, &visible, columns);
            let mut indices = pos
                .into_iter()
                .filter_map(|(_, _, _, s)| s)
                .collect::<Vec<_>>();
            indices.sort();
            assert_eq!(indices, (0..items.len()).collect::<Vec<_>>());
        }
    }
}
