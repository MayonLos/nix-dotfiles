use crate::import::WordInput;
use anyhow::{bail, Context, Result};
use chrono::{Duration, Local, NaiveDate};
use fsrs::{ComputeParametersInput, FSRSItem, FSRSReview, MemoryState, FSRS};
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, fs, os::unix::fs::PermissionsExt, path::Path};

#[derive(Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Settings {
    pub new_limit: u32,
    pub review_limit: u32,
    pub retention: f32,
    pub reminder: String,
    pub before_minutes: i64,
    pub parameters: Vec<f32>,
    pub audio: String,
}
impl Default for Settings {
    fn default() -> Self {
        Self {
            new_limit: 20,
            review_limit: 200,
            retention: 0.9,
            reminder: "20:00".into(),
            before_minutes: 10,
            parameters: fsrs::DEFAULT_PARAMETERS.to_vec(),
            audio: "espeak".into(),
        }
    }
}
impl Settings {
    pub fn validate(&self) -> Result<()> {
        if !(0.7..=0.99).contains(&self.retention)
            || self.before_minutes < 0
            || self.before_minutes > 120
        {
            bail!("留存目标应为 0.70–0.99，提醒应提前 0–120 分钟");
        }
        chrono::NaiveTime::parse_from_str(&self.reminder, "%H:%M").context("提醒时间使用 HH:MM")?;
        if self.parameters.len() != 21 {
            bail!("FSRS 6 参数必须为 21 项");
        }
        FSRS::new(&self.parameters)?;
        if !["espeak", "youdao", "none"].contains(&self.audio.as_str()) {
            bail!("audio 可选 espeak / youdao / none");
        }
        Ok(())
    }
}
#[derive(Clone)]
pub struct Card {
    pub id: i64,
    pub word: WordInput,
    pub due: i64,
    pub last: i64,
    pub stability: Option<f32>,
    pub difficulty: Option<f32>,
    pub lapses: u32,
}
#[derive(Default)]
pub struct Stats {
    pub daily: BTreeMap<NaiveDate, u32>,
    pub forecast: [u32; 7],
    pub count: u32,
    pub remembered: u32,
    pub minutes: u32,
    pub streak: u32,
    pub hours: [u32; 24],
    pub retention: f32,
}
pub struct Store {
    pub db: Connection,
}
impl Store {
    pub fn open(root: &Path) -> Result<Self> {
        fs::create_dir_all(root)?;
        fs::set_permissions(root, fs::Permissions::from_mode(0o700))?;
        let path = root.join("study.sqlite3");
        if path.is_symlink() {
            bail!("数据库不能是符号链接");
        }
        let db = Connection::open(&path)?;
        fs::set_permissions(path, fs::Permissions::from_mode(0o600))?;
        db.busy_timeout(std::time::Duration::from_secs(5))?;
        db.execute_batch("PRAGMA foreign_keys=ON;
          CREATE TABLE IF NOT EXISTS words(id INTEGER PRIMARY KEY,word TEXT UNIQUE NOT NULL,phonetic TEXT NOT NULL,meaning TEXT NOT NULL,definition TEXT NOT NULL,example TEXT NOT NULL,roots TEXT NOT NULL,book TEXT NOT NULL,due INTEGER NOT NULL DEFAULT 0,last INTEGER NOT NULL DEFAULT 0,stability REAL,difficulty REAL,lapses INTEGER NOT NULL DEFAULT 0);
          CREATE TABLE IF NOT EXISTS reviews(id INTEGER PRIMARY KEY,card INTEGER NOT NULL REFERENCES words(id),at INTEGER NOT NULL,day TEXT NOT NULL,rating INTEGER NOT NULL CHECK(rating BETWEEN 1 AND 4),elapsed INTEGER NOT NULL,new INTEGER NOT NULL,seconds INTEGER NOT NULL);
          CREATE INDEX IF NOT EXISTS due_index ON words(due);
          CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY,value TEXT NOT NULL);
          CREATE TABLE IF NOT EXISTS notified(key TEXT PRIMARY KEY,at INTEGER NOT NULL);")?;
        Ok(Self { db })
    }
    pub fn get<T: for<'a> Deserialize<'a> + Default>(&self, key: &str) -> Result<T> {
        let s: Option<String> = self
            .db
            .query_row("SELECT value FROM settings WHERE key=?", [key], |r| {
                r.get(0)
            })
            .optional()?;
        s.map(|s| serde_json::from_str(&s).map_err(Into::into))
            .unwrap_or_else(|| Ok(T::default()))
    }
    pub fn set<T: Serialize>(&self, key: &str, value: &T) -> Result<()> {
        self.db.execute(
            "INSERT INTO settings VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            params![key, serde_json::to_string(value)?],
        )?;
        Ok(())
    }
    pub fn add(&mut self, words: &[WordInput]) -> Result<usize> {
        let tx = self.db.transaction()?;
        let mut count = 0;
        for w in words {
            let word = w.word.trim();
            if word.is_empty() || word.chars().count() > 120 {
                continue;
            }
            count += tx.execute("INSERT INTO words(word,phonetic,meaning,definition,example,roots,book) VALUES(?,?,?,?,?,?,?) ON CONFLICT(word) DO UPDATE SET phonetic=CASE WHEN words.phonetic='' THEN excluded.phonetic ELSE words.phonetic END,meaning=CASE WHEN words.meaning='' THEN excluded.meaning ELSE words.meaning END,definition=CASE WHEN words.definition='' THEN excluded.definition ELSE words.definition END,example=CASE WHEN words.example='' THEN excluded.example ELSE words.example END,roots=CASE WHEN words.roots='' THEN excluded.roots ELSE words.roots END,book=CASE WHEN words.book='' THEN excluded.book ELSE words.book END WHERE (words.phonetic='' AND excluded.phonetic!='') OR (words.meaning='' AND excluded.meaning!='') OR (words.definition='' AND excluded.definition!='') OR (words.example='' AND excluded.example!='') OR (words.roots='' AND excluded.roots!='') OR (words.book='' AND excluded.book!='')",params![word,w.phonetic,w.meaning,w.definition,w.example,w.roots,w.book])?;
        }
        tx.commit()?;
        Ok(count)
    }
    pub fn cards(&self, filter: &str, wrong: bool) -> Result<Vec<Card>> {
        let mut stmt = self.db.prepare("SELECT id,word,phonetic,meaning,definition,example,roots,book,due,last,stability,difficulty,lapses FROM words WHERE (word LIKE ?1 OR meaning LIKE ?1 OR book LIKE ?1) AND (?2=0 OR lapses>0) ORDER BY (last=0),due,id")?;
        let rows = stmt.query_map(params![format!("%{filter}%"), wrong], |r| {
            Ok(Card {
                id: r.get(0)?,
                word: WordInput {
                    word: r.get(1)?,
                    phonetic: r.get(2)?,
                    meaning: r.get(3)?,
                    definition: r.get(4)?,
                    example: r.get(5)?,
                    roots: r.get(6)?,
                    book: r.get(7)?,
                },
                due: r.get(8)?,
                last: r.get(9)?,
                stability: r.get(10)?,
                difficulty: r.get(11)?,
                lapses: r.get(12)?,
            })
        })?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }
    pub fn queue(&self, now: i64, cfg: &Settings) -> Result<Vec<Card>> {
        let day = chrono::DateTime::from_timestamp(now, 0)
            .context("无效时间")?
            .with_timezone(&Local)
            .date_naive()
            .to_string();
        let (new, review): (u32, u32) = self.db.query_row(
            "SELECT COALESCE(SUM(new),0),COALESCE(SUM(1-new),0) FROM reviews WHERE day=?",
            [day],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )?;
        let mut n = cfg.new_limit.saturating_sub(new);
        let mut r = cfg.review_limit.saturating_sub(review);
        Ok(self
            .cards("", false)?
            .into_iter()
            .filter(|c| {
                if c.last == 0 {
                    if n > 0 {
                        n -= 1;
                        true
                    } else {
                        false
                    }
                } else if c.due <= now && r > 0 {
                    r -= 1;
                    true
                } else {
                    false
                }
            })
            .collect())
    }
    pub fn rate(
        &mut self,
        c: &Card,
        rating: u32,
        now: i64,
        seconds: u32,
        cfg: &Settings,
    ) -> Result<i64> {
        if !(1..=4).contains(&rating) {
            bail!("评分必须为 1–4");
        }
        cfg.validate()?;
        let elapsed = if c.last == 0 {
            0
        } else {
            ((now - c.last).max(0) / 86400) as u32
        };
        let state = c
            .stability
            .zip(c.difficulty)
            .map(|(stability, difficulty)| MemoryState {
                stability,
                difficulty,
            });
        let states = FSRS::new(&cfg.parameters)?.next_states(state, cfg.retention, elapsed)?;
        let next = match rating {
            1 => states.again,
            2 => states.hard,
            3 => states.good,
            _ => states.easy,
        };
        // Short relearning step: failing cards return after 60 seconds, not a whole day.
        let interval = if rating == 1 {
            60
        } else {
            (next.interval * 86400.).round().max(60.) as i64
        };
        let day = chrono::DateTime::from_timestamp(now, 0)
            .context("无效时间")?
            .with_timezone(&Local)
            .date_naive()
            .to_string();
        let tx = self.db.transaction()?;
        tx.execute(
            "UPDATE words SET due=?,last=?,stability=?,difficulty=?,lapses=lapses+? WHERE id=?",
            params![
                now + interval,
                now,
                next.memory.stability,
                next.memory.difficulty,
                u32::from(rating == 1),
                c.id
            ],
        )?;
        tx.execute(
            "INSERT INTO reviews(card,at,day,rating,elapsed,new,seconds) VALUES(?,?,?,?,?,?,?)",
            params![
                c.id,
                now,
                day,
                rating,
                elapsed,
                c.last == 0,
                seconds.min(3600)
            ],
        )?;
        tx.commit()?;
        Ok(now + interval)
    }
    pub fn optimize(&self, cfg: &mut Settings) -> Result<()> {
        let mut stmt = self
            .db
            .prepare("SELECT card,rating,elapsed FROM reviews ORDER BY card,at,id")?;
        let mut history: BTreeMap<i64, Vec<FSRSReview>> = BTreeMap::new();
        let mut train_set = Vec::new();
        let mut card_ids = Vec::new();
        for row in stmt.query_map([], |r| {
            Ok((
                r.get::<_, i64>(0)?,
                r.get::<_, u32>(1)?,
                r.get::<_, u32>(2)?,
            ))
        })? {
            let (id, rating, delta_t) = row?;
            let h = history.entry(id).or_default();
            h.push(FSRSReview { rating, delta_t });
            if h.len() > 1 {
                train_set.push(FSRSItem { reviews: h.clone() });
                card_ids.push(id);
            }
        }
        if train_set.len() < 400 {
            bail!(
                "至少需要 400 条含历史的复习样本，当前 {} 条；继续使用默认参数",
                train_set.len()
            );
        }
        cfg.parameters = fsrs::compute_parameters(ComputeParametersInput {
            train_set,
            card_ids: Some(card_ids),
            ..Default::default()
        })?;
        self.set("settings", cfg)
    }
    pub fn stats(&self, today: NaiveDate) -> Result<Stats> {
        let mut s = Stats::default();
        let mut total_seconds = 0;
        let mut stmt = self
            .db
            .prepare("SELECT day,COUNT(*),SUM(rating>1),SUM(seconds) FROM reviews GROUP BY day")?;
        for row in stmt.query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, u32>(1)?,
                r.get::<_, u32>(2)?,
                r.get::<_, u32>(3)?,
            ))
        })? {
            let (d, n, remembered, seconds) = row?;
            let d = d.parse()?;
            s.daily.insert(d, n);
            s.count += n;
            s.remembered += remembered;
            total_seconds += seconds;
        }
        s.minutes = total_seconds / 60;
        let mut by_hour = self.db.prepare(
            "SELECT strftime('%H',at,'unixepoch','localtime'),COUNT(*) FROM reviews GROUP BY 1",
        )?;
        for row in by_hour.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, u32>(1)?)))? {
            let (h, n) = row?;
            let h: usize = h.parse()?;
            if h < 24 {
                s.hours[h] = n;
            }
        }
        let mut d = if s.daily.contains_key(&today) {
            today
        } else {
            today - Duration::days(1)
        };
        while s.daily.contains_key(&d) {
            s.streak += 1;
            d -= Duration::days(1);
        }
        let cfg: Settings = self.get("settings")?;
        let decay = cfg
            .parameters
            .last()
            .copied()
            .unwrap_or(fsrs::FSRS6_DEFAULT_DECAY);
        let mut trained = 0;
        for c in self.cards("", false)?.into_iter().filter(|c| c.last > 0) {
            if let Some((stability, difficulty)) = c.stability.zip(c.difficulty) {
                let elapsed = (Local::now().timestamp() - c.last).max(0) as f32 / 86400.;
                s.retention += fsrs::current_retrievability(
                    MemoryState {
                        stability,
                        difficulty,
                    },
                    elapsed,
                    decay,
                );
                trained += 1;
            }
            if let Some(t) = chrono::DateTime::from_timestamp(c.due, 0) {
                let offset = (t.with_timezone(&Local).date_naive() - today)
                    .num_days()
                    .max(0);
                if offset < 7 {
                    s.forecast[offset as usize] += 1;
                }
            }
        }
        if trained > 0 {
            s.retention /= trained as f32;
        }
        Ok(s)
    }
    pub fn claim_notice(&self, key: &str, now: i64) -> Result<bool> {
        Ok(self.db.execute(
            "INSERT OR IGNORE INTO notified VALUES(?,?)",
            params![key, now],
        )? > 0)
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn store() -> Store {
        let s = Store {
            db: Connection::open_in_memory().unwrap(),
        };
        s.db.execute_batch("CREATE TABLE words(id INTEGER PRIMARY KEY,word TEXT UNIQUE,phonetic TEXT,meaning TEXT,definition TEXT,example TEXT,roots TEXT,book TEXT,due INTEGER DEFAULT 0,last INTEGER DEFAULT 0,stability REAL,difficulty REAL,lapses INTEGER DEFAULT 0);CREATE TABLE reviews(id INTEGER PRIMARY KEY,card INTEGER,at INTEGER,day TEXT,rating INTEGER,elapsed INTEGER,new INTEGER,seconds INTEGER);CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT);").unwrap();
        s
    }
    fn word() -> WordInput {
        WordInput {
            word: "learn".into(),
            phonetic: String::new(),
            meaning: "学习".into(),
            definition: String::new(),
            example: String::new(),
            roots: String::new(),
            book: "test".into(),
        }
    }
    #[test]
    fn fsrs_four_grades_and_persistence() {
        let cfg = Settings::default();
        let mut intervals = Vec::new();
        for grade in 1..=4 {
            let mut s = store();
            s.add(&[word()]).unwrap();
            let c = s.cards("", false).unwrap().remove(0);
            let due = s.rate(&c, grade, 1800000000, 15, &cfg).unwrap();
            intervals.push(due);
            assert!(s.cards("", false).unwrap()[0].stability.unwrap() > 0.);
        }
        assert!(intervals.windows(2).all(|w| w[0] < w[1]));
    }
    #[test]
    fn limits_and_failed_card_not_lost() {
        let mut s = store();
        s.add(&[word()]).unwrap();
        let cfg = Settings {
            new_limit: 1,
            review_limit: 1,
            ..Default::default()
        };
        let c = s.queue(1800000000, &cfg).unwrap().remove(0);
        s.rate(&c, 1, 1800000000, 30, &cfg).unwrap();
        assert!(s.queue(1800000001, &cfg).unwrap().is_empty());
        assert_eq!(s.queue(1800000060, &cfg).unwrap().len(), 1);
        assert_eq!(s.cards("", true).unwrap().len(), 1);
    }
    #[test]
    fn imported_definition_enriches_clipboard_word_without_losing_schedule() {
        let mut s = store();
        let mut w = word();
        w.meaning.clear();
        s.add(&[w]).unwrap();
        let c = s.cards("", false).unwrap().remove(0);
        s.rate(&c, 3, 1800000000, 15, &Settings::default()).unwrap();
        s.add(&[word()]).unwrap();
        let c = s.cards("", false).unwrap().remove(0);
        assert_eq!(c.word.meaning, "学习");
        assert_eq!(c.last, 1800000000);
        assert!(c.stability.is_some());
    }
}
