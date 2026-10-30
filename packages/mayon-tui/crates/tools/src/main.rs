mod voice;

use crossterm::event::{
    Event, EventStream, KeyCode, KeyEventKind, KeyModifiers, MouseButton, MouseEventKind,
};
use futures_util::StreamExt;
use mayon_ui::{self as ui, theme::*};
use ratatui::{
    layout::{Rect, Size},
    style::Modifier,
    text::{Line, Span},
    widgets::Paragraph,
    Frame,
};
use std::{
    error::Error,
    time::{Duration, Instant},
};

type Result<T> = std::result::Result<T, Box<dyn Error>>;
const NAMES: [&str; 5] = ["docker", "ports", "serial", "keys", "voice"];
const LABELS: [&str; 5] = ["Docker", "Ports", "Serial", "Keys", "Voice"];
const FRAME_TIME: Duration = Duration::from_millis(70);

enum Screen {
    Docker(Box<dockertui_mayon::app::App>),
    Ports(Box<portstui_mayon::Screen>),
    Serial(Box<serial_mayon::app::App>),
    Keys(Box<keys_mayon::Screen>),
    Voice(Box<voice::Screen>),
    Error(String),
}
impl Screen {
    fn new(page: usize, args: &[String]) -> Self {
        let result: Result<Self> = (|| {
            Ok(match page {
                0 => Self::Docker(Box::new(
                    dockertui_mayon::app::App::new(dockertui_mayon::host(args)?)
                        .map_err(std::io::Error::other)?,
                )),
                1 => Self::Ports(Box::new(portstui_mayon::Screen::new(args))),
                2 => Self::Serial(Box::new(serial_mayon::open(args)?)),
                3 => Self::Keys(Box::new(keys_mayon::Screen::new(args)?)),
                _ => Self::Voice(Box::new(
                    voice::Screen::new().map_err(|e| std::io::Error::other(e.to_string()))?,
                )),
            })
        })();
        result.unwrap_or_else(|error| Self::Error(error.to_string()))
    }
    fn tick(&mut self) -> bool {
        match self {
            Self::Docker(app) => app.tick(),
            Self::Ports(app) => app.tick(),
            Self::Serial(app) => app.tick_changed(),
            Self::Voice(app) => {
                app.tick();
                false
            }
            _ => false,
        }
    }
    fn deadline(&self) -> Instant {
        match self {
            Self::Docker(app) => app.deadline(),
            Self::Ports(app) => app.deadline(),
            Self::Serial(app) => app.deadline(),
            Self::Voice(app) => app.deadline(),
            _ => Instant::now() + Duration::from_secs(3600),
        }
    }
    async fn changed(&mut self) -> bool {
        match self {
            Self::Docker(app) => {
                app.changed().await;
                true
            }
            Self::Ports(app) => {
                app.changed().await;
                true
            }
            Self::Serial(app) => {
                app.worker.notify.notified().await;
                true
            }
            Self::Voice(app) => app.changed().await,
            _ => std::future::pending().await,
        }
    }
    fn suspend(&mut self) {
        match self {
            Self::Docker(app) => app.suspend(),
            Self::Ports(app) => app.suspend(),
            Self::Serial(app) => app.suspend(),
            Self::Voice(app) => app.suspend(),
            _ => {}
        }
    }
    fn resume(&mut self) {
        match self {
            Self::Docker(app) => app.resume(),
            Self::Ports(app) => app.resume(),
            Self::Serial(app) => app.resume(),
            Self::Voice(app) => app.resume(),
            _ => {}
        }
    }
    fn editing(&self) -> bool {
        match self {
            Self::Docker(app) => app.editing(),
            Self::Ports(app) => app.editing(),
            Self::Serial(app) => app.input.is_some(),
            Self::Keys(app) => app.editing(),
            Self::Voice(app) => app.editing(),
            Self::Error(_) => false,
        }
    }
    fn draw(&mut self, f: &mut Frame, area: Rect) {
        match self {
            Self::Docker(app) => app.draw_in(f, area),
            Self::Ports(app) => app.draw(f, area),
            Self::Serial(app) => serial_mayon::tui::draw_in(f, app, area),
            Self::Keys(app) => app.draw(f, area),
            Self::Voice(app) => app.draw(f, area),
            Self::Error(error) => ui::list_state(
                f,
                area,
                ui::ListState::Error,
                &format!("{error}\nR 重试 · [ / ] 切换工具"),
            ),
        }
    }
    fn event(&mut self, event: Event, size: Size) -> bool {
        match self {
            Self::Docker(app) => {
                match local_event(event) {
                    Event::Key(key) if key.kind != KeyEventKind::Release => app.key(key),
                    Event::Paste(text) => app.paste(&text),
                    Event::Mouse(mouse) => app.mouse(mouse, local_size(size)),
                    _ => {}
                };
                app.quit
            }
            Self::Ports(app) => app.event(event, size),
            Self::Serial(app) => {
                serial_mayon::tui::event(app, local_event(event), local_size(size))
            }
            Self::Keys(app) => app.event(event),
            Self::Voice(app) => app.event(local_event(event)),
            Self::Error(_) => {
                matches!(event,Event::Key(key)if key.code==KeyCode::Char('q')||key.code==KeyCode::Esc)
            }
        }
    }
}
fn open_screen(screens: &mut [Option<Screen>], page: usize, args: &[String]) {
    if let Some(screen) = screens[page].as_mut() {
        screen.resume();
    } else {
        screens[page] = Some(Screen::new(page, args));
    }
}
fn local_size(size: Size) -> Size {
    Size::new(size.width, size.height.saturating_sub(1))
}
fn local_event(event: Event) -> Event {
    match event {
        Event::Mouse(mut mouse) => {
            mouse.row = mouse.row.saturating_sub(1);
            Event::Mouse(mouse)
        }
        other => other,
    }
}
fn tabs(f: &mut Frame, page: usize) {
    let area = f.area();
    let mut spans = vec![ui::muted(" 工具箱  ")];
    for (i, label) in LABELS.iter().enumerate() {
        spans.push(Span::styled(
            format!(" {label} "),
            if i == page {
                ui::base().fg(BLUE).add_modifier(Modifier::UNDERLINED)
            } else {
                ui::base().fg(MUTED)
            },
        ));
        spans.push(Span::raw(" "));
    }
    spans.push(ui::muted(" [ / ] 切换"));
    f.render_widget(
        Paragraph::new(Line::from(spans)).style(ui::base()),
        Rect::new(area.x, area.y, area.width, 1),
    );
}
fn tab_at(x: u16) -> Option<usize> {
    let mut left = 9;
    for (i, name) in LABELS.iter().enumerate() {
        let width = name.len() as u16 + 3;
        if (left..left + width).contains(&x) {
            return Some(i);
        }
        left += width;
    }
    None
}
fn top_switch(event: &Event, current: usize, editing: bool) -> Option<usize> {
    match event {
        Event::Key(key)
            if key.kind != KeyEventKind::Release
                && !editing
                && !key
                    .modifiers
                    .intersects(KeyModifiers::CONTROL | KeyModifiers::ALT) =>
        {
            match key.code {
                KeyCode::Char('[') => Some((current + 4) % 5),
                KeyCode::Char(']') => Some((current + 1) % 5),
                _ => None,
            }
        }
        Event::Mouse(mouse)
            if mouse.row == 0 && matches!(mouse.kind, MouseEventKind::Down(MouseButton::Left)) =>
        {
            tab_at(mouse.column)
        }
        _ => None,
    }
}
async fn command(page: usize, args: &[String]) -> Result<bool> {
    Ok(match page {
        0 => dockertui_mayon::command(args.to_vec()).await?,
        1 => portstui_mayon::command(args),
        2 => serial_mayon::command(args)?,
        3 => keys_mayon::command(args.to_vec())?,
        _ => {
            if !args.is_empty() {
                return Err(
                    "mayon-tools voice 没有非交互子命令；录音命令仍由 mayon-voice 提供".into(),
                );
            }
            false
        }
    })
}
#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    let mut args: Vec<String> = std::env::args().skip(1).collect();
    if args.first().is_some_and(|s| s == "--help" || s == "-h") {
        println!("mayon-tools [docker|ports|serial|keys|voice] [参数]\n\n默认打开 Ports；[ / ] 切换工具，内部数字键保留。\nmayon-tools docker df|clean ...\nmayon-tools ports --help\nmayon-tools serial list|<端口> [-b 波特率]\nmayon-tools keys list [--json]");
        return Ok(());
    }
    if args.first().is_some_and(|s| s == "--version") {
        println!("mayon-tools {}", env!("CARGO_PKG_VERSION"));
        return Ok(());
    }
    let mut page = 1;
    if !args.is_empty() {
        page = NAMES
            .iter()
            .position(|name| *name == args[0])
            .ok_or("未知工具；请运行 mayon-tools --help")?;
        args.remove(0);
    }
    if command(page, &args).await? {
        return Ok(());
    }
    let mut page_args: Vec<Vec<String>> = (0..5).map(|_| Vec::new()).collect();
    page_args[page] = args;
    let mut screens: Vec<Option<Screen>> = (0..5).map(|_| None).collect();
    open_screen(&mut screens, page, &page_args[page]);
    let (mut terminal, _guard) = ui::terminal()?;
    let mut events = EventStream::new();
    let mut focused = true;
    let mut dirty = true;
    let mut last_draw = Instant::now() - FRAME_TIME;
    loop {
        let screen = screens[page].as_mut().unwrap();
        if focused {
            dirty |= screen.tick();
        }
        if focused && dirty && last_draw.elapsed() >= FRAME_TIME {
            terminal.draw(|f| {
                let all = f.area();
                f.render_widget(ratatui::widgets::Block::default().style(ui::base()), all);
                let body = Rect::new(
                    all.x,
                    all.y.saturating_add(1),
                    all.width,
                    all.height.saturating_sub(1),
                );
                screen.draw(f, body);
                tabs(f, page);
            })?;
            dirty = false;
            last_draw = Instant::now();
        }
        let deadline = if dirty {
            screen.deadline().min(last_draw + FRAME_TIME)
        } else {
            screen.deadline()
        };
        enum Wake {
            Event(Event),
            Data(bool),
            Timer,
        }
        let wake = tokio::select! {
            event=events.next()=>match event{Some(Ok(event))=>Wake::Event(event),Some(Err(error))=>return Err(error.into()),None=>break},
            changed=screen.changed(),if focused=>Wake::Data(changed),
            _=tokio::time::sleep_until(deadline.into()),if focused=>Wake::Timer,
        };
        match wake {
            Wake::Data(changed) => {
                dirty |= changed;
            }
            Wake::Timer => {}
            Wake::Event(event) => {
                if matches!(event,Event::Key(key)if key.kind==KeyEventKind::Release)
                    || matches!(event,Event::Mouse(mouse)if matches!(mouse.kind,MouseEventKind::Moved))
                {
                    continue;
                }
                if matches!(event, Event::FocusLost) {
                    if focused {
                        screen.suspend();
                        focused = false;
                    }
                    continue;
                }
                if matches!(event, Event::FocusGained) {
                    if !focused {
                        focused = true;
                        screen.resume();
                        dirty = true;
                    }
                    continue;
                }
                if let Some(next) = top_switch(&event, page, screen.editing()) {
                    if next != page {
                        screen.suspend();
                        page = next;
                        open_screen(&mut screens, page, &page_args[page]);
                        dirty = true;
                    }
                    continue;
                }
                if matches!(event,Event::Key(key)if key.kind!=KeyEventKind::Release&&key.code==KeyCode::Char('R'))
                    && matches!(screen, Screen::Error(_))
                {
                    screens[page] = None;
                    open_screen(&mut screens, page, &page_args[page]);
                    dirty = true;
                    continue;
                }
                if matches!(event,Event::Key(key)if key.code==KeyCode::Char('c')&&key.modifiers.contains(KeyModifiers::CONTROL))
                {
                    break;
                }
                if screen.event(event, terminal.size()?) {
                    break;
                }
                dirty = true;
            }
        }
    }
    for screen in screens.iter_mut().flatten() {
        screen.suspend();
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    async fn opening_ports_leaves_unvisited_tools_uninitialized() {
        let mut screens: Vec<Option<Screen>> = (0..5).map(|_| None).collect();
        open_screen(&mut screens, 1, &[]);
        assert!(matches!(screens[1], Some(Screen::Ports(_))));
        for page in [0, 2, 3, 4] {
            assert!(screens[page].is_none());
        }
        screens[1].as_mut().unwrap().suspend();
        if let Some(Screen::Ports(screen)) = &mut screens[1] {
            assert!(!screen.editing());
        }
    }
    #[test]
    fn top_tabs_preserve_page_numbers_and_editor_brackets() {
        let key = |c| {
            Event::Key(crossterm::event::KeyEvent::new(
                KeyCode::Char(c),
                KeyModifiers::NONE,
            ))
        };
        assert_eq!(top_switch(&key(']'), 1, false), Some(2));
        assert_eq!(top_switch(&key('['), 0, false), Some(4));
        assert_eq!(top_switch(&key('1'), 1, false), None);
        assert_eq!(top_switch(&key(']'), 1, true), None);
    }
}
