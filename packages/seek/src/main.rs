mod config;
mod embed;
mod extract;
mod index;
mod open;
mod qa;
mod tui;
use anyhow::Result;
use clap::{Parser, Subcommand};
use std::path::PathBuf;
#[derive(Parser)]
#[command(
    version,
    about = "本地资料混合检索；默认只检索，不外发。首次运行 seek init。"
)]
struct Args {
    #[arg(long, global = true)]
    config: Option<PathBuf>,
    #[arg(long, global = true)]
    data_dir: Option<PathBuf>,
    #[command(subcommand)]
    command: Option<Cmd>,
}
#[derive(Subcommand)]
enum Cmd {
    /// 只列目录名并写待审核配置；--confirm 输入 yes 后允许索引
    Init {
        #[arg(long)]
        confirm: bool,
    },
    /// 增量抽取与索引；后台模式电池供电时推迟
    Index {
        #[arg(long)]
        background: bool,
        #[arg(long)]
        force: bool,
    },
    /// 检索片段（无网络）；JSON 接口供 launchpad provider 使用
    Query {
        query: String,
        #[arg(long, default_value_t = 8)]
        limit: usize,
        #[arg(long)]
        json: bool,
        #[arg(long)]
        lexical: bool,
    },
    /// 显式问答：只向选定后端发送问题与 top-k 片段及来源元数据
    Ask {
        question: String,
        #[arg(long, default_value_t = 5)]
        limit: usize,
        #[arg(long)]
        dry_run: bool,
        #[arg(long)]
        backend: Option<String>,
        #[arg(long)]
        lexical: bool,
    },
    /// 实时搜索 / 问答 / 索引状态
    Tui {
        #[arg(long, default_value = "")]
        query: String,
        #[arg(long)]
        lexical: bool,
        #[arg(long, default_value = "auto")]
        viewer: String,
    },
    /// 从 stdin 逐行读取问题，逐行输出 JSON（一次加载模型，非守护进程）
    Batch {
        #[arg(long, default_value_t = 5)]
        limit: usize,
        #[arg(long)]
        lexical: bool,
    },
    Status {
        #[arg(long)]
        json: bool,
    },
    Model {
        #[command(subcommand)]
        command: ModelCmd,
    },
    /// 打开一次查询的指定结果（rank 从 1 开始）
    Open {
        query: String,
        #[arg(long, default_value_t = 1)]
        rank: usize,
        #[arg(long, default_value = "auto")]
        viewer: String,
        #[arg(long)]
        lexical: bool,
    },
}
#[derive(Subcommand)]
enum ModelCmd {
    Download,
}
fn main() {
    if let Err(e) = run() {
        eprintln!("seek: {e:#}");
        std::process::exit(1);
    }
}
fn run() -> Result<()> {
    let args = Args::parse();
    let path = args.config.unwrap_or(config::config_path()?);
    let data = args
        .data_dir
        .unwrap_or(config::xdg("XDG_DATA_HOME", ".local/share")?);
    let cmd = args.command.unwrap_or(Cmd::Tui {
        query: String::new(),
        lexical: false,
        viewer: "auto".into(),
    });
    if let Cmd::Init { confirm } = cmd {
        return config::init(&path, confirm);
    }
    if let Cmd::Model {
        command: ModelCmd::Download,
    } = cmd
    {
        return embed::download(&data);
    }
    let mut c = config::load(&path)?;
    match cmd {
        Cmd::Index { background, force } => {
            if background && (!c.confirmed || c.include.is_empty() || index::on_battery()) {
                println!("后台索引推迟：范围未确认或电池供电");
                return Ok(());
            }
            println!(
                "{}",
                serde_json::to_string_pretty(&index::run(&c, &data, background, force)?)?
            );
        }
        Cmd::Query {
            query,
            limit,
            json,
            lexical,
        } => {
            config::approved(&c)?;
            let start = std::time::Instant::now();
            let hits =
                index::Search::open(&data, c.embeddings && !lexical)?.query(&query, limit)?;
            if json {
                println!("{}", serde_json::to_string(&hits)?);
            } else {
                for h in hits {
                    println!(
                        "{}:{} · 行 {}–{}\n{}\n",
                        h.chunk.path,
                        h.chunk.page.map_or("段落".into(), |p| p.to_string()),
                        h.chunk.line_start,
                        h.chunk.line_end,
                        h.chunk.text
                    );
                }
                eprintln!("{} ms（含冷启动）", start.elapsed().as_millis());
            }
        }
        Cmd::Ask {
            question,
            limit,
            dry_run,
            backend,
            lexical,
        } => {
            config::approved(&c)?;
            let hits = index::Search::open(&data, c.embeddings && !lexical)?
                .query(&question, limit.min(20))?;
            if let Some(b) = backend {
                c.qa.backend = b;
            }
            if dry_run {
                println!(
                    "仅预览，不发请求。后端：{}\n问题：{}\n{}",
                    c.qa.backend,
                    question,
                    qa::context(&hits)
                );
            } else {
                eprintln!(
                    "显式问答：向 {} 发送问题、{} 个片段和来源元数据；不发送整文件。",
                    c.qa.backend,
                    hits.len()
                );
                println!("{}", qa::ask(&question, &hits, &c.qa)?);
            }
        }
        Cmd::Tui {
            query,
            lexical,
            viewer,
        } => {
            config::approved(&c)?;
            tui::run(c, &data, query, lexical, viewer)?;
        }
        Cmd::Batch { limit, lexical } => {
            use std::io::BufRead;
            config::approved(&c)?;
            let mut search = index::Search::open(&data, c.embeddings && !lexical)?;
            for q in std::io::stdin().lock().lines() {
                let q = q?;
                let start = std::time::Instant::now();
                let hits = search.query(&q, limit)?;
                println!(
                    "{}",
                    serde_json::json!({"query":q,"elapsed_ms":start.elapsed().as_secs_f64()*1000.0,"hits":hits})
                );
            }
        }
        Cmd::Status { json } => {
            let s = index::status(&data)?;
            if json {
                println!("{}", serde_json::to_string(&s)?);
            } else {
                println!(
                    "文件 {} · 片段 {} · 更新 Unix {} · 失败 {}\n{}",
                    s.files,
                    s.chunks,
                    s.updated_at,
                    s.failures.len(),
                    s.failures
                        .iter()
                        .map(|(p, e)| format!("{p}: {e}"))
                        .collect::<Vec<_>>()
                        .join("\n")
                );
            }
        }
        Cmd::Open {
            query,
            rank,
            viewer,
            lexical,
        } => {
            config::approved(&c)?;
            if rank == 0 {
                anyhow::bail!("rank 从 1 开始");
            }
            let hits = index::Search::open(&data, c.embeddings && !lexical)?.query(&query, rank)?;
            let h = hits
                .get(rank.saturating_sub(1))
                .ok_or_else(|| anyhow::anyhow!("结果不存在"))?;
            open::open(h, &viewer)?;
        }
        Cmd::Init { .. } | Cmd::Model { .. } => unreachable!(),
    }
    Ok(())
}
