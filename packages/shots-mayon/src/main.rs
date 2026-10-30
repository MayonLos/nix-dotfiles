mod actions;
mod library;
mod record;
mod tui;

use anyhow::Result;
use clap::{Parser, Subcommand};
use library::Library;
use std::{
    fs::OpenOptions,
    os::unix::{fs::OpenOptionsExt, process::CommandExt},
    process::{Command, Stdio},
};

#[derive(Parser)]
#[command(version, about = "截图与录屏库 · 本地 OCR / Kitty 预览")]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,
}
#[derive(Subcommand)]
enum Commands {
    /// 打开图库（无参数时默认）
    Tui,
    /// 增量索引；默认后台低优先级 OCR
    Index {
        #[arg(long)]
        no_ocr: bool,
    },
    /// 文件名、日期、类型、来源与 OCR 搜索，输出 JSON
    Search {
        term: String,
        #[arg(long)]
        kind: Option<String>,
        #[arg(long)]
        source: Option<String>,
        #[arg(long)]
        favorite: bool,
    },
    Record {
        #[command(subcommand)]
        command: record::RecordCommand,
    },
    Ocr {
        #[command(subcommand)]
        command: OcrCommand,
    },
    #[command(hide = true)]
    RecordWorker { spec: String },
    #[command(hide = true)]
    OcrWorker,
}
#[derive(Subcommand)]
enum OcrCommand {
    Pause,
    Resume,
    Run,
}

fn self_command() -> Result<Command> {
    Ok(Command::new(
        std::env::var_os("SHOTS_SELF")
            .map(std::path::PathBuf::from)
            .unwrap_or(std::env::current_exe()?),
    ))
}
fn spawn_reaped(command: &mut Command) -> Result<()> {
    let mut child = command.spawn()?;
    std::thread::spawn(move || {
        let _ = child.wait();
    });
    Ok(())
}
fn start_ocr(lib: &Library) -> Result<()> {
    let log = OpenOptions::new()
        .create(true)
        .append(true)
        .mode(0o600)
        .open(lib.dir.join("ocr.log"))?;
    spawn_reaped(
        self_command()?
            .arg("ocr-worker")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(log)
            .process_group(0),
    )?;
    Ok(())
}
fn ocr_queue(lib: &Library) -> Result<()> {
    let mut errors = 0;
    loop {
        match lib.ocr_one() {
            Ok(true) => {}
            Ok(false) => break,
            Err(e) => {
                eprintln!("OCR: {e:#}");
                errors += 1;
                // Bound retries even if the underlying index or filesystem fails.
                if errors >= 100 {
                    anyhow::bail!("OCR 错误过多，稍后重新索引再试");
                }
            }
        }
    }
    Ok(())
}
fn main() {
    // Indexes, OCR and recording metadata contain private text.
    unsafe {
        libc::umask(0o077);
    }
    if let Err(e) = run() {
        eprintln!("shots-mayon: {e:#}");
        std::process::exit(1);
    }
}
fn run() -> Result<()> {
    let cli = Cli::parse();
    if let Some(Commands::RecordWorker { spec }) = cli.command {
        return record::worker(serde_json::from_str(&spec)?);
    }
    let lib = Library::open()?;
    match cli.command.unwrap_or(Commands::Tui) {
        Commands::Tui => tui::run(lib),
        Commands::Index { no_ocr } => {
            println!("索引 {} 个文件", lib.index()?);
            if !no_ocr {
                start_ocr(&lib)?;
            }
            Ok(())
        }
        Commands::Search {
            term,
            kind,
            source,
            favorite,
        } => {
            println!(
                "{}",
                serde_json::to_string_pretty(&lib.entries(
                    &term,
                    kind.as_deref(),
                    source.as_deref(),
                    favorite
                )?)?
            );
            Ok(())
        }
        Commands::Record { command } => {
            let result = record::run(&lib, command);
            if let Err(e) = &result {
                record::notify(&format!("录制请求失败：{e:#}"), false);
            }
            result
        }
        Commands::Ocr { command } => {
            match command {
                OcrCommand::Pause => lib.set_paused(true)?,
                OcrCommand::Resume => {
                    lib.set_paused(false)?;
                    start_ocr(&lib)?;
                }
                OcrCommand::Run => ocr_queue(&lib)?,
            }
            Ok(())
        }
        Commands::OcrWorker => ocr_queue(&lib),
        Commands::RecordWorker { .. } => unreachable!(),
    }
}
