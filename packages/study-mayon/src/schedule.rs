//! Offline timetable model and import/export helpers.
//!
//! WakeUp's public documentation describes backup-file and share-code import,
//! while online sharing requires the app's network permission. We intentionally
//! accept local exported JSON only and never call an undocumented share API.

use anyhow::{anyhow, bail, Context, Result};
use chrono::{Datelike, Duration, NaiveDate, NaiveDateTime, NaiveTime, Weekday};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeSet, HashMap};
use std::io::Cursor;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum TermKind {
    #[default]
    Winter,
    Summer,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Semester {
    pub start_date: NaiveDate,
    #[serde(default = "default_term_weeks")]
    pub weeks: u8,
    #[serde(default)]
    pub kind: TermKind,
}

fn default_term_weeks() -> u8 {
    20
}

impl Semester {
    pub fn new(start_date: NaiveDate, kind: TermKind) -> Self {
        Self {
            start_date,
            weeks: 20,
            kind,
        }
    }

    /// Monday-based academic week containing the configured first day.
    pub fn week_on(&self, date: NaiveDate) -> Option<u8> {
        let first_monday = self.start_date
            - Duration::days(i64::from(self.start_date.weekday().num_days_from_monday()));
        let date_monday = date - Duration::days(i64::from(date.weekday().num_days_from_monday()));
        let week = date_monday
            .signed_duration_since(first_monday)
            .num_days()
            .div_euclid(7)
            + 1;
        (week >= 1 && week <= i64::from(self.weeks)).then_some(week as u8)
    }

    pub fn date_for(&self, week: u8, day: Weekday) -> Result<NaiveDate> {
        if week == 0 || week > self.weeks {
            bail!("周次 {week} 超出学期范围 1..={}", self.weeks);
        }
        let monday = self.start_date
            - Duration::days(i64::from(self.start_date.weekday().num_days_from_monday()));
        Ok(monday
            + Duration::weeks(i64::from(week - 1))
            + Duration::days(i64::from(day.num_days_from_monday())))
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum WeekParity {
    #[default]
    Every,
    Odd,
    Even,
}

impl WeekParity {
    pub fn includes(self, week: u8) -> bool {
        match self {
            Self::Every => true,
            Self::Odd => week % 2 == 1,
            Self::Even => week.is_multiple_of(2),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Course {
    pub name: String,
    #[serde(default)]
    pub teacher: String,
    #[serde(default)]
    pub room: String,
    /// ISO weekday, Monday=1 through Sunday=7.
    pub weekday: u8,
    /// Inclusive class periods, for example `[1, 2]`.
    pub periods: Vec<u8>,
    /// Explicit semester week numbers. Empty means all weeks (subject to parity).
    #[serde(default)]
    pub weeks: BTreeSet<u8>,
    #[serde(default)]
    pub parity: WeekParity,
}

impl Course {
    pub fn validate(&self, semester: &Semester) -> Result<()> {
        if self.name.trim().is_empty() {
            bail!("课程名不能为空");
        }
        if !(1..=7).contains(&self.weekday) {
            bail!("weekday 必须为 ISO 星期 1..=7");
        }
        if self.periods.is_empty() || self.periods.contains(&0) {
            bail!("课程至少需要一个大于 0 的节次");
        }
        if self.weeks.iter().any(|w| *w == 0 || *w > semester.weeks) {
            bail!("课程周次超出学期范围");
        }
        Ok(())
    }

    pub fn occurs(&self, weekday: Weekday, week: u8) -> bool {
        self.weekday == weekday.number_from_monday() as u8
            && self.parity.includes(week)
            && (self.weeks.is_empty() || self.weeks.contains(&week))
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PeriodTime {
    pub period: u8,
    pub start: NaiveTime,
    pub end: NaiveTime,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct BellSchedule {
    pub periods: Vec<PeriodTime>,
}

impl BellSchedule {
    pub fn period(&self, period: u8) -> Option<&PeriodTime> {
        self.periods.iter().find(|p| p.period == period)
    }
    pub fn for_course(&self, course: &Course) -> Result<(&PeriodTime, &PeriodTime)> {
        let first = *course
            .periods
            .iter()
            .min()
            .ok_or_else(|| anyhow!("课程没有节次"))?;
        let last = *course
            .periods
            .iter()
            .max()
            .ok_or_else(|| anyhow!("课程没有节次"))?;
        let start = self
            .period(first)
            .ok_or_else(|| anyhow!("未设置第 {first} 节时间"))?;
        let end = self
            .period(last)
            .ok_or_else(|| anyhow!("未设置第 {last} 节时间"))?;
        Ok((start, end))
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClassMeeting<'a> {
    pub course: &'a Course,
    pub date: NaiveDate,
    pub start: NaiveDateTime,
    pub end: NaiveDateTime,
}

pub fn courses_on<'a>(
    courses: &'a [Course],
    semester: &Semester,
    date: NaiveDate,
    bell: &BellSchedule,
) -> Result<Vec<ClassMeeting<'a>>> {
    let Some(week) = semester.week_on(date) else {
        return Ok(Vec::new());
    };
    let mut meetings = Vec::new();
    for course in courses.iter().filter(|c| c.occurs(date.weekday(), week)) {
        let (first, last) = bell.for_course(course)?;
        meetings.push(ClassMeeting {
            course,
            date,
            start: date.and_time(first.start),
            end: date.and_time(last.end),
        });
    }
    meetings.sort_by_key(|m| m.start);
    Ok(meetings)
}

pub fn next_meeting<'a>(
    courses: &'a [Course],
    semester: &Semester,
    bell: &BellSchedule,
    now: NaiveDateTime,
) -> Result<Option<ClassMeeting<'a>>> {
    for offset in 0..=i64::from(semester.weeks) * 7 {
        let date = now.date() + Duration::days(offset);
        for meeting in courses_on(courses, semester, date, bell)? {
            if meeting.end > now {
                return Ok(Some(meeting));
            }
        }
    }
    Ok(None)
}

/// Return whole minutes until the reminder should fire. `None` means the
/// meeting is already underway/finished or the lead time has elapsed.
pub fn reminder_minutes_before(
    start: NaiveDateTime,
    now: NaiveDateTime,
    lead_minutes: u16,
) -> Option<i64> {
    let fire_at = start - Duration::minutes(i64::from(lead_minutes));
    (fire_at > now).then(|| fire_at.signed_duration_since(now).num_minutes())
}

/// Import a WakeUp local backup/export JSON. Online share codes are deliberately
/// rejected: the official flow requires the WakeUp app's network-enabled import.
pub fn import_wakeup_json(input: &str) -> Result<Vec<Course>> {
    if (input.contains("WakeUp") && (input.contains("口令") || input.contains("来自WakeUp课程表")))
        || input.trim().starts_with("wakeup://")
    {
        bail!("这是 WakeUp 在线分享口令；请先在 WakeUp 中导出备份文件，再使用本地 JSON 导入。此工具不会调用在线分享接口");
    }
    let value: serde_json::Value =
        serde_json::from_str(input).context("WakeUp 导出不是有效 JSON")?;
    let value = if let Some(data) = value.get("data").and_then(serde_json::Value::as_str) {
        serde_json::from_str(data).context("WakeUp data 字段不是有效 JSON")?
    } else {
        value
    };
    let rows = value.get("courses").or_else(|| value.get("courseList"))
        .or_else(|| value.get("data").and_then(|d| d.get("courseList")))
        .and_then(serde_json::Value::as_array)
        .ok_or_else(|| anyhow!("未找到 courses/courseList。支持的格式为 WakeUp courseList JSON；其他结构请先转为通用 Excel 模板"))?;
    let mut result = Vec::new();
    for (index, row) in rows.iter().enumerate() {
        let name = field(
            row,
            &["name", "courseName", "course_name", "课程名", "课程名称"],
        )
        .ok_or_else(|| anyhow!("第 {} 条缺少课程名", index + 1))?
        .to_string();
        let weekday = number_field(row, &["weekday", "day", "weekDay", "星期", "周几"])
            .ok_or_else(|| anyhow!("第 {} 条缺少星期", index + 1))?;
        let start_node = number_field(row, &["startNode"]);
        let periods = if let Some(start) = start_node {
            let length = number_field(row, &["step"])
                .or_else(|| {
                    number_field(row, &["endNode"])
                        .map(|end| end.saturating_sub(start).saturating_add(1))
                })
                .ok_or_else(|| anyhow!("第 {} 条缺少 step/endNode", index + 1))?;
            if length == 0 || length > 32 || start > 32 {
                bail!("WakeUp 节次范围无效");
            }
            (start..start + length)
                .map(|p| u8::try_from(p).context("WakeUp 节次超出范围"))
                .collect::<Result<Vec<_>>>()?
        } else {
            number_list(row, &["periods", "sections", "section", "节次"])?
        };
        let weeks = number_list(row, &["weeks", "weekList", "stepWeekList", "周次"])?
            .into_iter()
            .collect();
        let parity = match (
            number_field(row, &["type"]),
            field(row, &["parity", "weekType", "单双周"])
                .unwrap_or("")
                .to_lowercase()
                .as_str(),
        ) {
            (Some(1), _) => WeekParity::Odd,
            (Some(2), _) => WeekParity::Even,
            (_, "odd" | "single" | "单周") => WeekParity::Odd,
            (_, "even" | "double" | "双周") => WeekParity::Even,
            _ => WeekParity::Every,
        };
        result.push(Course {
            name,
            teacher: field(row, &["teacher", "teacherName", "教师", "老师"])
                .unwrap_or("")
                .to_string(),
            room: field(row, &["room", "classroom", "classroomName", "教室"])
                .unwrap_or("")
                .to_string(),
            weekday: u8::try_from(weekday).context("星期超出范围")?,
            periods,
            weeks,
            parity,
        });
    }
    Ok(result)
}

/// Parse the documented community-observed `.wakeup_schedule` five-line JSON
/// backup layout. The official app does not publish this schema; malformed or
/// newer variants are rejected instead of being partially imported.
pub fn import_wakeup_backup(input: &str) -> Result<Vec<Course>> {
    if let Ok(courses) = import_wakeup_json(input) {
        return Ok(courses);
    }
    let lines: Vec<&str> = input
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .collect();
    if lines.len() < 3 {
        bail!("WakeUp 备份文件结构无效：至少需要元数据、课表信息和课程列表三行 JSON");
    }
    let table: serde_json::Value =
        serde_json::from_str(lines[1]).context("WakeUp 备份第 2 行课表信息无效")?;
    let courses: serde_json::Value =
        serde_json::from_str(lines[2]).context("WakeUp 备份第 3 行课程列表无效")?;
    let rows = courses
        .as_array()
        .or_else(|| {
            courses
                .get("courseList")
                .and_then(serde_json::Value::as_array)
        })
        .ok_or_else(|| anyhow!("WakeUp 备份课程列表不是数组"))?;
    let wrapper = serde_json::json!({ "tableName": table.get("tableName"), "startDate": table.get("startDate"), "courseList": rows });
    import_wakeup_json(&wrapper.to_string())
}

/// Read term metadata and bell times when present. The WakeUp website does not
/// publish the backup schema; this accepts the community-observed `startDate`
/// and `timeList` fields and rejects partial or unknown metadata.
pub fn wakeup_metadata(input: &str) -> Result<Option<(NaiveDate, BellSchedule)>> {
    let owned_lines: Vec<String> = input
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(str::to_string)
        .collect();
    let (table, time_list) = if let Ok(value) = serde_json::from_str::<serde_json::Value>(input) {
        let value = if let Some(data) = value.get("data").and_then(serde_json::Value::as_str) {
            serde_json::from_str(data).context("WakeUp data 字段不是有效 JSON")?
        } else {
            value
        };
        (value.clone(), value.get("timeList").cloned())
    } else {
        if owned_lines.len() < 4 {
            return Ok(None);
        }
        let table: serde_json::Value =
            serde_json::from_str(&owned_lines[1]).context("WakeUp 备份第 2 行课表信息无效")?;
        let time_list: serde_json::Value =
            serde_json::from_str(&owned_lines[3]).context("WakeUp 备份第 4 行作息表无效")?;
        (table, Some(time_list))
    };
    let start_value = table.get("startDate");
    if start_value.is_none() && time_list.is_none() {
        return Ok(None);
    }
    let start_raw = start_value
        .and_then(serde_json::Value::as_str)
        .ok_or_else(|| anyhow!("WakeUp metadata 有作息信息但缺少有效的 startDate"))?;
    let start_date = NaiveDate::parse_from_str(start_raw, "%Y-%m-%d")
        .or_else(|_| NaiveDate::parse_from_str(start_raw, "%Y/%m/%d"))
        .context("WakeUp startDate 必须是 YYYY-MM-DD")?;
    let entries = time_list
        .and_then(|value| value.as_array().cloned())
        .ok_or_else(|| anyhow!("WakeUp metadata 有 startDate 但缺少数组 timeList"))?;
    if entries.is_empty() {
        bail!("WakeUp timeList 为空");
    }
    let mut periods = Vec::with_capacity(entries.len());
    for (index, entry) in entries.iter().enumerate() {
        let period = number_field(entry, &["node", "period", "section", "节次"])
            .or_else(|| Some((index + 1) as u64))
            .and_then(|n| u8::try_from(n).ok())
            .ok_or_else(|| anyhow!("WakeUp timeList 第 {} 项节次无效", index + 1))?;
        let start = field(entry, &["startTime", "start", "beginTime"])
            .ok_or_else(|| anyhow!("WakeUp timeList 第 {} 项缺少 startTime", index + 1))?;
        let end = field(entry, &["endTime", "end", "finishTime"])
            .ok_or_else(|| anyhow!("WakeUp timeList 第 {} 项缺少 endTime", index + 1))?;
        periods.push(PeriodTime {
            period,
            start: parse_time(start)?,
            end: parse_time(end)?,
        });
    }
    Ok(Some((start_date, BellSchedule { periods })))
}

/// Import a WakeUp JSON or local backup and return schedule metadata alongside
/// courses so callers can apply the table atomically.
pub fn import_wakeup_table(
    input: &str,
) -> Result<(Vec<Course>, Option<NaiveDate>, Option<BellSchedule>)> {
    let courses = import_wakeup_backup(input)?;
    let metadata = wakeup_metadata(input)?;
    let (start_date, bell) = metadata
        .map(|(date, bell)| (Some(date), Some(bell)))
        .unwrap_or((None, None));
    Ok((courses, start_date, bell))
}

fn parse_time(value: &str) -> Result<NaiveTime> {
    NaiveTime::parse_from_str(value, "%H:%M:%S")
        .or_else(|_| NaiveTime::parse_from_str(value, "%H:%M"))
        .with_context(|| format!("无效的 WakeUp 时间: {value}"))
}

fn field<'a>(value: &'a serde_json::Value, keys: &[&str]) -> Option<&'a str> {
    keys.iter()
        .find_map(|key| value.get(*key).and_then(serde_json::Value::as_str))
}
fn number_field(value: &serde_json::Value, keys: &[&str]) -> Option<u64> {
    keys.iter().find_map(|key| {
        value
            .get(*key)
            .and_then(|v| v.as_u64().or_else(|| v.as_str()?.parse().ok()))
    })
}
fn number_list(value: &serde_json::Value, keys: &[&str]) -> Result<Vec<u8>> {
    let Some(found) = keys.iter().find_map(|key| value.get(*key)) else {
        return Ok(Vec::new());
    };
    let parsed: Vec<u64> = if let Some(array) = found.as_array() {
        array
            .iter()
            .filter_map(|v| v.as_u64().or_else(|| v.as_str()?.parse().ok()))
            .collect()
    } else if let Some(text) = found.as_str() {
        parse_int_ranges(text)?
    } else if let Some(number) = found.as_u64() {
        vec![number]
    } else {
        Vec::new()
    };
    parsed
        .into_iter()
        .map(|v| u8::try_from(v).map_err(|_| anyhow!("节次/周次超出范围")))
        .collect()
}
fn parse_int_ranges(text: &str) -> Result<Vec<u64>> {
    let mut out = Vec::new();
    for part in text
        .split([',', '，', ';', '；', ' '])
        .filter(|s| !s.is_empty())
    {
        let normalized = part.replace(['—', '–'], "-");
        if let Some((a, b)) = normalized.split_once('-') {
            let start: u64 = a.trim().parse().context("周次范围格式错误")?;
            let end: u64 = b.trim().parse().context("周次范围格式错误")?;
            if end < start || end - start > 32 {
                bail!("周次范围无效: {part}");
            }
            out.extend(start..=end);
        } else {
            out.push(normalized.parse().context("数字列表格式错误")?);
        }
    }
    Ok(out)
}

/// Import a WakeUp share text only when it embeds a local JSON payload. Bare
/// online codes receive a safe, actionable error.
pub fn import_wakeup_share_code(code: &str) -> Result<Vec<Course>> {
    if let Some((_, json)) = code.split_once('\n') {
        return import_wakeup_json(json.trim());
    }
    import_wakeup_json(code)
}

/// Import generic Chinese/English column-header spreadsheet exports. Unknown
/// layouts return an actionable error; no external school credentials are used.
pub fn import_excel(bytes: &[u8]) -> Result<Vec<Course>> {
    use calamine::{open_workbook_auto_from_rs, Reader};
    let mut workbook =
        open_workbook_auto_from_rs(Cursor::new(bytes.to_vec())).context("无法读取 Excel 文件")?;
    let range = workbook
        .worksheet_range_at(0)
        .ok_or_else(|| anyhow!("Excel 没有工作表"))??;
    let mut rows = range.rows();
    let headers: Vec<String> = rows
        .next()
        .ok_or_else(|| anyhow!("Excel 工作表为空"))?
        .iter()
        .map(|cell| cell.to_string().trim().to_lowercase())
        .collect();
    let find = |names: &[&str]| {
        headers
            .iter()
            .position(|h| names.iter().any(|n| h == n))
            .or_else(|| {
                headers
                    .iter()
                    .position(|h| names.iter().any(|n| h.contains(n)))
            })
    };
    let name_col =
        find(&["课程名称", "课程名", "课程", "course name", "course"]).ok_or_else(|| {
            anyhow!("无法识别课程名列。模板列名：课程名、教师、教室、星期、节次、周次、单双周")
        })?;
    let weekday_col = find(&["星期", "周几", "weekday", "day"]).ok_or_else(|| {
        anyhow!("无法识别星期列。模板列名：课程名、教师、教室、星期、节次、周次、单双周")
    })?;
    let periods_col = find(&["节次", "上课节次", "period", "section"]).ok_or_else(|| {
        anyhow!("无法识别节次列。请使用模板：课程名、教师、教室、星期、节次、周次、单双周")
    })?;
    let mut courses = Vec::new();
    for row in rows {
        let get = |idx: Option<usize>| {
            idx.and_then(|i| row.get(i))
                .map(ToString::to_string)
                .unwrap_or_default()
        };
        let name = get(Some(name_col)).trim().to_string();
        if name.is_empty() {
            continue;
        }
        let day = parse_weekday(&get(Some(weekday_col)))?;
        let periods = parse_int_ranges(&get(Some(periods_col)))?
            .into_iter()
            .map(|p| u8::try_from(p).context("节次超出范围"))
            .collect::<Result<Vec<_>>>()?;
        let weeks: BTreeSet<_> =
            parse_int_ranges(&get(find(&["周次", "weeks", "week"])).replace("周", ""))?
                .into_iter()
                .map(|n| u8::try_from(n).context("周次超出范围"))
                .collect::<Result<_>>()?;
        let parity_text = get(find(&["单双周", "week type", "parity"]));
        let parity = if parity_text.contains("单") || parity_text.eq_ignore_ascii_case("odd") {
            WeekParity::Odd
        } else if parity_text.contains("双") || parity_text.eq_ignore_ascii_case("even") {
            WeekParity::Even
        } else {
            WeekParity::Every
        };
        courses.push(Course {
            name,
            teacher: get(find(&["教师", "老师", "teacher"])),
            room: get(find(&["教室", "地点", "room", "location"])),
            weekday: day,
            periods,
            weeks,
            parity,
        });
    }
    if courses.is_empty() {
        bail!("Excel 中没有可导入的课程行");
    }
    Ok(courses)
}

fn parse_weekday(text: &str) -> Result<u8> {
    let s = text
        .trim()
        .to_lowercase()
        .replace("星期", "")
        .replace("周", "");
    match s.as_str() {
        "一" | "1" | "mon" | "monday" => Ok(1),
        "二" | "2" | "tue" | "tuesday" => Ok(2),
        "三" | "3" | "wed" | "wednesday" => Ok(3),
        "四" | "4" | "thu" | "thursday" => Ok(4),
        "五" | "5" | "fri" | "friday" => Ok(5),
        "六" | "6" | "sat" | "saturday" => Ok(6),
        "日" | "天" | "7" | "sun" | "sunday" => Ok(7),
        _ => bail!("无法识别星期：{text}"),
    }
}

fn weekday_from_iso(day: u8) -> Result<Weekday> {
    match day {
        1 => Ok(Weekday::Mon),
        2 => Ok(Weekday::Tue),
        3 => Ok(Weekday::Wed),
        4 => Ok(Weekday::Thu),
        5 => Ok(Weekday::Fri),
        6 => Ok(Weekday::Sat),
        7 => Ok(Weekday::Sun),
        _ => bail!("weekday 必须为 ISO 星期 1..=7"),
    }
}

pub const EXCEL_TEMPLATE: &str = "课程名,教师,教室,星期,节次,周次,单双周\n高等数学,张老师,教1-201,星期一,1-2,1-16,每周\n英语,李老师,外语楼302,星期三,3-4,1-16,单周\n";

pub fn export_ics(
    courses: &[Course],
    semester: &Semester,
    bell: &BellSchedule,
    lead_minutes: u16,
) -> Result<String> {
    export_ics_seasonal(courses, semester, bell, bell, None, lead_minutes)
}

/// Export each class occurrence with winter/summer bell times selected by date.
/// Explicit events preserve skipped weeks and can change times within a term.
/// With no `summer_from`, every event uses `winter` (the compatibility form).
pub fn export_ics_seasonal(
    courses: &[Course],
    semester: &Semester,
    winter: &BellSchedule,
    summer: &BellSchedule,
    summer_from: Option<NaiveDate>,
    lead_minutes: u16,
) -> Result<String> {
    let mut out = String::from(
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//study-mayon//CN\r\nCALSCALE:GREGORIAN\r\n",
    );
    for (idx, course) in courses.iter().enumerate() {
        course.validate(semester)?;
        let weeks: Vec<u8> = if course.weeks.is_empty() {
            (1..=semester.weeks)
                .filter(|w| course.parity.includes(*w))
                .collect()
        } else {
            course
                .weeks
                .iter()
                .copied()
                .filter(|w| course.parity.includes(*w))
                .collect()
        };
        if weeks.is_empty() {
            continue;
        }
        let first_day = weekday_from_iso(course.weekday)?;
        // Emit each occurrence explicitly. This preserves gaps in explicit week
        // sets and allows winter/summer bell changes within a term.
        for (event_index, event_week) in weeks.iter().enumerate() {
            let date = semester.date_for(*event_week, first_day)?;
            let bell = if summer_from.is_some_and(|start| date >= start) {
                summer
            } else {
                winter
            };
            let (first, last) = bell.for_course(course)?;
            out.push_str("BEGIN:VEVENT\r\n");
            out.push_str(&format!(
                "UID:study-mayon-{idx}-{event_index}@localhost\r\nDTSTAMP:19700101T000000Z\r\n"
            ));
            out.push_str(&format!(
                "DTSTART:{}T{}\r\n",
                date.format("%Y%m%d"),
                first.start.format("%H%M%S")
            ));
            out.push_str(&format!(
                "DTEND:{}T{}\r\n",
                date.format("%Y%m%d"),
                last.end.format("%H%M%S")
            ));
            out.push_str(&format!("SUMMARY:{}\r\n", ics_escape(&course.name)));
            if !course.room.is_empty() {
                out.push_str(&format!("LOCATION:{}\r\n", ics_escape(&course.room)));
            }
            if !course.teacher.is_empty() {
                out.push_str(&format!("DESCRIPTION:{}\r\n", ics_escape(&course.teacher)));
            }
            if lead_minutes > 0 {
                out.push_str(&format!("BEGIN:VALARM\r\nTRIGGER:-PT{lead_minutes}M\r\nACTION:DISPLAY\r\nDESCRIPTION:{}\r\nEND:VALARM\r\n", ics_escape(&course.name)));
            }
            out.push_str("END:VEVENT\r\n");
        }
    }
    out.push_str("END:VCALENDAR\r\n");
    Ok(out)
}

/// Parse standard ICS VEVENT entries, including DTSTART/DTEND and weekly RRULE.
/// Meeting times map to the nearest configured period start/end; when no match
/// exists, the event is assigned to a matching exact time or returns an error.
pub fn import_ics(input: &str, semester: &Semester, bell: &BellSchedule) -> Result<Vec<Course>> {
    let unfolded_text = input.replace("\r\n ", "").replace("\n ", "");
    let mut result = Vec::new();
    let mut event: HashMap<String, String> = HashMap::new();
    let mut in_event = false;
    let mut in_alarm = false;
    for line in unfolded_text.lines() {
        if line == "BEGIN:VEVENT" {
            event.clear();
            in_event = true;
            continue;
        }
        if in_event && line == "BEGIN:VALARM" {
            in_alarm = true;
            continue;
        }
        if in_event && line == "END:VALARM" {
            in_alarm = false;
            continue;
        }
        if line == "END:VEVENT" {
            let dtstart = event
                .iter()
                .find(|(k, _)| k.starts_with("DTSTART"))
                .map(|(_, v)| v)
                .ok_or_else(|| anyhow!("ICS 事件缺少 DTSTART"))?;
            let dtend = event
                .iter()
                .find(|(k, _)| k.starts_with("DTEND"))
                .map(|(_, v)| v)
                .ok_or_else(|| anyhow!("ICS 事件缺少 DTEND"))?;
            let start = parse_ics_datetime(dtstart)?;
            let end = parse_ics_datetime(dtend)?;
            let week = semester
                .week_on(start.date())
                .ok_or_else(|| anyhow!("ICS 首次日期不在学期内"))?;
            let (first, last) = bell
                .periods
                .iter()
                .filter(|p| p.start == start.time())
                .min_by_key(|p| p.period)
                .zip(
                    bell.periods
                        .iter()
                        .filter(|p| p.end == end.time())
                        .max_by_key(|p| p.period),
                )
                .ok_or_else(|| {
                    anyhow!("ICS 时间 {}–{} 未匹配作息表节次", start.time(), end.time())
                })?;
            if event.keys().any(|key| key.contains("TZID")) {
                bail!("暂不支持带 TZID 的 ICS；请导出浮动本地时间");
            }
            let rrule = event.get("RRULE").cloned().unwrap_or_default();
            if !rrule.is_empty() && !supported_weekly_rrule(&rrule) {
                bail!("不支持此 ICS RRULE：{rrule}");
            }
            if event
                .keys()
                .any(|key| key.starts_with("EXDATE") || key.starts_with("RDATE"))
            {
                bail!("暂不支持 ICS EXDATE/RDATE 例外日期");
            }
            let mut weeks: BTreeSet<u8> = if rrule.is_empty() {
                [week].into_iter().collect()
            } else {
                (week..=semester.weeks)
                    .filter(|w| WeekParity::Every.includes(*w))
                    .collect()
            };
            if let Some(until) = rrule
                .split(';')
                .find_map(|part| part.strip_prefix("UNTIL="))
            {
                let until_date = NaiveDate::parse_from_str(
                    until
                        .get(..8)
                        .ok_or_else(|| anyhow!("ICS UNTIL 日期无效"))?,
                    "%Y%m%d",
                )
                .context("ICS UNTIL 日期无效")?;
                weeks.retain(|w| {
                    semester
                        .date_for(*w, start.weekday())
                        .map(|d| d <= until_date)
                        .unwrap_or(false)
                });
            }
            let parity = if rrule.contains("INTERVAL=2") {
                if week % 2 == 0 {
                    WeekParity::Even
                } else {
                    WeekParity::Odd
                }
            } else {
                WeekParity::Every
            };
            let name = event
                .get("SUMMARY")
                .map(|v| ics_unescape(v))
                .unwrap_or_else(|| "未命名课程".to_string());
            result.push(Course {
                name,
                teacher: event
                    .get("DESCRIPTION")
                    .map(|v| ics_unescape(v))
                    .unwrap_or_default(),
                room: event
                    .get("LOCATION")
                    .map(|v| ics_unescape(v))
                    .unwrap_or_default(),
                weekday: start.weekday().number_from_monday() as u8,
                periods: (first.period..=last.period).collect(),
                weeks,
                parity,
            });
            event.clear();
            in_event = false;
            in_alarm = false;
            continue;
        }
        if let Some((key, value)) = line.split_once(':') {
            if in_event && !in_alarm {
                event.insert(key.to_string(), value.to_string());
            }
        }
    }
    Ok(coalesce_occurrences(result))
}

fn parse_ics_datetime(value: &str) -> Result<NaiveDateTime> {
    if value.ends_with('Z') {
        bail!("暂不支持 UTC `Z` 时间；请先转换为本地浮动时间再导入");
    }
    NaiveDateTime::parse_from_str(value, "%Y%m%dT%H%M%S")
        .or_else(|_| NaiveDateTime::parse_from_str(value, "%Y%m%dT%H%M"))
        .map_err(Into::into)
}

fn coalesce_occurrences(courses: Vec<Course>) -> Vec<Course> {
    let mut combined: Vec<Course> = Vec::new();
    for course in courses {
        if let Some(existing) = combined.iter_mut().find(|item| {
            item.name == course.name
                && item.teacher == course.teacher
                && item.room == course.room
                && item.weekday == course.weekday
                && item.periods == course.periods
                && item.parity == course.parity
        }) {
            existing.weeks.extend(course.weeks);
        } else {
            combined.push(course);
        }
    }
    combined
}
fn supported_weekly_rrule(rule: &str) -> bool {
    let mut freq = false;
    for part in rule.split(';') {
        if part == "FREQ=WEEKLY" {
            freq = true;
        } else if part == "INTERVAL=1" || part == "INTERVAL=2" || part.starts_with("UNTIL=") {
        } else {
            return false;
        }
    }
    freq
}
fn ics_escape(s: &str) -> String {
    s.replace('\\', "\\\\")
        .replace(';', "\\;")
        .replace(',', "\\,")
        .replace('\n', "\\n")
}
fn ics_unescape(s: &str) -> String {
    s.replace("\\n", "\n")
        .replace("\\,", ",")
        .replace("\\;", ";")
        .replace("\\\\", "\\")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn semester() -> Semester {
        Semester {
            start_date: NaiveDate::from_ymd_opt(2026, 9, 7).unwrap(),
            weeks: 16,
            kind: TermKind::Winter,
        }
    }
    fn bell() -> BellSchedule {
        BellSchedule {
            periods: (1..=4)
                .map(|p| PeriodTime {
                    period: p,
                    start: NaiveTime::from_hms_opt(8 + u32::from(p - 1) * 2, 0, 0).unwrap(),
                    end: NaiveTime::from_hms_opt(9 + u32::from(p - 1) * 2, 40, 0).unwrap(),
                })
                .collect(),
        }
    }

    #[test]
    fn semester_week_and_parity_follow_monday_based_weeks() {
        let sem = semester();
        assert_eq!(
            sem.week_on(NaiveDate::from_ymd_opt(2026, 9, 7).unwrap()),
            Some(1)
        );
        assert_eq!(
            sem.week_on(NaiveDate::from_ymd_opt(2026, 9, 13).unwrap()),
            Some(1)
        );
        assert_eq!(
            sem.week_on(NaiveDate::from_ymd_opt(2026, 9, 14).unwrap()),
            Some(2)
        );
        let non_monday = Semester {
            start_date: NaiveDate::from_ymd_opt(2026, 9, 9).unwrap(),
            ..sem.clone()
        };
        assert_eq!(
            non_monday.week_on(NaiveDate::from_ymd_opt(2026, 9, 7).unwrap()),
            Some(1)
        );
        assert_eq!(
            non_monday.week_on(NaiveDate::from_ymd_opt(2026, 9, 14).unwrap()),
            Some(2)
        );
        assert!(WeekParity::Odd.includes(3));
        assert!(!WeekParity::Odd.includes(4));
    }

    #[test]
    fn course_filter_and_next_meeting_respect_week_parity() {
        let sem = semester();
        let bell = bell();
        let course = Course {
            name: "英语".into(),
            teacher: String::new(),
            room: "A101".into(),
            weekday: 1,
            periods: vec![1, 2],
            weeks: BTreeSet::new(),
            parity: WeekParity::Even,
        };
        let monday = NaiveDate::from_ymd_opt(2026, 9, 7).unwrap();
        assert!(
            courses_on(std::slice::from_ref(&course), &sem, monday, &bell)
                .unwrap()
                .is_empty()
        );
        let now = monday.and_hms_opt(8, 0, 0).unwrap();
        assert_eq!(
            next_meeting(&[course], &sem, &bell, now)
                .unwrap()
                .unwrap()
                .date,
            monday + Duration::weeks(1)
        );
    }

    #[test]
    fn reminder_skips_when_notice_window_has_passed() {
        let start = NaiveDate::from_ymd_opt(2026, 9, 7)
            .unwrap()
            .and_hms_opt(9, 0, 0)
            .unwrap();
        assert_eq!(
            reminder_minutes_before(start, start - Duration::minutes(30), 10),
            Some(20)
        );
        assert_eq!(
            reminder_minutes_before(start, start - Duration::minutes(5), 10),
            None
        );
    }

    #[test]
    fn wakeup_json_fixture_and_online_code_error() {
        let raw = include_str!("../tests/fixtures/schedule-wakeup.json");
        let imported = import_wakeup_json(raw).unwrap();
        assert_eq!(imported.len(), 2);
        assert_eq!(imported[1].parity, WeekParity::Odd);
        assert!(import_wakeup_share_code("〖来自WakeUp课程表〗abc")
            .unwrap_err()
            .to_string()
            .contains("不会调用在线分享接口"));
    }

    #[test]
    fn wakeup_backup_fixture_uses_course_list_node_fields() {
        let raw = include_str!("../tests/fixtures/schedule-wakeup-backup.txt");
        let (imported, start_date, bell) = import_wakeup_table(raw).unwrap();
        assert_eq!(imported.len(), 1);
        assert_eq!(imported[0].periods, vec![2, 3]);
        assert_eq!(imported[0].weeks.len(), 16);
        assert_eq!(
            start_date,
            Some(NaiveDate::from_ymd_opt(2026, 9, 7).unwrap())
        );
        assert_eq!(
            bell.unwrap().period(1).unwrap().start,
            NaiveTime::from_hms_opt(8, 0, 0).unwrap()
        );
    }

    #[test]
    fn spreadsheet_template_and_headers_are_stable() {
        use base64::Engine;
        let fixture = base64::engine::general_purpose::STANDARD
            .decode(include_str!("../tests/fixtures/schedule-template.xlsx.b64").trim())
            .unwrap();
        let imported = import_excel(&fixture).unwrap();
        assert_eq!(imported.len(), 1);
        assert_eq!(imported[0].weekday, 1);
        assert_eq!(imported[0].periods, vec![1, 2]);
        assert!(EXCEL_TEMPLATE.starts_with("课程名,教师,教室,星期,节次,周次,单双周"));
    }

    #[test]
    fn calendar_round_trip_keeps_occurrence_and_meeting_time() {
        let sem = semester();
        let bell = bell();
        let course = Course {
            name: "线代,一班".into(),
            teacher: "李老师".into(),
            room: "教1-101".into(),
            weekday: 1,
            periods: vec![1, 2],
            weeks: [1, 3, 5].into_iter().collect(),
            parity: WeekParity::Odd,
        };
        let ics = export_ics(&[course], &sem, &bell, 15).unwrap();
        assert!(ics.contains("TRIGGER:-PT15M"));
        assert_eq!(ics.matches("BEGIN:VEVENT").count(), 3);
        assert!(!ics.contains("RRULE:"));
        let imported = import_ics(&ics, &sem, &bell).unwrap();
        assert_eq!(imported[0].name, "线代,一班");
        assert_eq!(imported[0].periods, vec![1, 2]);
        assert_eq!(imported[0].weeks, [1, 3, 5].into_iter().collect());
        assert_eq!(imported[0].teacher, "李老师");
    }

    #[test]
    fn unsupported_ics_timezone_is_rejected() {
        let sem = semester();
        let bell = bell();
        let raw = "BEGIN:VCALENDAR\nBEGIN:VEVENT\nDTSTART;TZID=Asia/Shanghai:20260907T080000\nDTEND;TZID=Asia/Shanghai:20260907T094000\nSUMMARY:课\nEND:VEVENT\nEND:VCALENDAR\n";
        assert!(import_ics(raw, &sem, &bell)
            .unwrap_err()
            .to_string()
            .contains("TZID"));
    }

    #[test]
    fn utc_ics_datetime_is_not_misread_as_local_time() {
        assert!(parse_ics_datetime("20260907T080000Z")
            .unwrap_err()
            .to_string()
            .contains("UTC"));
    }

    #[test]
    fn seasonal_calendar_export_splits_at_bell_change() {
        let sem = semester();
        let winter = bell();
        let summer = BellSchedule {
            periods: winter
                .periods
                .iter()
                .map(|p| PeriodTime {
                    period: p.period,
                    start: p.start + Duration::minutes(30),
                    end: p.end + Duration::minutes(30),
                })
                .collect(),
        };
        let course = Course {
            name: "课程".into(),
            teacher: String::new(),
            room: String::new(),
            weekday: 1,
            periods: vec![1],
            weeks: BTreeSet::new(),
            parity: WeekParity::Every,
        };
        let cutoff = sem.date_for(9, Weekday::Mon).unwrap();
        let ics = export_ics_seasonal(&[course], &sem, &winter, &summer, Some(cutoff), 0).unwrap();
        assert_eq!(ics.matches("BEGIN:VEVENT").count(), 16);
        assert!(!ics.contains("RRULE:"));
        assert!(ics.contains("DTSTART:20260907T080000"));
        assert!(ics.contains("DTSTART:20261102T083000"));
    }
    #[test]
    fn english_excel_weekday_does_not_shadow_weeks_column() {
        use base64::Engine;
        let bytes = base64::engine::general_purpose::STANDARD
            .decode(include_str!("../tests/fixtures/schedule-english.xlsx.b64").trim())
            .unwrap();
        let courses = import_excel(&bytes).unwrap();
        assert_eq!(courses[0].weekday, 1);
        assert!(courses[0].weeks.contains(&16));
        assert_eq!(courses[0].weeks.len(), 16);
    }
}
