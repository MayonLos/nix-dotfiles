//! Word list import/export helpers. Anki package support intentionally targets
//! the portable legacy `collection.anki2` SQLite format.

use anyhow::{anyhow, bail, Context, Result};
use rusqlite::{Connection, OpenFlags};
use serde::{Deserialize, Serialize};
use std::fs::{File, OpenOptions};
use std::io::{Read, Write};
use std::path::Path;
use tempfile::NamedTempFile;
use zip::{write::SimpleFileOptions, ZipArchive, ZipWriter};

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct WordInput {
    pub word: String,
    pub phonetic: String,
    pub meaning: String,
    pub definition: String,
    pub example: String,
    pub roots: String,
    pub book: String,
}

/// Read CSV (including this app's export), UTF-8 plain word lists, or Anki `.apkg`.
pub fn read_words(path: &Path) -> Result<Vec<WordInput>> {
    let ext = path
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or_default()
        .to_ascii_lowercase();
    match ext.as_str() {
        "apkg" => read_apkg(path),
        "txt" | "text" => {
            parse_text_reader(File::open(path).with_context(|| format!("open {}", path.display()))?)
        }
        "csv" => {
            parse_csv_reader(File::open(path).with_context(|| format!("open {}", path.display()))?)
        }
        _ => bail!(
            "不支持的词表格式：{}（支持 .csv、.txt、.apkg）",
            path.display()
        ),
    }
}

pub fn parse_text_reader(reader: impl Read) -> Result<Vec<WordInput>> {
    let mut out = Vec::new();
    for (line_no, line) in std::io::BufRead::lines(std::io::BufReader::new(reader)).enumerate() {
        let line = line.with_context(|| format!("读取第 {} 行", line_no + 1))?;
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let (word, meaning) = line
            .split_once('\t')
            .or_else(|| line.split_once(','))
            .map(|(a, b)| (a.trim(), b.trim()))
            .unwrap_or((line, ""));
        if word.is_empty() {
            continue;
        }
        out.push(WordInput {
            word: word.into(),
            meaning: meaning.into(),
            ..Default::default()
        });
    }
    Ok(out)
}

pub fn parse_csv_reader(reader: impl Read) -> Result<Vec<WordInput>> {
    let mut input = Vec::new();
    std::io::Read::read_to_end(&mut std::io::BufReader::new(reader), &mut input)?;
    let mut csv = csv::ReaderBuilder::new()
        .flexible(true)
        .trim(csv::Trim::All)
        .from_reader(input.as_slice());
    let headers = csv.headers().context("CSV 缺少表头或无法读取")?.clone();
    let normalized: Vec<String> = headers
        .iter()
        .map(|h| normalize_header(h.trim_start_matches('\u{feff}')))
        .collect();
    let has_header = normalized
        .iter()
        .any(|h| matches!(h.as_str(), "word" | "english" | "front" | "单词" | "英文"));
    let mut out = Vec::new();
    if has_header {
        for (row_no, row) in csv.records().enumerate() {
            let row = row.with_context(|| format!("CSV 第 {} 行格式错误", row_no + 2))?;
            let get = |names: &[&str]| -> String {
                names
                    .iter()
                    .find_map(|name| {
                        normalized
                            .iter()
                            .position(|h| h == name)
                            .and_then(|i| row.get(i))
                    })
                    .unwrap_or_default()
                    .trim()
                    .to_owned()
            };
            let word = get(&["word", "english", "front", "单词", "英文"]);
            if word.is_empty() {
                continue;
            }
            out.push(WordInput {
                word,
                phonetic: get(&["phonetic", "音标"]),
                meaning: get(&["meaning", "translation", "中文", "释义", "back"]),
                definition: get(&["definition", "englishdefinition", "英文释义"]),
                example: get(&["example", "sentence", "例句"]),
                roots: get(&["roots", "root", "derivatives", "词根", "派生"]),
                book: get(&["book", "deck", "词书"]),
            });
        }
    } else {
        // Headerless two-column CSV: word, meaning.
        let mut records = csv::ReaderBuilder::new()
            .has_headers(false)
            .flexible(true)
            .trim(csv::Trim::All)
            .from_reader(input.as_slice());
        for (row_no, row) in records.records().enumerate() {
            let row = row.with_context(|| format!("CSV 第 {} 行格式错误", row_no + 1))?;
            let word = row.get(0).unwrap_or_default().trim();
            if !word.is_empty() {
                out.push(WordInput {
                    word: word.into(),
                    meaning: row.get(1).unwrap_or_default().trim().into(),
                    ..Default::default()
                });
            }
        }
    }
    Ok(out)
}

fn normalize_header(value: &str) -> String {
    value
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || !c.is_ascii())
        .flat_map(char::to_lowercase)
        .collect()
}

pub fn export_csv(path: &Path, words: &[WordInput]) -> Result<()> {
    let file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .with_context(|| format!("创建 CSV（目标已存在时拒绝覆盖）：{}", path.display()))?;
    let mut writer = csv::WriterBuilder::new()
        .has_headers(false)
        .from_writer(file);
    writer.write_record([
        "word",
        "phonetic",
        "meaning",
        "definition",
        "example",
        "roots",
        "book",
    ])?;
    for item in words {
        writer.serialize(item)?;
    }
    writer.flush().context("写入 CSV")?;
    Ok(())
}

fn read_apkg(path: &Path) -> Result<Vec<WordInput>> {
    let file = File::open(path).with_context(|| format!("open {}", path.display()))?;
    let mut archive = ZipArchive::new(file).context("不是有效的 Anki apkg/zip 文件")?;
    let mut legacy = None;
    let mut modern = None;
    for i in 0..archive.len() {
        let entry = archive.by_index(i)?;
        let name = entry.name().to_owned();
        if name.ends_with("collection.anki21") || name.ends_with("collection.anki21b") {
            modern.get_or_insert(name);
        } else if name.ends_with("collection.anki2") {
            legacy.get_or_insert(name);
        }
    }
    if let Some(name) = modern {
        bail!("暂不支持新版 Anki 数据库 {name}；请在 Anki 中导出为兼容旧版的 apkg 或 CSV");
    }
    let name = legacy.ok_or_else(|| {
        anyhow!("apkg 内没有 collection.anki2；该 Anki 包可能采用暂不支持的新版数据库格式")
    })?;
    const MAX_DATABASE_BYTES: u64 = 64 * 1024 * 1024;
    let mut entry = archive.by_name(&name)?;
    if entry.size() > MAX_DATABASE_BYTES {
        bail!("Anki 数据库超过 64 MiB 解压上限");
    }
    let mut db_data = Vec::new();
    entry
        .by_ref()
        .take(MAX_DATABASE_BYTES + 1)
        .read_to_end(&mut db_data)?;
    if db_data.len() as u64 > MAX_DATABASE_BYTES {
        bail!("Anki 数据库超过 64 MiB 解压上限");
    }
    let temp_db = NamedTempFile::new().context("创建临时 Anki 数据库文件")?;
    temp_db.as_file().write_all(&db_data)?;
    temp_db.as_file().sync_all()?;
    let result = (|| -> Result<Vec<WordInput>> {
        let conn = Connection::open_with_flags(temp_db.path(), OpenFlags::SQLITE_OPEN_READ_ONLY)?;
        let models: String = conn
            .query_row("SELECT models FROM col LIMIT 1", [], |r| r.get(0))
            .context("Anki 包缺少 col.models")?;
        let model_fields = parse_model_fields(&models);
        let columns = table_columns(&conn, "notes")?;
        if !columns.iter().any(|c| c == "flds") {
            bail!("Anki notes 表缺少 flds 列");
        }
        let mut stmt = conn.prepare("SELECT mid, flds FROM notes")?;
        let rows = stmt.query_map([], |row| {
            Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?))
        })?;
        let mut result = Vec::new();
        for row in rows {
            let (mid, fields) = row?;
            let fields: Vec<&str> = fields.split('\x1f').collect();
            let names = model_fields.get(&mid);
            let find = |keys: &[&str], fallback: usize| -> String {
                let idx = names
                    .and_then(|n| {
                        n.iter()
                            .position(|name| keys.iter().any(|key| normalize_header(name) == *key))
                    })
                    .unwrap_or(fallback);
                fields.get(idx).copied().unwrap_or_default().to_owned()
            };
            let word = strip_anki_markup(&find(&["word", "english", "front", "单词"], 0));
            if word.trim().is_empty() {
                continue;
            }
            result.push(WordInput {
                word,
                meaning: strip_anki_markup(&find(&["meaning", "translation", "back", "中文"], 1)),
                ..Default::default()
            });
        }
        Ok(result)
    })();
    result
}

fn strip_anki_markup(input: &str) -> String {
    let mut plain = String::with_capacity(input.len());
    let mut in_tag = false;
    for ch in input.chars() {
        match ch {
            '<' => in_tag = true,
            '>' if in_tag => {
                in_tag = false;
                plain.push(' ');
            }
            _ if !in_tag => plain.push(ch),
            _ => {}
        }
    }
    let plain = decode_basic_entities(&plain);
    let mut without_audio = String::with_capacity(plain.len());
    let mut rest = plain.as_str();
    while let Some(start) = rest.to_ascii_lowercase().find("[sound:") {
        without_audio.push_str(&rest[..start]);
        let after = &rest[start..];
        if let Some(end) = after.find(']') {
            without_audio.push(' ');
            rest = &after[end + 1..];
        } else {
            rest = "";
            break;
        }
    }
    without_audio.push_str(rest);
    without_audio
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

fn decode_basic_entities(input: &str) -> String {
    let mut output = String::with_capacity(input.len());
    let mut rest = input;
    while let Some(amp) = rest.find('&') {
        output.push_str(&rest[..amp]);
        let after = &rest[amp..];
        let Some(end) = after.find(';') else {
            output.push_str(after);
            return output;
        };
        let entity = &after[1..end];
        let decoded = match entity {
            "amp" => Some('&'),
            "lt" => Some('<'),
            "gt" => Some('>'),
            "quot" => Some('"'),
            "apos" | "#39" => Some('\''),
            "nbsp" => Some(' '),
            value if value.starts_with("#x") || value.starts_with("#X") => {
                u32::from_str_radix(&value[2..], 16)
                    .ok()
                    .and_then(char::from_u32)
            }
            value if value.starts_with('#') => {
                value[1..].parse::<u32>().ok().and_then(char::from_u32)
            }
            _ => None,
        };
        if let Some(ch) = decoded {
            output.push(ch);
        } else {
            output.push_str(&after[..=end]);
        }
        rest = &after[end + 1..];
    }
    output.push_str(rest);
    output
}

fn table_columns(conn: &Connection, table: &str) -> Result<Vec<String>> {
    let mut stmt = conn.prepare(&format!("PRAGMA table_info({table})"))?;
    let rows = stmt.query_map([], |r| r.get(1))?;
    Ok(rows.collect::<rusqlite::Result<Vec<String>>>()?)
}

fn parse_model_fields(models: &str) -> std::collections::HashMap<i64, Vec<String>> {
    let Ok(models) = serde_json::from_str::<serde_json::Value>(models) else {
        return Default::default();
    };
    models
        .as_object()
        .into_iter()
        .flatten()
        .filter_map(|(id, model)| {
            let id = id.parse().ok()?;
            let names = model
                .get("flds")?
                .as_array()?
                .iter()
                .filter_map(|f| f.get("name")?.as_str().map(str::to_owned))
                .collect();
            Some((id, names))
        })
        .collect()
}

/// Export a basic two-field Anki package. Media and scheduling history are not
/// included; generated cards are ordinary front/back notes.
pub fn export_apkg(path: &Path, words: &[WordInput]) -> Result<()> {
    let now = chrono::Utc::now().timestamp();
    let temp_db = NamedTempFile::new().context("创建临时 Anki 导出数据库")?;
    let mut conn = Connection::open(temp_db.path())?;
    conn.execute_batch("PRAGMA journal_mode=OFF; CREATE TABLE col (id integer primary key, crt integer not null, mod integer not null, scm integer not null, ver integer not null, dty integer not null, usn integer not null, ls integer not null, conf text not null, models text not null, decks text not null, dconf text not null, tags text not null); CREATE TABLE notes (id integer primary key, guid text not null, mid integer not null, mod integer not null, usn integer not null, tags text not null, flds text not null, sfld integer not null, csum integer not null, flags integer not null, data text not null); CREATE TABLE cards (id integer primary key, nid integer not null, did integer not null, ord integer not null, mod integer not null, usn integer not null, type integer not null, queue integer not null, due integer not null, ivl integer not null, factor integer not null, reps integer not null, lapses integer not null, left integer not null, odue integer not null, odid integer not null, flags integer not null, data text not null); CREATE TABLE revlog (id integer primary key, cid integer not null, usn integer not null, ease integer not null, ivl integer not null, lastIvl integer not null, factor integer not null, time integer not null, type integer not null); CREATE TABLE graves (usn integer not null, oid integer not null, type integer not null);")?;
    let model_id = 1_700_000_000_000i64;
    let deck_id = 1i64;
    let model = serde_json::json!({model_id.to_string(): {"id":model_id,"name":"Study Mayon","type":0,"mod":0,"usn":-1,"sortf":0,"did":deck_id,"flds":[{"name":"Word","ord":0,"sticky":false,"rtl":false,"font":"Arial","size":20,"media":[]},{"name":"Meaning","ord":1,"sticky":false,"rtl":false,"font":"Arial","size":20,"media":[]}],"tmpls":[{"name":"Card 1","ord":0,"qfmt":"{{Word}}","afmt":"{{FrontSide}}<hr id=answer>{{Meaning}}","did":null,"bqfmt":"","bafmt":""}],"css":".card { font-family: Arial; font-size: 20px; text-align: center; }","latexPre":"","latexPost":"","req":[[0,"all",[0]]],"tags":[]}});
    let decks = serde_json::json!({deck_id.to_string(): {"id":deck_id,"name":"Study Mayon","desc":"","mod":0,"usn":-1,"collapsed":false,"browserCollapsed":false,"conf":1,"dyn":0,"extendNew":10,"extendRev":50,"newToday":[0,0],"revToday":[0,0],"lrnToday":[0,0],"timeToday":[0,0]}});
    conn.execute(
        "INSERT INTO col VALUES (1,?1,?1,?2,11,0,-1,0,'{}',?3,?4,'{}','{}')",
        rusqlite::params![now, now * 1000, model.to_string(), decks.to_string()],
    )?;
    {
        let tx = conn.transaction()?;
        for (i, item) in words.iter().enumerate() {
            let id = now * 1000 + i as i64 + 1;
            let fields = format!("{}\x1f{}", item.word, item.meaning);
            let checksum = u32::from_be_bytes(sha1_prefix(&item.word));
            let guid = format!("{:016x}", id);
            tx.execute(
                "INSERT INTO notes VALUES (?1,?2,?3,?4,-1,'',?5,?6,?7,0,'')",
                rusqlite::params![id, guid, model_id, now, fields, item.word, checksum],
            )?;
            tx.execute(
                "INSERT INTO cards VALUES (?1,?2,?3,0,?4,-1,0,0,?5,0,2500,0,0,0,0,0,0,'')",
                rusqlite::params![id, id, deck_id, now, i as i64 + 1],
            )?;
        }
        tx.commit()?;
    }
    drop(conn);
    let db = std::fs::read(temp_db.path())?;
    let file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .with_context(|| format!("创建 Anki 包（目标已存在时拒绝覆盖）：{}", path.display()))?;
    let mut zip = ZipWriter::new(file);
    zip.start_file(
        "collection.anki2",
        SimpleFileOptions::default().compression_method(zip::CompressionMethod::Deflated),
    )?;
    zip.write_all(&db)?;
    zip.start_file("media", SimpleFileOptions::default())?;
    zip.write_all(b"{}")?;
    zip.finish()?;
    Ok(())
}

fn sha1_prefix(input: &str) -> [u8; 4] {
    // Anki stores the first 32 bits of SHA-1(field 0) for duplicate lookup.
    let bytes = input.as_bytes();
    let bit_len = (bytes.len() as u64).wrapping_mul(8);
    let mut padded = bytes.to_vec();
    padded.push(0x80);
    while padded.len() % 64 != 56 {
        padded.push(0);
    }
    padded.extend_from_slice(&bit_len.to_be_bytes());
    let (mut h0, mut h1, mut h2, mut h3, mut h4) = (
        0x67452301u32,
        0xefcdab89u32,
        0x98badcfeu32,
        0x10325476u32,
        0xc3d2e1f0u32,
    );
    for chunk in padded.chunks_exact(64) {
        let mut w = [0u32; 80];
        for (i, word) in chunk.chunks_exact(4).take(16).enumerate() {
            w[i] = u32::from_be_bytes(word.try_into().expect("4-byte word"));
        }
        for i in 16..80 {
            w[i] = (w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]).rotate_left(1);
        }
        let (mut a, mut b, mut c, mut d, mut e) = (h0, h1, h2, h3, h4);
        for (i, word) in w.iter().enumerate() {
            let (f, k) = match i {
                0..=19 => ((b & c) | ((!b) & d), 0x5a827999),
                20..=39 => (b ^ c ^ d, 0x6ed9eba1),
                40..=59 => ((b & c) | (b & d) | (c & d), 0x8f1bbcdc),
                _ => (b ^ c ^ d, 0xca62c1d6),
            };
            let temp = a
                .rotate_left(5)
                .wrapping_add(f)
                .wrapping_add(e)
                .wrapping_add(k)
                .wrapping_add(*word);
            (e, d, c, b, a) = (d, c, b.rotate_left(30), a, temp);
        }
        h0 = h0.wrapping_add(a);
        h1 = h1.wrapping_add(b);
        h2 = h2.wrapping_add(c);
        h3 = h3.wrapping_add(d);
        h4 = h4.wrapping_add(e);
    }
    h0.to_be_bytes()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::io::Cursor;

    #[test]
    fn parses_word_list_and_annotations() {
        let got = parse_text_reader(Cursor::new("# note\nserendipity\napple\t苹果\n")).unwrap();
        assert_eq!(got.len(), 2);
        assert_eq!(got[1].meaning, "苹果");
    }

    #[test]
    fn csv_round_trip() {
        let words = vec![WordInput {
            word: "hello, world".into(),
            meaning: "你好\n世界".into(),
            book: "CET-4".into(),
            ..Default::default()
        }];
        let path =
            std::env::temp_dir().join(format!("study-import-test-{}.csv", std::process::id()));
        export_csv(&path, &words).unwrap();
        let got = read_words(&path).unwrap();
        let _ = fs::remove_file(path);
        assert_eq!(got, words);
    }

    #[test]
    fn parses_csv_fixture() {
        let words = read_words(Path::new(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/tests/fixtures/words.csv"
        )))
        .unwrap();
        assert_eq!(words[0].phonetic, "ˈæp.əl");
        assert_eq!(words[0].meaning, "苹果");
        assert_eq!(words[0].book, "CET-4");
    }

    #[test]
    fn parses_bom_prefixed_chinese_csv_headers() {
        let words = read_words(Path::new(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/tests/fixtures/words-bom.csv"
        )))
        .unwrap();
        assert_eq!(words[0].word, "campus");
        assert_eq!(words[0].meaning, "校园");
    }

    #[test]
    fn exports_importable_anki_package() {
        let path =
            std::env::temp_dir().join(format!("study-export-test-{}.apkg", std::process::id()));
        let expected = vec![WordInput {
            word: "campus".into(),
            meaning: "校园".into(),
            ..Default::default()
        }];
        export_apkg(&path, &expected).unwrap();
        let got = read_words(&path).unwrap();
        let _ = fs::remove_file(path);
        assert_eq!(got[0].word, "campus");
        assert_eq!(got[0].meaning, "校园");
    }

    #[test]
    fn imports_anki_fixture() {
        use base64::Engine;
        let mut fixture = tempfile::Builder::new().suffix(".apkg").tempfile().unwrap();
        fixture
            .write_all(
                &base64::engine::general_purpose::STANDARD
                    .decode(include_str!("../tests/fixtures/basic.apkg.b64").trim())
                    .unwrap(),
            )
            .unwrap();
        let words = read_words(fixture.path()).unwrap();
        assert_eq!(words[0].word, "abandon");
        assert_eq!(words[0].meaning, "放弃");
    }

    #[test]
    fn anki_checksum_uses_sha1_prefix() {
        assert_eq!(sha1_prefix("abc"), [0xa9, 0x99, 0x3e, 0x36]);
    }

    #[test]
    fn modern_collection_wins_over_legacy_placeholder() {
        let path = std::env::temp_dir().join(format!(
            "study-modern-anki-test-{}.apkg",
            std::process::id()
        ));
        let file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&path)
            .unwrap();
        let mut archive = ZipWriter::new(file);
        archive
            .start_file("collection.anki2", SimpleFileOptions::default())
            .unwrap();
        archive.write_all(b"legacy placeholder").unwrap();
        archive
            .start_file("collection.anki21b", SimpleFileOptions::default())
            .unwrap();
        archive.write_all(b"modern collection").unwrap();
        archive.finish().unwrap();
        let error = read_words(&path).unwrap_err().to_string();
        let _ = std::fs::remove_file(path);
        assert!(error.contains("新版 Anki"));
    }

    #[test]
    fn strips_html_audio_and_basic_entities() {
        assert_eq!(
            strip_anki_markup("<div>abandon &amp; leave</div>[sound:word.mp3]"),
            "abandon & leave"
        );
    }
}
