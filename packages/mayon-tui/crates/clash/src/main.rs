mod api;
mod app;
mod backend;
mod cli;
mod lifecycle;
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
    let runtime = env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from);
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
        socket: runtime
            .map(|path| path.join("clash-verge-rev/verge-mihomo.sock"))
            .unwrap_or_default(),
        profiles: home.join(".local/share/io.github.clash-verge-rev.clash-verge-rev/profiles.yaml"),
        settings,
        usage_proxy: None,
        no_verge: false,
        lifecycle: lifecycle::Lifecycle::default(),
        backend: backend::Backend::Native,
        native: native::Native {
            data: home.join(".local/share/mayon-clash"),
            socket: "/run/mayon-clash/mihomo.sock".into(),
            verge_profiles: home
                .join(".local/share/io.github.clash-verge-rev.clash-verge-rev/profiles.yaml"),
            mihomo: "mihomo".into(),
            systemctl: "systemctl".into(),
            yq: "yq".into(),
        },
    };
    let explicit_socket = raw.iter().any(|a| a == "--socket");
    let mut args = raw.into_iter();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--backend" => {
                opts.settings.backend = match args.next().as_deref() {
                    Some("auto") => backend::Preference::Auto,
                    Some("native") => backend::Preference::Native,
                    Some("verge") => backend::Preference::Verge,
                    _ => return Err("后端须为 auto/native/verge"),
                }
            }
            "--data-dir" => opts.native.data = args.next().ok_or("需要数据目录")?.into(),
            "--mihomo" => opts.native.mihomo = args.next().ok_or("需要 mihomo 路径")?.into(),
            "--systemctl" => {
                opts.native.systemctl = args.next().ok_or("需要 systemctl 路径")?.into()
            }
            "--socket" => opts.socket = args.next().ok_or("--socket 需要路径")?.into(),
            "--profiles" => opts.profiles = args.next().ok_or("--profiles 需要路径")?.into(),
            "--test-url" => opts.settings.test_url = args.next().ok_or("--test-url 需要 URL")?,
            "--config" => {
                args.next().ok_or("--config 需要路径")?;
            }
            "--usage-proxy" => {
                opts.usage_proxy = Some(args.next().ok_or("--usage-proxy 需要 URL")?)
            }
            "--no-verge" => opts.no_verge = true,
            "--test-verge-executable" => {
                opts.lifecycle.test_executable =
                    Some(args.next().ok_or("需要替身可执行文件")?.into())
            }
            "--test-launcher" => {
                opts.lifecycle.test_launcher = Some(args.next().ok_or("需要替身启动器")?.into())
            }
            "--help" | "-h" => {
                println!(concat!(
                    "clashtui-mayon ",
                    env!("CARGO_PKG_VERSION"),
                    "\n\n--backend auto|native|verge\n--data-dir PATH     Native private data directory\n--mihomo PATH       Validator executable (isolated fixtures)\n--systemctl PATH    Service command (isolated fixtures)\nprofile add|update|use|rename|url|delete|import-verge|list (see README)\nsettings KEY VALUE · service start|stop\n--socket PATH       Mihomo Unix socket (never TCP controller)\n--profiles PATH     Read-only Verge profiles.yaml\n--test-url URL      Delay probe target\n--config PATH       Read optional preferences\n--usage-proxy URL   Explicit HTTP/SOCKS proxy for usage headers\n--no-verge          Disable all external Verge launches (isolated tests)\n\n1 概览 · 2 代理 · 3 订阅 · 4 连接 · 5 规则 · 6 日志 · 7 工具 · s 启动 · X 关闭（确认） · ? 帮助\n--test-verge-executable PATH + --test-launcher PATH (paired isolated fixtures)"
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
    if opts.lifecycle.test_executable.is_some() != opts.lifecycle.test_launcher.is_some() {
        return Err("隔离生命周期参数必须成对提供");
    }
    if opts
        .lifecycle
        .test_executable
        .iter()
        .chain(opts.lifecycle.test_launcher.iter())
        .any(|p| !p.is_absolute())
    {
        return Err("替身路径必须是绝对路径");
    }
    opts.backend = backend::Backend::detect(opts.settings.backend, &opts.socket);
    opts.native.verge_profiles = opts.profiles.clone();
    if opts.backend == backend::Backend::Native {
        if explicit_socket {
            opts.native.socket = opts.socket.clone();
        } else {
            opts.socket = opts.native.socket.clone();
        }
    }
    if opts.socket.as_os_str().is_empty() {
        return Err("需要 XDG_RUNTIME_DIR 或 --socket");
    }
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
