use crate::{
    import::WordInput,
    schedule::*,
    store::{Settings, Store},
};
use anyhow::{bail, Context, Result};
use chrono::{Datelike, Duration, Local, NaiveDate, NaiveTime};
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeSet,
    path::{Path, PathBuf},
};

#[derive(Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Timetable {
    pub semester: Semester,
    pub courses: Vec<Course>,
    pub winter: BellSchedule,
    pub summer: BellSchedule,
    pub summer_from: Option<NaiveDate>,
}
impl Default for Timetable {
    fn default() -> Self {
        let today = Local::now().date_naive();
        let start = NaiveDate::from_ymd_opt(today.year(), if today.month() < 8 { 2 } else { 9 }, 1)
            .unwrap();
        let make = |shift: u32| BellSchedule {
            periods: [
                (8, 0),
                (8, 55),
                (10, 10),
                (11, 5),
                (14, 0),
                (14, 55),
                (16, 0),
                (16, 55),
                (19, 0),
                (19, 55),
                (20, 50),
            ]
            .into_iter()
            .enumerate()
            .map(|(i, (h, m))| {
                let start = NaiveTime::from_hms_opt(h + shift, m, 0).unwrap();
                PeriodTime {
                    period: i as u8 + 1,
                    start,
                    end: start + Duration::minutes(45),
                }
            })
            .collect(),
        };
        Self {
            semester: Semester::new(start, TermKind::Winter),
            courses: Vec::new(),
            winter: make(0),
            summer: make(0),
            summer_from: None,
        }
    }
}
impl Timetable {
    pub fn bell(&self, date: NaiveDate) -> &BellSchedule {
        if self.summer_from.is_some_and(|d| date >= d) || self.semester.kind == TermKind::Summer {
            &self.summer
        } else {
            &self.winter
        }
    }
    pub fn today(&self, date: NaiveDate) -> Result<Vec<ClassMeeting<'_>>> {
        courses_on(&self.courses, &self.semester, date, self.bell(date))
    }
    pub fn validate(&self) -> Result<()> {
        if self.semester.weeks == 0 || self.semester.weeks > 54 {
            bail!("学期应为 1–54 周");
        }
        for bell in [&self.winter, &self.summer] {
            let mut seen = BTreeSet::new();
            let mut last = None;
            for p in &bell.periods {
                if p.period == 0
                    || !seen.insert(p.period)
                    || p.end <= p.start
                    || last.is_some_and(|end| p.start < end)
                {
                    bail!("作息节次重复、顺序错误或时间重叠");
                }
                last = Some(p.end);
            }
            for c in &self.courses {
                c.validate(&self.semester)?;
                bell.for_course(c)?;
            }
        }
        Ok(())
    }
    pub fn next_json(&self, now: chrono::NaiveDateTime) -> Result<serde_json::Value> {
        // The bar intentionally hides after today's last class; CLI has the same contract.
        Ok(
            match self.today(now.date())?.into_iter().find(|m| m.end > now) {
                None => serde_json::Value::Null,
                Some(m) => {
                    let start = m
                        .start
                        .and_local_timezone(Local)
                        .single()
                        .context("课程开始时间处于 DST 歧义区间")?;
                    serde_json::json!({"course":m.course.name,"room":m.course.room,"start_time":start.to_rfc3339(),"remaining_minutes":((m.start-now).num_seconds().max(0)+59)/60,"status":if m.start<=now {"in_class"} else {"next"},"end_time":m.end.and_local_timezone(Local).single().context("课程结束时间不唯一")?.to_rfc3339()})
                }
            },
        )
    }
}
pub fn data_dir() -> PathBuf {
    std::env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".local/share")
        })
        .join("study")
}
pub fn seed(store: &mut Store) -> Result<()> {
    if !store.cards("", false)?.is_empty() {
        return Ok(());
    }
    let words = [
        (
            "serendipity",
            "ˌserənˈdɪpəti",
            "意外发现美好事物的运气",
            "the occurrence of happy discoveries by chance",
            "A walk through the library led to a moment of serendipity.",
            "serendip + ity · serendipitous",
        ),
        (
            "resilient",
            "rɪˈzɪliənt",
            "有韧性的；能恢复的",
            "able to recover after difficulty",
            "The resilient student tried again after the exam.",
            "re- 回 + salire 跳 · resilience",
        ),
        (
            "curiosity",
            "ˌkjʊəriˈɒsəti",
            "好奇心；求知欲",
            "a strong desire to learn something",
            "Curiosity keeps us asking thoughtful questions.",
            "curious + ity",
        ),
        (
            "consistent",
            "kənˈsɪstənt",
            "始终如一的；一致的",
            "acting in the same way over time",
            "Consistent practice makes progress possible.",
            "con- 共同 + sist 站立 · consistency",
        ),
    ];
    store.add(
        &words
            .into_iter()
            .map(
                |(word, phonetic, meaning, definition, example, roots)| WordInput {
                    word: word.into(),
                    phonetic: phonetic.into(),
                    meaning: meaning.into(),
                    definition: definition.into(),
                    example: example.into(),
                    roots: roots.into(),
                    book: "演示 · 自编例句".into(),
                },
            )
            .collect::<Vec<_>>(),
    )?;
    let now = Local::now();
    let today = now.date_naive();
    let monday = today - Duration::days(today.weekday().num_days_from_monday() as i64);
    let mut table = Timetable::default();
    table.semester.start_date = monday - Duration::weeks(8);
    for (name, room, teacher, weekday, periods, parity) in [
        (
            "高等数学 A",
            "博学楼 A302",
            "陈老师",
            1,
            vec![1, 2],
            WeekParity::Every,
        ),
        (
            "大学英语",
            "外语楼 203",
            "李老师",
            2,
            vec![3, 4],
            WeekParity::Every,
        ),
        (
            "数据结构",
            "计算机楼 406",
            "王老师",
            3,
            vec![1, 2],
            WeekParity::Every,
        ),
        (
            "大学物理",
            "理科楼 B201",
            "刘老师",
            4,
            vec![5, 6],
            WeekParity::Odd,
        ),
        (
            "线性代数",
            "博学楼 A205",
            "张老师",
            5,
            vec![3, 4],
            WeekParity::Every,
        ),
        (
            "程序设计实验",
            "实验楼 502",
            "周老师",
            5,
            vec![7, 8],
            WeekParity::Every,
        ),
    ] {
        table.courses.push(Course {
            name: name.into(),
            teacher: teacher.into(),
            room: room.into(),
            weekday,
            periods,
            weeks: (1..=18).collect(),
            parity,
        });
    }
    store.set("timetable", &table)?;
    let cards = store.cards("", false)?;
    for day in 1..85i64 {
        if day % 9 == 0 {
            continue;
        }
        for j in 0..((day * 7) % 17 + 3) {
            let card = &cards[(j as usize) % cards.len()];
            store.db.execute("INSERT INTO reviews(card,at,day,rating,elapsed,new,seconds) VALUES(?,?,?,?,0,0,24)",rusqlite::params![card.id,(now-Duration::days(day)).timestamp(),(today-Duration::days(day)).to_string(),if j%7==0 {1}else{3}])?;
        }
    }
    for (i, card) in cards.iter().enumerate().skip(1) {
        store.db.execute(
            "UPDATE words SET last=?,due=?,stability=6.0,difficulty=5.0 WHERE id=?",
            rusqlite::params![
                (now - Duration::days(1)).timestamp(),
                (now + Duration::days(i as i64)).timestamp(),
                card.id
            ],
        )?;
    }
    Ok(())
}
pub fn select_book(store: &mut Store, path: &Path, book: &str) -> Result<usize> {
    if !["cet4", "cet6", "ky", "ielts", "toefl", "gre"].contains(&book) {
        bail!("词书可选 cet4 cet6 ky ielts toefl gre");
    }
    let db =
        rusqlite::Connection::open_with_flags(path, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY)
            .context("找不到构建期词书；Nix 安装自带数据，Cargo 请指定 --dictionary")?;
    let mut stmt=db.prepare("SELECT word,phonetic,meaning,definition,example,roots,book FROM words WHERE book=? ORDER BY frequency DESC,word")?;
    let words = stmt
        .query_map([book], |r| {
            Ok(WordInput {
                word: r.get(0)?,
                phonetic: r.get(1)?,
                meaning: r.get(2)?,
                definition: r.get(3)?,
                example: r.get(4)?,
                roots: r.get(5)?,
                book: r.get(6)?,
            })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    store.add(&words)
}
pub fn settings(store: &Store) -> Result<Settings> {
    let cfg: Settings = store.get("settings")?;
    cfg.validate()?;
    Ok(cfg)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn bar_contract_hides_after_last_class_and_marks_in_class() {
        let mut table = Timetable::default();
        table.semester.start_date = "2026-09-01".parse().unwrap();
        table.courses.push(Course {
            name: "数学".into(),
            teacher: String::new(),
            room: "A302".into(),
            weekday: 5,
            periods: vec![1, 2],
            weeks: Default::default(),
            parity: WeekParity::Every,
        });
        let before = "2026-10-30T07:59:01".parse().unwrap();
        let json = table.next_json(before).unwrap();
        assert_eq!(json["remaining_minutes"], 1);
        assert_eq!(json["room"], "A302");
        assert_eq!(json["status"], "next");
        assert_eq!(
            table
                .next_json("2026-10-30T08:01:00".parse().unwrap())
                .unwrap()["status"],
            "in_class"
        );
        assert!(table
            .next_json("2026-10-30T20:00:00".parse().unwrap())
            .unwrap()
            .is_null());
    }
}
