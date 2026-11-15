//! `mayon-overlay` entry point.
//!
//! Modes:
//!
//! * `mayon-overlay clipboard` — cliphist history overlay (Super+V)
//! * `mayon-overlay launcher`  — text-only application launcher (Super+A)
//! * `mayon-overlay ctl <command>` — talk to a running overlay over its Unix
//!   socket (used by scripts and the headless test; see `ipc.rs`).
//!
//! The two wrappers installed by the Nix package (`mayon-clipboard`,
//! `mayon-launcher`) are this binary with the mode argument already supplied.

mod canvas;
mod cliphist;
mod desktop;
mod fonts;
mod ipc;
mod logger;
mod overlay;
mod palette;
mod paste;
mod wayland;

use crate::fonts::Fonts;
use crate::ipc::IpcServer;
use crate::logger::{json_string, Logger};
use crate::overlay::{ExitAction, Mode, Overlay};
use crate::wayland::WaylandHost;
use std::path::PathBuf;
use std::process::ExitCode;

const HELP: &str = "\
mayon-overlay — One Dark clipboard history and text application launcher

USAGE:
    mayon-overlay clipboard [OPTIONS]   clipboard history overlay
    mayon-overlay launcher  [OPTIONS]   text-only application launcher
    mayon-overlay ctl [--socket PATH] <command...>

OVERLAY OPTIONS:
    --socket PATH          control socket (default: $XDG_RUNTIME_DIR/mayon-overlay-<mode>.sock)
    --log PATH             JSON-lines event log (default: $XDG_RUNTIME_DIR/mayon-overlay.log)
    --ready-file PATH      write the first-frame geometry here (tests/automation)
    --font PATH            UI font file (default: fc-match Inter)
    --font-fallback PATH   CJK fallback font file (default: fc-match Noto Sans CJK SC)
    --query TEXT           initial search query
    --data-dir PATH        extra XDG data directory for launcher entries (repeatable)
    --scale N              force an integer buffer scale instead of the output value
    --paste-keys CHORD     chord injected after copying (default ctrl+v; 'none' disables)
    --no-paste             copy only, never inject the paste chord

CTL COMMANDS:
    state, ping, query <text>, select <index>, activate [index],
    click <x> <y>, close, toggle, reload

ENVIRONMENT:
    MAYON_OVERLAY_SOCKET, MAYON_OVERLAY_LOG, MAYON_OVERLAY_FONT,
    MAYON_OVERLAY_FONT_FALLBACK, MAYON_OVERLAY_PASTE_KEYS, MAYON_OVERLAY_SCALE,
    MAYON_OVERLAY_DATA_DIRS (colon separated)
";

#[derive(Debug)]
struct Args {
    command: Command,
    socket: Option<PathBuf>,
    log: Option<PathBuf>,
    ready_file: Option<PathBuf>,
    font: Option<String>,
    font_fallback: Option<String>,
    query: Option<String>,
    data_dirs: Vec<PathBuf>,
    scale: Option<i32>,
    paste_keys: Option<String>,
    no_paste: bool,
    ctl_request: String,
}

#[derive(Debug, PartialEq, Eq)]
enum Command {
    Clipboard,
    Launcher,
    Ctl,
    Help,
}

fn main() -> ExitCode {
    let argv: Vec<String> = std::env::args().skip(1).collect();
    let args = match parse_args(&argv) {
        Ok(args) => args,
        Err(error) => {
            eprintln!("mayon-overlay: {}", error);
            eprintln!("{}", HELP);
            return ExitCode::from(2);
        }
    };
    match args.command {
        Command::Help => {
            print!("{}", HELP);
            ExitCode::SUCCESS
        }
        Command::Ctl => run_ctl(&args),
        Command::Clipboard | Command::Launcher => run_overlay(&args),
    }
}

fn parse_args(argv: &[String]) -> Result<Args, String> {
    if argv.is_empty() || argv.iter().any(|arg| arg == "--help" || arg == "-h") {
        return Ok(Args {
            command: Command::Help,
            socket: None,
            log: None,
            ready_file: None,
            font: None,
            font_fallback: None,
            query: None,
            data_dirs: Vec::new(),
            scale: None,
            paste_keys: None,
            no_paste: false,
            ctl_request: String::new(),
        });
    }
    let command = match argv[0].as_str() {
        "clipboard" => Command::Clipboard,
        "launcher" => Command::Launcher,
        "ctl" => Command::Ctl,
        other => return Err(format!("unknown subcommand '{}'", other)),
    };
    let mut args = Args {
        command,
        socket: std::env::var_os("MAYON_OVERLAY_SOCKET").map(PathBuf::from),
        log: std::env::var_os("MAYON_OVERLAY_LOG").map(PathBuf::from),
        ready_file: None,
        font: std::env::var("MAYON_OVERLAY_FONT").ok(),
        font_fallback: std::env::var("MAYON_OVERLAY_FONT_FALLBACK").ok(),
        query: None,
        data_dirs: std::env::var("MAYON_OVERLAY_DATA_DIRS")
            .map(|dirs| {
                dirs.split(':')
                    .filter(|dir| !dir.is_empty())
                    .map(PathBuf::from)
                    .collect()
            })
            .unwrap_or_default(),
        scale: std::env::var("MAYON_OVERLAY_SCALE")
            .ok()
            .and_then(|value| value.parse().ok()),
        paste_keys: std::env::var("MAYON_OVERLAY_PASTE_KEYS").ok(),
        no_paste: false,
        ctl_request: String::new(),
    };
    let mut index = 1;
    let mut ctl_parts: Vec<String> = Vec::new();
    while index < argv.len() {
        let argument = &argv[index];
        if args.command == Command::Ctl && !argument.starts_with("--") {
            ctl_parts.push(argument.clone());
            index += 1;
            continue;
        }
        let mut take_value = |name: &str| -> Result<String, String> {
            index += 1;
            argv.get(index)
                .cloned()
                .ok_or_else(|| format!("{} requires a value", name))
        };
        match argument.as_str() {
            "--socket" => args.socket = Some(PathBuf::from(take_value("--socket")?)),
            "--log" => args.log = Some(PathBuf::from(take_value("--log")?)),
            "--ready-file" => args.ready_file = Some(PathBuf::from(take_value("--ready-file")?)),
            "--font" => args.font = Some(take_value("--font")?),
            "--font-fallback" => args.font_fallback = Some(take_value("--font-fallback")?),
            "--query" => args.query = Some(take_value("--query")?),
            "--data-dir" => args
                .data_dirs
                .push(PathBuf::from(take_value("--data-dir")?)),
            "--scale" => {
                args.scale = Some(
                    take_value("--scale")?
                        .parse()
                        .map_err(|_| "--scale requires an integer".to_string())?,
                )
            }
            "--paste-keys" => args.paste_keys = Some(take_value("--paste-keys")?),
            "--no-paste" => args.no_paste = true,
            other => return Err(format!("unknown option '{}'", other)),
        }
        index += 1;
    }
    if args.command == Command::Ctl {
        args.ctl_request = ctl_parts.join(" ");
        if args.ctl_request.is_empty() {
            return Err("ctl requires a command (state, activate, ...)".to_string());
        }
    }
    Ok(args)
}

fn mode_socket(args: &Args, mode: Mode) -> PathBuf {
    args.socket
        .clone()
        .unwrap_or_else(|| mode.default_socket_path())
}

fn default_log_path() -> PathBuf {
    std::env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"))
        .join("mayon-overlay.log")
}

fn run_ctl(args: &Args) -> ExitCode {
    let explicit = args.socket.clone();
    let request = args.ctl_request.clone();
    let sockets: Vec<PathBuf> = match explicit {
        Some(socket) => vec![socket],
        None => vec![
            Mode::Clipboard.default_socket_path(),
            Mode::Launcher.default_socket_path(),
        ],
    };
    let mut last_error = String::new();
    for socket in sockets {
        match ipc::client_request(&socket, &request) {
            Ok(reply) => {
                println!("{}", reply);
                if reply.starts_with("{\"ok\":true") || reply.starts_with("{\"ok\": true") {
                    return ExitCode::SUCCESS;
                }
                return ExitCode::from(1);
            }
            Err(error) => last_error = error,
        }
    }
    eprintln!("mayon-overlay: {}", last_error);
    ExitCode::from(1)
}

fn run_overlay(args: &Args) -> ExitCode {
    let mode = match args.command {
        Command::Clipboard => Mode::Clipboard,
        Command::Launcher => Mode::Launcher,
        _ => unreachable!(),
    };
    let socket = mode_socket(args, mode);
    // A second invocation of the same key binding toggles the running overlay.
    if ipc::toggle_if_running(&socket) {
        return ExitCode::SUCCESS;
    }
    let log_path = args.log.clone().unwrap_or_else(default_log_path);
    let logger = Logger::open(Some(&log_path));
    logger.event(
        "boot",
        &[
            ("mode", json_string(mode.name())),
            ("socket", json_string(&socket.to_string_lossy())),
            ("log", json_string(&log_path.to_string_lossy())),
        ],
    );
    let fonts = match Fonts::load(args.font.as_deref(), args.font_fallback.as_deref()) {
        Ok(fonts) => fonts,
        Err(error) => {
            logger.event("font_error", &[("error", json_string(&error))]);
            eprintln!("mayon-overlay: {}", error);
            return ExitCode::from(2);
        }
    };
    logger.event(
        "fonts",
        &[
            ("primary", json_string(&fonts.primary_path)),
            (
                "fallback",
                match &fonts.fallback_path {
                    Some(path) => json_string(path),
                    None => "null".to_string(),
                },
            ),
        ],
    );
    let mut overlay = match mode {
        Mode::Clipboard => Overlay::new_clipboard(fonts, logger.clone()),
        Mode::Launcher => Overlay::new_launcher(fonts, logger.clone(), args.data_dirs.clone()),
    };
    if let Some(query) = &args.query {
        overlay.set_query(query.clone());
    }
    let ipc = match IpcServer::bind(&socket) {
        Ok(server) => server,
        Err(error) => {
            eprintln!("mayon-overlay: {}", error);
            return ExitCode::from(2);
        }
    };
    let mut host = WaylandHost::new(
        overlay,
        logger.clone(),
        Some(ipc),
        args.ready_file.clone(),
        socket.clone(),
    );
    if let Some(scale) = args.scale {
        host.force_scale(scale);
    }
    let exit = match host.run() {
        Ok(exit) => exit,
        Err(error) => {
            logger.event("fatal", &[("error", json_string(&error))]);
            eprintln!("mayon-overlay: {}", error);
            return ExitCode::from(1);
        }
    };
    match exit {
        Some(ExitAction::ClipboardCopied {
            is_image,
            bytes,
            preview,
        }) => {
            eprintln!(
                "mayon-overlay: copied {} ({} bytes)",
                if is_image { "image" } else { "text" },
                bytes
            );
            let chord = args
                .paste_keys
                .clone()
                .unwrap_or_else(|| "ctrl+v".to_string());
            if args.no_paste {
                logger.event("paste_skipped", &[("reason", json_string("--no-paste"))]);
            } else {
                let outcome = paste::inject(&chord, &logger);
                logger.event(
                    "paste",
                    &[
                        ("injected", outcome.injected.to_string()),
                        ("command", json_string(&outcome.command)),
                        (
                            "reason",
                            match &outcome.reason {
                                Some(reason) => json_string(reason),
                                None => "null".to_string(),
                            },
                        ),
                    ],
                );
                if !outcome.injected {
                    let reason = outcome
                        .reason
                        .clone()
                        .unwrap_or_else(|| "unknown".to_string());
                    eprintln!(
                        "mayon-overlay: copied to clipboard; automatic paste unavailable: {}",
                        reason
                    );
                    let short_preview: String = preview.chars().take(60).collect();
                    paste::notify_copy(
                        "已复制到剪贴板",
                        &format!("自动粘贴不可用：{}\n{}", reason, short_preview),
                        &logger,
                    );
                }
            }
        }
        Some(ExitAction::Launched {
            name,
            desktop_path,
            result,
        }) => match result {
            Ok(()) => eprintln!("mayon-overlay: launched {} ({})", name, desktop_path),
            Err(error) => {
                logger.event(
                    "launch_error",
                    &[("name", json_string(&name)), ("error", json_string(&error))],
                );
                eprintln!("mayon-overlay: launch failed: {}", error);
                return ExitCode::from(1);
            }
        },
        Some(ExitAction::Closed { reason }) => {
            eprintln!("mayon-overlay: closed ({})", reason);
        }
        None => {}
    }
    ExitCode::SUCCESS
}
