use crate::{
    config::{self, Config},
    embed,
    extract::{self, Chunk},
};
use anyhow::{bail, Context, Result};
use globset::{Glob, GlobSet, GlobSetBuilder};
use jieba_rs::Jieba;
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use std::{
    collections::{HashMap, HashSet},
    fs,
    path::{Path, PathBuf},
    sync::LazyLock,
    time::{SystemTime, UNIX_EPOCH},
};
use tantivy::{
    collector::TopDocs,
    doc,
    query::{BooleanQuery, Occur, TermQuery},
    schema::{Field, IndexRecordOption, Schema, Value, STORED, TEXT},
    Index, IndexReader, Term,
};
use walkdir::WalkDir;
static JIEBA: LazyLock<Jieba> = LazyLock::new(Jieba::new);
pub fn terms(text: &str) -> Vec<String> {
    JIEBA
        .cut_for_search(text, false)
        .into_iter()
        .filter(|s| s.chars().any(char::is_alphanumeric))
        .map(str::to_lowercase)
        .collect()
}
#[derive(Debug, Default, Serialize, Deserialize)]
pub struct Report {
    pub files: usize,
    pub chunks: usize,
    pub updated: usize,
    pub removed: usize,
    pub failures: Vec<(String, String)>,
    pub updated_at: u64,
    pub hybrid: bool,
}
pub fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}
pub fn current(data: &Path) -> Result<PathBuf> {
    let name = fs::read_to_string(data.join("CURRENT")).context("索引尚未创建：运行 seek index")?;
    if !name.starts_with("gen-") || name.contains('/') || name.contains("..") {
        bail!("索引指针无效");
    }
    Ok(data.join(name))
}
pub fn status(data: &Path) -> Result<Report> {
    Ok(serde_json::from_slice(&fs::read(
        current(data)?.join("status.json"),
    )?)?)
}
fn patterns(c: &Config) -> Result<GlobSet> {
    let mut b = GlobSetBuilder::new();
    for g in &c.exclude {
        b.add(Glob::new(g)?);
    }
    Ok(b.build()?)
}
fn excluded(p: &Path, g: &GlobSet) -> bool {
    g.is_match(p) || g.is_match(p.join("__seek_child__"))
}
fn supported(p: &Path) -> bool {
    matches!(
        p.extension()
            .and_then(|s| s.to_str())
            .unwrap_or("")
            .to_ascii_lowercase()
            .as_str(),
        "md" | "txt"
            | "rs"
            | "py"
            | "c"
            | "h"
            | "cpp"
            | "hpp"
            | "java"
            | "js"
            | "ts"
            | "tsx"
            | "jsx"
            | "nix"
            | "lua"
            | "sh"
            | "go"
            | "rb"
            | "tex"
            | "csv"
            | "toml"
            | "yaml"
            | "yml"
            | "json"
            | "pdf"
            | "docx"
            | "pptx"
            | "xlsx"
    )
}
fn scan(c: &Config) -> Result<Vec<PathBuf>> {
    let g = patterns(c)?;
    let mut files = HashSet::new();
    for root in &c.include {
        if root.is_symlink() {
            bail!("include 不能是 symlink：{}", root.display());
        }
        if !root.is_dir() {
            bail!("include 目录不可用：{}", root.display());
        }
        for entry in WalkDir::new(root)
            .follow_links(false)
            .into_iter()
            .filter_entry(|e| {
                !excluded(
                    e.path()
                        .strip_prefix(root.parent().unwrap_or(root))
                        .unwrap_or(e.path()),
                    &g,
                )
            })
        {
            let e = entry.context("目录遍历失败，保留原索引")?;
            if e.file_type().is_file() && supported(e.path()) {
                files.insert(e.path().to_path_buf());
            }
        }
    }
    let mut files: Vec<_> = files.into_iter().collect();
    files.sort();
    Ok(files)
}
pub fn on_battery() -> bool {
    fs::read_dir("/sys/class/power_supply")
        .into_iter()
        .flatten()
        .flatten()
        .any(|e| {
            fs::read_to_string(e.path().join("type")).is_ok_and(|s| s.trim() == "Battery")
                && fs::read_to_string(e.path().join("status"))
                    .is_ok_and(|s| s.trim() == "Discharging")
        })
}
fn schema() -> (Schema, Field, Field) {
    let mut s = Schema::builder();
    let id = s.add_u64_field("id", STORED);
    let text = s.add_text_field("text", TEXT);
    (s.build(), id, text)
}
pub fn run(c: &Config, data: &Path, background: bool, force: bool) -> Result<Report> {
    config::approved(c)?;
    if background && on_battery() {
        bail!("电池供电，推迟后台索引；下次 timer 重试。手动 seek index 可覆盖");
    }
    let _lock = config::lock(data)?;
    let files = scan(c)?;
    let stage = tempfile::Builder::new()
        .prefix(".building-")
        .tempdir_in(data)?;
    let previous = current(data).ok();
    if let Some(p) = &previous {
        fs::copy(p.join("state.sqlite"), stage.path().join("state.sqlite"))?;
    }
    let mut db = Connection::open(stage.path().join("state.sqlite"))?;
    db.execute_batch("CREATE TABLE IF NOT EXISTS files(path TEXT PRIMARY KEY,mtime TEXT,size INTEGER,hash TEXT); CREATE TABLE IF NOT EXISTS chunks(id INTEGER PRIMARY KEY,path TEXT,data TEXT,vector BLOB); CREATE TABLE IF NOT EXISTS metadata(key TEXT PRIMARY KEY,value TEXT);")?;
    let extraction_version = format!(
        "v1-ocr-{}-max-{}-embed-{}-{}",
        c.ocr,
        c.max_file_mb,
        c.embeddings,
        embed::REVISION
    );
    let old_version: Option<String> = db
        .query_row("SELECT value FROM metadata WHERE key='version'", [], |r| {
            r.get(0)
        })
        .optional()?;
    let rebuild = force || old_version.as_deref() != Some(&extraction_version);
    let mut report = Report {
        updated_at: now(),
        hybrid: c.embeddings,
        ..Report::default()
    };
    let old_paths: Vec<String> = db
        .prepare("SELECT path FROM files")?
        .query_map([], |r| r.get(0))?
        .collect::<std::result::Result<_, _>>()?;
    let paths: HashSet<String> = files
        .iter()
        .map(|p| p.to_string_lossy().into_owned())
        .collect();
    let mut model = if c.embeddings {
        Some(embed::load(data)?)
    } else {
        None
    };
    let mut changed = rebuild;
    let tx = db.transaction()?;
    for path in old_paths {
        if !paths.contains(&path) {
            tx.execute("DELETE FROM chunks WHERE path=?1", [&path])?;
            tx.execute("DELETE FROM files WHERE path=?1", [&path])?;
            report.removed += 1;
            changed = true;
        }
    }
    for p in files {
        let path = p.to_string_lossy().into_owned();
        let result = (|| -> Result<()> {
            let meta = fs::symlink_metadata(&p)?;
            if !meta.is_file() {
                bail!("文件类型已变化");
            }
            if meta.len() > c.max_file_mb * 1024 * 1024 {
                bail!("超出文件大小上限");
            }
            let mtime = format!("{:?}", meta.modified()?);
            let old: Option<(String, u64, String)> = tx
                .query_row(
                    "SELECT mtime,size,hash FROM files WHERE path=?1",
                    [&path],
                    |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
                )
                .optional()?;
            if !rebuild
                && old
                    .as_ref()
                    .is_some_and(|(m, s, _)| m == &mtime && *s == meta.len())
            {
                return Ok(());
            }
            changed = true;
            let hash = blake3::hash(&fs::read(&p)?).to_hex().to_string();
            if !rebuild && old.as_ref().is_some_and(|(_, _, h)| h == &hash) {
                tx.execute(
                    "UPDATE files SET mtime=?1,size=?2 WHERE path=?3",
                    params![mtime, meta.len(), path],
                )?;
                return Ok(());
            }
            let chunks = extract::extract(&p, c.ocr, c.max_file_mb * 1024 * 1024)?;
            let mut rows = vec![];
            for ch in chunks {
                let v = if let Some(m) = &mut model {
                    embed::vector(m, &format!("{}\n{}", ch.title, ch.text), false)?
                } else {
                    vec![]
                };
                let bytes: Vec<u8> = v.iter().flat_map(|f| f.to_le_bytes()).collect();
                rows.push((serde_json::to_string(&ch)?, bytes));
            }
            tx.execute("DELETE FROM chunks WHERE path=?1", [&path])?;
            for (json, v) in rows {
                tx.execute(
                    "INSERT INTO chunks(path,data,vector) VALUES(?1,?2,?3)",
                    params![path, json, v],
                )?;
            }
            tx.execute(
                "INSERT OR REPLACE INTO files VALUES(?1,?2,?3,?4)",
                params![path, mtime, meta.len(), hash],
            )?;
            report.updated += 1;
            Ok(())
        })();
        if let Err(e) = result {
            changed = true;
            // Never expose stale content after a changed file fails extraction.
            tx.execute("DELETE FROM chunks WHERE path=?1", [&path])?;
            tx.execute("DELETE FROM files WHERE path=?1", [&path])?;
            report.failures.push((path, format!("{e:#}")));
        }
    }
    tx.execute(
        "INSERT OR REPLACE INTO metadata VALUES('version',?1)",
        [&extraction_version],
    )?;
    tx.commit()?;
    report.files = db.query_row("SELECT count(*) FROM files", [], |r| r.get(0))?;
    report.chunks = db.query_row("SELECT count(*) FROM chunks", [], |r| r.get(0))?;
    if !changed {
        if let Some(p) = previous {
            config::atomic(&p.join("status.json"), &serde_json::to_vec_pretty(&report)?)?;
            return Ok(report);
        }
    }
    let (schema, id, text) = schema();
    fs::create_dir(stage.path().join("bm25"))?;
    let index = Index::create_in_dir(stage.path().join("bm25"), schema)?;
    let mut writer = index.writer_with_num_threads(1, 30_000_000)?;
    let mut stmt = db.prepare("SELECT id,data FROM chunks")?;
    for row in stmt.query_map([], |r| Ok((r.get::<_, u64>(0)?, r.get::<_, String>(1)?)))? {
        let (key, json) = row?;
        let ch: Chunk = serde_json::from_str(&json)?;
        let t = terms(&format!("{} {} {}", ch.path, ch.title, ch.text)).join(" ");
        writer.add_document(doc!(id=>key,text=>t))?;
    }
    writer.commit()?;
    writer.wait_merging_threads()?;
    drop(stmt);
    drop(db);
    config::atomic(
        &stage.path().join("status.json"),
        &serde_json::to_vec_pretty(&report)?,
    )?;
    let name = format!(
        "gen-{}-{}-{}",
        now(),
        std::process::id(),
        stage
            .path()
            .file_name()
            .unwrap()
            .to_string_lossy()
            .trim_start_matches(".building-")
    );
    fs::rename(stage.path(), data.join(&name))?;
    config::atomic(&data.join("CURRENT"), name.as_bytes())?;
    Ok(report)
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Hit {
    #[serde(flatten)]
    pub chunk: Chunk,
    pub score: f64,
}
pub struct Search {
    _index: Index,
    reader: IndexReader,
    db: Connection,
    id: Field,
    text: Field,
    vectors: Vec<(u64, Vec<f32>)>,
    model: Option<fastembed::TextEmbedding>,
}
impl Search {
    pub fn open(data: &Path, hybrid: bool) -> Result<Self> {
        LazyLock::force(&JIEBA);
        let p = current(data)?;
        let report: Report = serde_json::from_slice(&fs::read(p.join("status.json"))?)?;
        if hybrid && !report.hybrid {
            bail!("当前索引仅含 BM25，请重新 seek index 或使用 --lexical");
        }
        let index = Index::open_in_dir(p.join("bm25"))?;
        let schema = index.schema();
        let db = Connection::open_with_flags(
            p.join("state.sqlite"),
            rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
        )?;
        let vectors = if hybrid {
            db.prepare("SELECT id,vector FROM chunks WHERE length(vector)>0")?
                .query_map([], |r| Ok((r.get::<_, u64>(0)?, r.get::<_, Vec<u8>>(1)?)))?
                .map(|r| {
                    r.map(|(id, b)| {
                        (
                            id,
                            embed::normalize(
                                b.chunks_exact(4)
                                    .map(|a| f32::from_le_bytes(a.try_into().unwrap()))
                                    .collect(),
                            ),
                        )
                    })
                })
                .collect::<std::result::Result<_, _>>()?
        } else {
            vec![]
        };
        let model = if hybrid && !vectors.is_empty() {
            Some(embed::load(data)?)
        } else {
            None
        };
        Ok(Self {
            id: schema.get_field("id")?,
            text: schema.get_field("text")?,
            reader: index.reader()?,
            _index: index,
            db,
            vectors,
            model,
        })
    }
    pub fn query(&mut self, q: &str, limit: usize) -> Result<Vec<Hit>> {
        if limit == 0 || limit > 100 {
            bail!("limit 须在 1..100");
        }
        if q.chars().count() > 2000 {
            bail!("查询过长");
        }
        let tokens = terms(q);
        if tokens.is_empty() {
            return Ok(vec![]);
        }
        let sub = tokens
            .into_iter()
            .map(|s| {
                (
                    Occur::Should,
                    Box::new(TermQuery::new(
                        Term::from_field_text(self.text, &s),
                        IndexRecordOption::WithFreqs,
                    )) as Box<dyn tantivy::query::Query>,
                )
            })
            .collect();
        let query = BooleanQuery::new(sub);
        let searcher = self.reader.searcher();
        let hits = searcher.search(&query, &TopDocs::with_limit(100))?;
        let mut lexical = vec![];
        for (_, address) in hits {
            let d = searcher.doc::<tantivy::TantivyDocument>(address)?;
            if let Some(id) = d.get_first(self.id).and_then(|v| v.as_u64()) {
                lexical.push(id);
            }
        }
        let mut ranks = vec![lexical];
        if let Some(m) = &mut self.model {
            let qv = embed::vector(m, q, true)?;
            let mut scored: Vec<_> = self
                .vectors
                .iter()
                .map(|(id, v)| (*id, embed::dot(&qv, v)))
                .collect();
            scored.sort_by(|a, b| b.1.total_cmp(&a.1));
            ranks.push(scored.into_iter().take(100).map(|(id, _)| id).collect());
        }
        let mut out = vec![];
        for (id, score) in rrf(&ranks).into_iter().take(limit) {
            let json: String =
                self.db
                    .query_row("SELECT data FROM chunks WHERE id=?1", [id], |r| r.get(0))?;
            out.push(Hit {
                chunk: serde_json::from_str(&json)?,
                score,
            });
        }
        Ok(out)
    }
}
pub fn rrf(ranks: &[Vec<u64>]) -> Vec<(u64, f64)> {
    let mut scores = HashMap::new();
    for list in ranks {
        for (rank, id) in list.iter().enumerate() {
            *scores.entry(*id).or_insert(0.0) += 1.0 / (61 + rank) as f64;
        }
    }
    let mut out: Vec<_> = scores.into_iter().collect();
    out.sort_by(|a, b| b.1.total_cmp(&a.1).then(a.0.cmp(&b.0)));
    out
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn fusion_rewards_agreement() {
        assert_eq!(rrf(&[vec![1, 2], vec![2, 3]])[0].0, 2);
    }
    #[test]
    fn chinese_search_tokens() {
        assert!(terms("人工智能 machine").contains(&"人工智能".to_string()));
    }
    #[test]
    fn exclusions_prune_subtrees() {
        let g = patterns(&Config::default()).unwrap();
        assert!(excluded(Path::new("/home/u/foo/node_modules"), &g));
        assert!(excluded(Path::new("/home/u/.cache"), &g));
        assert!(!excluded(Path::new("/home/u/notes"), &g));
    }
    #[test]
    fn incremental_removal_and_failure() {
        let d = tempfile::tempdir().unwrap();
        let root = d.path().join("notes");
        fs::create_dir(&root).unwrap();
        let path = root.join("lesson.md");
        fs::write(&path, "# 数学\n线性代数研究矩阵和向量空间。\n").unwrap();
        let data = d.path().join("data");
        let c = Config {
            confirmed: true,
            include: vec![root],
            embeddings: false,
            ..Config::default()
        };
        assert_eq!(run(&c, &data, false, false).unwrap().updated, 1);
        let before = fs::read_to_string(data.join("CURRENT")).unwrap();
        assert_eq!(run(&c, &data, false, false).unwrap().updated, 0);
        assert_eq!(before, fs::read_to_string(data.join("CURRENT")).unwrap());
        assert_eq!(
            Search::open(&data, false)
                .unwrap()
                .query("矩阵", 5)
                .unwrap()
                .len(),
            1
        );
        fs::write(&path, [0xff, 0xfe]).unwrap();
        assert_eq!(run(&c, &data, false, false).unwrap().failures.len(), 1);
        assert!(Search::open(&data, false)
            .unwrap()
            .query("矩阵", 5)
            .unwrap()
            .is_empty());
        fs::write(&path, "矩阵").unwrap();
        run(&c, &data, false, false).unwrap();
        fs::remove_file(path).unwrap();
        assert_eq!(run(&c, &data, false, false).unwrap().removed, 1);
    }
}
