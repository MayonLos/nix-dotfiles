mod api;
mod app;
mod lifecycle;
mod profiles;
mod theme;
mod ui;

use app::{App, Options};
use crossterm::event::{self, Event, KeyEventKind};
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
        lifecycle: lifecycle::Lifecycle::default(),
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
            "--test-verge-executable" => {
                opts.lifecycle.test_executable =
                    Some(args.next().ok_or("test executable required")?.into())
            }
            "--test-launcher" => {
                opts.lifecycle.test_launcher =
                    Some(args.next().ok_or("test launcher required")?.into())
            }
            "--help" | "-h" => {
                println!(concat!(
                    "clashtui-mayon ",
                    env!("CARGO_PKG_VERSION"),
                    "\n\n--socket PATH       Mihomo Unix socket (never TCP controller)\n--profiles PATH     Read-only Verge profiles.yaml\n--test-url URL      Delay probe target\n--usage-proxy URL   Explicit HTTP/SOCKS proxy for usage headers\n--no-verge          Disable all external Verge launches (isolated tests)\n\n1 proxies · 2 subscriptions · 3 connections · s start · X stop (confirm) · ? help\n--test-verge-executable PATH + --test-launcher PATH (paired isolated fixtures)"
                ));
                return Ok(None);
            }
            "--version" => {
                println!("clashtui-mayon {}", env!("CARGO_PKG_VERSION"));
                return Ok(None);
            }
            _ => return Err("unknown argument; use --help"),
        }
    }
    if opts.lifecycle.test_executable.is_some() != opts.lifecycle.test_launcher.is_some() {
        return Err("isolated lifecycle requires both --test-verge-executable and --test-launcher");
    }
    if opts
        .lifecycle
        .test_executable
        .iter()
        .chain(opts.lifecycle.test_launcher.iter())
        .any(|p| !p.is_absolute())
    {
        return Err("test lifecycle paths must be absolute");
    }
    if opts.socket.as_os_str().is_empty() {
        return Err("XDG_RUNTIME_DIR or --socket is required");
    }
    Ok(Some(opts))
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let Some(opts) = options().map_err(io::Error::other)? else {
        return Ok(());
    };
    let mut app = App::new(opts)?;
    let (mut terminal, _guard) = mayon_ui::terminal()?;
    app.start();
    while !app.quit {
        app.tick();
        terminal.draw(|frame| ui::draw(frame, &mut app))?;
        if event::poll(Duration::from_millis(50))? {
            match event::read()? {
                Event::Key(key) if key.kind != KeyEventKind::Release => app.key(key),
                Event::Mouse(mouse) => app.mouse(mouse, terminal.size()?),
                _ => {}
            }
        }
        tokio::task::yield_now().await;
    }
    app.stop();
    Ok(())
}
