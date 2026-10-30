use crate::{
    app::{self, Timetable},
    store::Store,
};
use anyhow::{bail, Context, Result};
use chrono::{Duration, Local, NaiveDateTime, NaiveTime};
use std::{
    path::Path,
    process::{Command, Stdio},
};

/// Earliest future deadline. Midnight/login bootstrap also repairs expired timers.
pub fn deadline(
    table: &Timetable,
    now: NaiveDateTime,
    reminder: NaiveTime,
    lead: i64,
) -> Result<NaiveDateTime> {
    let mut next = now.date().and_time(reminder);
    if next <= now {
        next += Duration::days(1);
    }
    for offset in 0..=1 {
        for m in table.today(now.date() + Duration::days(offset))? {
            let at = m.start - Duration::minutes(lead);
            if at > now && at < next {
                next = at;
            }
        }
    }
    Ok(next)
}
pub fn plan(store: &Store, table: &Timetable, root: &Path) -> Result<()> {
    if !enabled() {
        return Ok(());
    }
    let cfg = app::settings(store)?;
    let now = Local::now().naive_local();
    let at = deadline(
        table,
        now,
        NaiveTime::parse_from_str(&cfg.reminder, "%H:%M")?,
        cfg.before_minutes,
    )?;
    use std::hash::{Hash, Hasher};
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    crate::executable()?.hash(&mut hasher);
    let unit = format!(
        "study-next-{}-{:x}",
        at.and_utc().timestamp(),
        hasher.finish()
    );
    // Existing same-deadline timers are harmless; systemd won't replace an active unit.
    let result = Command::new("timeout")
        .args(["5", "systemd-run"])
        .args([
            "--user",
            "--quiet",
            "--collect",
            "--unit",
            &unit,
            "--timer-property=AccuracySec=1s",
            "--property=UMask=0077",
            "--on-calendar",
            &at.format("%Y-%m-%d %H:%M:%S").to_string(),
        ])
        .arg(crate::executable()?)
        .arg("--data-dir")
        .arg(root)
        .arg("remind")
        .stdin(Stdio::null())
        .output()
        .context("无法创建 transient user timer")?;
    if !result.status.success() {
        let err = String::from_utf8_lossy(&result.stderr);
        if !err.contains("already exists") {
            bail!("systemd-run：{}", err.trim());
        }
    }
    Ok(())
}
pub fn remind(store: &Store, table: &Timetable, root: &Path) -> Result<()> {
    if !enabled() {
        return Ok(());
    }
    let cfg = app::settings(store)?;
    let now = Local::now();
    let naive = now.naive_local();
    let mut notices = Vec::new();
    let vocab = naive
        .date()
        .and_time(NaiveTime::parse_from_str(&cfg.reminder, "%H:%M")?);
    if (0..=90).contains(&(naive - vocab).num_seconds())
        && !store.queue(now.timestamp(), &cfg)?.is_empty()
        && store.claim_notice(&format!("vocab-{}", naive.date()), now.timestamp())?
    {
        notices.push((
            "单词复习时间到了".to_string(),
            "你的学习队列还有待复习/新词，点此开始。".to_string(),
            "2",
        ));
    }
    for offset in 0..=1 {
        for m in table.today(naive.date() + Duration::days(offset))? {
            let at = m.start - Duration::minutes(cfg.before_minutes);
            if (0..=90).contains(&(naive - at).num_seconds())
                && store.claim_notice(
                    &format!("class-{}-{}-{}", m.start, m.course.name, m.course.room),
                    now.timestamp(),
                )?
            {
                notices.push((
                    format!("即将上课 · {}", m.course.name),
                    format!("{} · {} 开始", m.course.room, m.start.format("%H:%M")),
                    "4",
                ));
            }
        }
    }
    plan(store, table, root)?;
    for (title, body, page) in notices {
        let out = Command::new("timeout")
            .args([
                "30",
                "notify-send",
                "--app-name=Study",
                "--expire-time=20000",
                "--action=open=打开学习",
                "--wait",
                &title,
                &body,
            ])
            .stdin(Stdio::null())
            .output()?;
        if String::from_utf8_lossy(&out.stdout).trim() == "open" {
            // A window must outlive this transient notification service cgroup.
            let kitty = std::env::var_os("PATH")
                .and_then(|path| {
                    std::env::split_paths(&path)
                        .map(|dir| dir.join("kitty"))
                        .find(|p| p.is_file())
                })
                .context("找不到 kitty")?;
            let status = Command::new("systemd-run")
                .args([
                    "--user",
                    "--quiet",
                    "--collect",
                    "--property=Type=exec",
                    "--unit",
                    &format!(
                        "study-window-{}",
                        Local::now().timestamp_nanos_opt().unwrap_or_default()
                    ),
                    "--",
                ])
                .arg(kitty)
                .args(["--class", "study-mayon", "--title", "学习", "-e"])
                .arg(crate::executable()?)
                .arg("--data-dir")
                .arg(root)
                .args(["tui", "--page", page])
                .stdin(Stdio::null())
                .status()?;
            if !status.success() {
                bail!("无法启动独立学习窗口服务");
            }
        }
    }
    Ok(())
}

fn enabled() -> bool {
    let marker = std::env::var_os("XDG_CONFIG_HOME")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| {
            std::path::PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".config")
        })
        .join("study/reminders-enabled");
    let Ok(content) = std::fs::read_to_string(marker) else {
        return false;
    };
    content.trim() == "enabled"
        || crate::executable().is_ok_and(|exe| content.trim() == exe.to_string_lossy())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn daily_rollover() {
        let table = Timetable::default();
        let now =
            NaiveDateTime::parse_from_str("2026-10-30 21:00:00", "%Y-%m-%d %H:%M:%S").unwrap();
        assert_eq!(
            deadline(&table, now, NaiveTime::from_hms_opt(20, 0, 0).unwrap(), 10).unwrap(),
            now.date()
                .succ_opt()
                .unwrap()
                .and_hms_opt(20, 0, 0)
                .unwrap()
        );
    }
    #[test]
    fn class_deadline_and_previous_day_lead_time() {
        use crate::schedule::{Course, PeriodTime, WeekParity};
        let mut table = Timetable::default();
        table.semester.start_date = "2026-09-01".parse().unwrap();
        table.winter.periods = vec![PeriodTime {
            period: 1,
            start: NaiveTime::from_hms_opt(0, 5, 0).unwrap(),
            end: NaiveTime::from_hms_opt(0, 50, 0).unwrap(),
        }];
        table.summer = table.winter.clone();
        table.courses.push(Course {
            name: "实验".into(),
            teacher: String::new(),
            room: "A1".into(),
            weekday: 6,
            periods: vec![1],
            weeks: Default::default(),
            parity: WeekParity::Every,
        });
        let now = "2026-10-30T23:00:00".parse().unwrap();
        assert_eq!(
            deadline(&table, now, NaiveTime::from_hms_opt(20, 0, 0).unwrap(), 10).unwrap(),
            "2026-10-30T23:55:00".parse::<NaiveDateTime>().unwrap()
        );
    }
}
