mod api;
mod app;
mod profiles;
mod theme;
mod ui;

use app::{App, Options};
use crossterm::{
    event::{self, Event, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use std::{env, io, path::PathBuf, time::Duration};

fn options() -> Result<Option<Options>, &'static str> {
    let home = env::var_os("HOME").map(PathBuf::from).unwrap_or_default();
    let runtime = env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from);
    let mut opts = Options {
        socket: runtime
            .map(|path| path.join("clash-verge-rev/verge-mihomo.sock"))
            .unwrap_or_default(),
        profiles: home.join(".local/share/io.github.clash-verge-rev.clash-verge-rev/profiles.yaml"),
        test_url: "https://www.gstatic.com/generate_204".into(),
        usage_proxy: None,
        no_verge: false,
    };
    let mut args = env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--socket" => opts.socket = args.next().ok_or("--socket needs a path")?.into(),
            "--profiles" => opts.profiles = args.next().ok_or("--profiles needs a path")?.into(),
            "--test-url" => opts.test_url = args.next().ok_or("--test-url needs a URL")?,
            "--usage-proxy" => {
                opts.usage_proxy = Some(args.next().ok_or("--usage-proxy needs a URL")?)
            }
            "--no-verge" => opts.no_verge = true,
            "--help" | "-h" => {
                println!("clashtui-mayon 0.1.0\n\n--socket PATH       Mihomo Unix socket (never TCP controller)\n--profiles PATH     Read-only Verge profiles.yaml\n--test-url URL      Delay probe target\n--usage-proxy URL   Explicit HTTP/SOCKS proxy for usage headers\n--no-verge          Disable all external Verge launches (isolated tests)\n\n1 proxies · 2 subscriptions · 3 connections · ? help");
                return Ok(None);
            }
            "--version" => {
                println!("clashtui-mayon 0.1.0");
                return Ok(None);
            }
            _ => return Err("unknown argument; use --help"),
        }
    }
    if opts.socket.as_os_str().is_empty() {
        return Err("XDG_RUNTIME_DIR or --socket is required");
    }
    Ok(Some(opts))
}

// Drop guard also runs on early I/O failure; panic hook restores the terminal.
struct TerminalGuard;
impl Drop for TerminalGuard {
    fn drop(&mut self) {
        let _ = disable_raw_mode();
        let _ = execute!(io::stdout(), LeaveAlternateScreen);
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let Some(opts) = options().map_err(io::Error::other)? else {
        return Ok(());
    };
    let mut app = App::new(opts)?;
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        let _ = disable_raw_mode();
        let _ = execute!(io::stdout(), LeaveAlternateScreen);
        previous(info);
    }));
    enable_raw_mode()?;
    let _guard = TerminalGuard;
    execute!(io::stdout(), EnterAlternateScreen)?;
    let mut terminal =
        ratatui::Terminal::new(ratatui::backend::CrosstermBackend::new(io::stdout()))?;
    app.start();
    while !app.quit {
        app.tick();
        terminal.draw(|frame| ui::draw(frame, &mut app))?;
        if event::poll(Duration::from_millis(50))? {
            if let Event::Key(key) = event::read()? {
                if key.kind != KeyEventKind::Release {
                    app.key(key);
                }
            }
        }
        tokio::task::yield_now().await;
    }
    app.stop();
    Ok(())
}
