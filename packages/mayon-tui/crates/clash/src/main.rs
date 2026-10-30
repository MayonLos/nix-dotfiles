mod api;
mod app;
mod cli;
mod native;
mod profiles;
mod search;
mod settings;
mod theme;
mod ui;

use app::{App, Options};
use crossterm::event::{self, Event, KeyEventKind};
use std::{env, io, path::PathBuf, time::Duration};

fn options() -> Result<Option<Options>, &'static str> {
    let home = env::var_os("HOME").map(PathBuf::from).unwrap_or_default();
    let config_home = env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home.join(".config"));
    let raw: Vec<String> = env::args().skip(1).collect();
    let config_path = raw
        .windows(2)
        .find(|args| args[0] == "--config")
        .map(|args| PathBuf::from(&args[1]))
        .unwrap_or_else(|| config_home.join("mayon-tui/clash.toml"));
    let settings = if raw
        .iter()
        .any(|a| matches!(a.as_str(), "--help" | "-h" | "--version"))
    {
        settings::Settings::default()
    } else {
        settings::Settings::load(&config_path)?
    };
    let mut opts = Options {
        socket: PathBuf::from("/run/mayon-clash/mihomo.sock"),
        settings,
        usage_proxy: None,
        native: native::Native {
            data: home.join(".local/share/mayon-clash"),
            socket: "/run/mayon-clash/mihomo.sock".into(),
            mihomo: "mihomo".into(),
            systemctl: "systemctl".into(),
        },
    };
    let mut args = raw.into_iter();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--data-dir" => opts.native.data = args.next().ok_or("需要数据目录")?.into(),
            "--mihomo" => opts.native.mihomo = args.next().ok_or("需要 mihomo 路径")?.into(),
            "--systemctl" => {
                opts.native.systemctl = args.next().ok_or("需要 systemctl 路径")?.into()
            }
            "--socket" => opts.socket = args.next().ok_or("--socket 需要路径")?.into(),
            "--test-url" => opts.settings.test_url = args.next().ok_or("--test-url 需要 URL")?,
            "--config" => {
                args.next().ok_or("--config 需要路径")?;
            }
            "--usage-proxy" => {
                opts.usage_proxy = Some(args.next().ok_or("--usage-proxy 需要 URL")?)
            }
            "--help" | "-h" => {
                println!(concat!(
                    "clashtui-mayon ",
                    env!("CARGO_PKG_VERSION"),
                    "\n\n--data-dir PATH     Native private data directory\n--mihomo PATH       Validator executable (isolated fixtures)\n--systemctl PATH    Service command (isolated fixtures)\nprofile add|update|use|rename|url|delete|list (see README)\nsettings KEY VALUE · service start|stop\n--socket PATH       Mihomo Unix socket (never TCP controller)\n--test-url URL      Delay probe target\n--config PATH       Read optional preferences\n--usage-proxy URL   Explicit HTTP/SOCKS proxy for usage headers\n\n1 概览 · 2 代理 · 3 订阅 · 4 连接 · 5 规则 · 6 日志 · 7 工具 · s 启动 · X 关闭（确认） · ? 帮助"
                ));
                return Ok(None);
            }
            "--version" => {
                println!("clashtui-mayon {}", env!("CARGO_PKG_VERSION"));
                return Ok(None);
            }
            _ => return Err("未知参数，请用 --help 查看"),
        }
    }
    opts.native.socket = opts.socket.clone();
    opts.settings.validate()?;
    Ok(Some(opts))
}

#[tokio::main(worker_threads = 2)]
async fn main() {
    if let Err(message) = run().await {
        eprintln!("Clash TUI：{message}");
        std::process::exit(1);
    }
}
async fn run() -> Result<(), Box<dyn std::error::Error>> {
    if cli::run().await.map_err(io::Error::other)? {
        return Ok(());
    }
    let Some(opts) = options().map_err(io::Error::other)? else {
        return Ok(());
    };
    let mut app = App::new(opts).map_err(|_| io::Error::other("无法创建内核客户端"))?;
    let (mut terminal, _guard) = mayon_ui::terminal()?;
    crossterm::execute!(io::stdout(), crossterm::event::EnableBracketedPaste)?;
    app.start();
    while !app.quit {
        app.tick();
        if app.dirty {
            terminal.draw(|frame| ui::draw(frame, &app))?;
            app.dirty = false;
        }
        if event::poll(Duration::from_millis(50))? {
            match event::read()? {
                Event::Key(key) if key.kind != KeyEventKind::Release => app.key(key),
                Event::Paste(value) => app.paste(&value),
                Event::Mouse(mouse) => app.mouse(mouse, terminal.size()?),
                Event::Resize(_, _) => app.dirty = true,
                _ => {}
            }
        }
        tokio::task::yield_now().await;
    }
    app.finish_native().await;
    app.stop();
    Ok(())
}
