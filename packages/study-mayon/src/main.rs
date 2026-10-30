mod app;
mod audio;
pub mod import;
mod reminder;
pub mod schedule;
mod store;
mod tui;
use anyhow::{bail, Context, Result};
use app::Timetable;
use clap::{Parser, Subcommand};
use std::{
    path::{Path, PathBuf},
    sync::OnceLock,
};
use store::Store;
static DATA_ROOT: OnceLock<PathBuf> = OnceLock::new();
#[derive(Parser)]
#[command(
    version,
    about = "学习 · FSRS 背单词与大学课表",
    long_about = "study-mayon / study · 本地 SQLite 学习工具。无参数启动 TUI，1–5 切页，? 查看帮助。"
)]
struct Args {
    #[arg(long, global = true)]
    data_dir: Option<PathBuf>,
    #[arg(long, global = true)]
    dictionary: Option<PathBuf>,
    /// 仅向显式 --data-dir 写入自编演示数据，用于隔离截图
    #[arg(long)]
    demo: bool,
    #[command(subcommand)]
    command: Option<Cmd>,
}
#[derive(Subcommand)]
enum Cmd {
    /// 打开界面，页码 1–5；模式 0 认识 / 1 释义拼写 / 2 听写 / 3 选择
    Tui {
        #[arg(long, default_value_t = 1)]
        page: usize,
        #[arg(long, default_value_t = 0)]
        mode: usize,
    },
    Today,
    Next {
        #[arg(long)]
        json: bool,
    },
    Add {
        word: String,
        #[arg(long, default_value = "")]
        meaning: String,
    },
    Import {
        file: PathBuf,
    },
    Export {
        file: PathBuf,
        #[arg(long, default_value = "csv")]
        format: String,
    },
    Books {
        book: Option<String>,
    },
    /// 显示或读取 settings JSON（程序独占写数据库）
    Settings {
        file: Option<PathBuf>,
    },
    /// 显示或读取完整学期、冬夏作息、课程 JSON
    Timetable {
        file: Option<PathBuf>,
    },
    /// 依据本地历史优化 FSRS 参数（CPU 任务，建议接电运行）
    Optimize,
    /// 安排最近一次背词/上课提醒，使用精确的 transient user timer
    Plan,
    /// timer 内部入口；也可手动检查当前到点提醒
    Remind,
    /// 输出可供教务 Excel 整理的通用 CSV 模板
    Template,
}
fn main() {
    if let Err(e) = main_inner() {
        eprintln!("study: {e:#}");
        std::process::exit(1);
    }
}
fn main_inner() -> Result<()> {
    // All state, journal, caches and child-created exports start private.
    unsafe {
        umask(0o077);
    }
    let args = Args::parse();
    if args.demo && args.data_dir.is_none() {
        bail!("--demo 必须搭配隔离 --data-dir");
    }
    let root = args.data_dir.clone().unwrap_or_else(app::data_dir);
    let mut store = Store::open(&root)?;
    let root = root.canonicalize()?;
    DATA_ROOT.set(root.clone()).ok();
    if args.demo {
        app::seed(&mut store)?;
    }
    let mut table: Timetable = store.get("timetable")?;
    table.validate()?;
    let dictionary = args
        .dictionary
        .or_else(|| std::env::var_os("STUDY_DICTIONARY").map(PathBuf::from))
        .unwrap_or_else(|| PathBuf::from("dictionary.sqlite3"));
    let now = chrono::Local::now();
    match args.command.unwrap_or(Cmd::Tui { page: 1, mode: 0 }) {
        Cmd::Tui { page, mode } => tui::run(&mut store, page.saturating_sub(1), dictionary, mode)?,
        Cmd::Today => {
            let meetings = table.today(now.date_naive())?;
            if meetings.is_empty() {
                println!("今日无课");
            }
            for m in meetings {
                println!(
                    "{}–{}  {}  {}  {}",
                    m.start.format("%H:%M"),
                    m.end.format("%H:%M"),
                    m.course.name,
                    m.course.room,
                    m.course.teacher
                );
            }
        }
        Cmd::Next { json } => {
            let next = table.next_json(now.naive_local())?;
            if json {
                println!("{}", serde_json::to_string(&next)?);
            } else if next.is_null() {
                println!("今日已无课");
            } else {
                println!(
                    "{} · {} · {} 分钟 · {}",
                    next["course"].as_str().unwrap_or(""),
                    next["room"].as_str().unwrap_or(""),
                    next["remaining_minutes"],
                    next["start_time"].as_str().unwrap_or("")
                );
            }
        }
        Cmd::Add { word, meaning } => {
            let mut w = blank_word(&word);
            w.meaning = meaning;
            println!("加入 {} 词", store.add(&[w])?);
        }
        Cmd::Import { file } => {
            import_file(&mut store, &mut table, &file)?;
            report_plan(&store, &table);
        }
        Cmd::Export { file, format } => {
            if file.exists() {
                bail!("导出目标已存在，请选择新文件，避免覆盖");
            }
            match format.as_str() {
                "csv" => import::export_csv(
                    &file,
                    &store
                        .cards("", false)?
                        .into_iter()
                        .map(|c| c.word)
                        .collect::<Vec<_>>(),
                )?,
                "apkg" => import::export_apkg(
                    &file,
                    &store
                        .cards("", false)?
                        .into_iter()
                        .map(|c| c.word)
                        .collect::<Vec<_>>(),
                )?,
                "ics" => std::fs::write(
                    &file,
                    schedule::export_ics_seasonal(
                        &table.courses,
                        &table.semester,
                        &table.winter,
                        &table.summer,
                        if table.semester.kind == schedule::TermKind::Summer {
                            Some(table.semester.start_date)
                        } else {
                            table.summer_from
                        },
                        app::settings(&store)?.before_minutes as u16,
                    )?,
                )?,
                _ => bail!("格式可选 csv/apkg/ics"),
            };
            println!("已导出 {}", file.display());
        }
        Cmd::Books { book } => {
            if let Some(book) = book {
                println!(
                    "加入 {} 词",
                    app::select_book(&mut store, &dictionary, &book)?
                );
            } else {
                println!("cet4 CET-4\ncet6 CET-6\nky 考研\nielts IELTS\ntoefl TOEFL\ngre GRE");
            }
        }
        Cmd::Settings { file } => {
            if let Some(file) = file {
                let cfg: store::Settings = serde_json::from_slice(&std::fs::read(file)?)?;
                cfg.validate()?;
                store.set("settings", &cfg)?;
                report_plan(&store, &table);
            }
            println!("{}", serde_json::to_string_pretty(&app::settings(&store)?)?);
        }
        Cmd::Timetable { file } => {
            if let Some(file) = file {
                let t: Timetable = serde_json::from_slice(&std::fs::read(file)?)?;
                t.validate()?;
                store.set("timetable", &t)?;
                table = t;
                report_plan(&store, &table);
            }
            println!("{}", serde_json::to_string_pretty(&table)?);
        }
        Cmd::Optimize => {
            let mut cfg = app::settings(&store)?;
            store.optimize(&mut cfg)?;
            println!("已优化并保存 {} 个 FSRS 参数", cfg.parameters.len());
        }
        Cmd::Plan => reminder::plan(&store, &table, &root)?,
        Cmd::Remind => reminder::remind(&store, &table, &root)?,
        Cmd::Template => println!(
            "课程名,教师,教室,星期,节次,周次,单双周\n高等数学,陈老师,A302,1,1-2,1-16,every"
        ),
    }
    Ok(())
}
unsafe extern "C" {
    fn umask(mask: u32) -> u32;
}
fn blank_word(word: &str) -> import::WordInput {
    import::WordInput {
        word: word.trim().into(),
        phonetic: String::new(),
        meaning: String::new(),
        definition: String::new(),
        example: String::new(),
        roots: String::new(),
        book: "生词本".into(),
    }
}
fn import_file(store: &mut Store, table: &mut Timetable, path: &Path) -> Result<()> {
    if std::fs::metadata(path)?.len() > 64 * 1024 * 1024 {
        bail!("导入文件上限 64 MiB");
    }
    let ext = path
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_lowercase();
    let mut next = table.clone();
    let courses = match ext.as_str() {
        "ics" => Some(schedule::import_ics(
            &std::fs::read_to_string(path)?,
            &table.semester,
            table.bell(chrono::Local::now().date_naive()),
        )?),
        "wakeup_schedule" | "wakeup" | "json" => {
            let (courses, start, bell) =
                schedule::import_wakeup_table(&std::fs::read_to_string(path)?)?;
            if let Some(start) = start {
                next.semester.start_date = start;
            }
            if let Some(bell) = bell {
                next.winter = bell.clone();
                next.summer = bell;
            }
            Some(courses)
        }
        "xls" | "xlsx" | "xlsb" | "ods" => Some(schedule::import_excel(&std::fs::read(path)?)?),
        _ => None,
    };
    if let Some(courses) = courses {
        for c in courses {
            if !next.courses.contains(&c) {
                next.courses.push(c);
            }
        }
        next.validate()
            .context("课表校验失败；请先设置学期与作息")?;
        store.set("timetable", &next)?;
        *table = next;
    } else {
        let words = import::read_words(path)?;
        store.add(&words)?;
    }
    Ok(())
}

fn replan(store: &Store, table: &Timetable) -> Option<String> {
    DATA_ROOT.get().and_then(|root| {
        reminder::plan(store, table, root)
            .err()
            .map(|e| format!("数据已保存；提醒需运行 study plan：{e:#}"))
    })
}
fn report_plan(store: &Store, table: &Timetable) {
    if let Some(message) = replan(store, table) {
        eprintln!("{message}");
    }
}
fn executable() -> Result<PathBuf> {
    Ok(std::env::var_os("STUDY_EXECUTABLE")
        .map(PathBuf::from)
        .unwrap_or(std::env::current_exe()?))
}
