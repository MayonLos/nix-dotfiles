use crate::{
    app::{self, Timetable},
    audio,
    schedule::{Course, WeekParity},
    store::{Card, Settings, Store},
};
use anyhow::{bail, Result};
use chrono::{Datelike, Duration, Local};
use crossterm::event::{
    self, Event, KeyCode as K, KeyEventKind, KeyModifiers, MouseButton, MouseEventKind,
};
use mayon_ui::{self as ui, theme::*};
use ratatui::{
    layout::{Constraint, Layout, Rect},
    style::{Modifier, Style},
    text::{Line, Span},
    widgets::{Paragraph, Wrap},
    Frame,
};
use std::{
    path::PathBuf,
    process::{Command, Stdio},
    sync::mpsc,
    time::{Duration as Wait, Instant},
};

struct Form {
    kind: FormKind,
    fields: Vec<(&'static str, String)>,
    at: usize,
}
enum FormKind {
    Word,
    Course(Option<usize>),
    Settings,
    Filter,
    Import,
}
struct View {
    page: usize,
    mode: usize,
    reveal: bool,
    answer: String,
    filter: String,
    wrong: bool,
    help: bool,
    selected: usize,
    week: u8,
    message: String,
    form: Option<Form>,
    card_start: Instant,
    cards: Vec<Card>,
    cfg: Settings,
    table: Timetable,
    dictionary: PathBuf,
}
const MODES: [&str; 4] = ["认识与否", "看释义拼写", "听音拼写", "选择题"];
const BOOKS: [(&str, &str); 6] = [
    ("cet4", "CET-4 大学英语四级"),
    ("cet6", "CET-6 大学英语六级"),
    ("ky", "考研英语"),
    ("ielts", "IELTS 雅思"),
    ("toefl", "TOEFL 托福"),
    ("gre", "GRE 研究生入学"),
];
impl View {
    fn refresh(&mut self, store: &Store) -> Result<()> {
        self.cards = store
            .queue(Local::now().timestamp(), &self.cfg)?
            .into_iter()
            .filter(|c| {
                (!self.wrong || c.lapses > 0)
                    && (c.word.word.contains(&self.filter) || c.word.meaning.contains(&self.filter))
            })
            .collect();
        Ok(())
    }
    fn current(&self) -> Option<&Card> {
        self.cards.first()
    }
    fn reset(&mut self) {
        self.answer.clear();
        self.reveal = false;
        self.card_start = Instant::now();
    }
    fn draw(&self, f: &mut Frame, store: &Store) {
        let now = Local::now();
        let title = format!(
            " STUDY / 学习                                      {}  ·  第 {} 周",
            now.format("%m月%d日 %H:%M"),
            self.table
                .semester
                .week_on(now.date_naive())
                .map_or("—".into(), |w| w.to_string())
        );
        let area = ui::chrome(
            f,
            &title,
            &["今日", "背单词", "统计", "课表", "词书/设置"],
            self.page,
            "1–5 切页  m 模式  Space 翻面  z/x/c/v 评分  a 剪贴板  / 过滤  ? 帮助  q 退出",
            &self.message,
        );
        match self.page {
            0 => self.today(f, area, store),
            1 => self.vocab(f, area, store),
            2 => self.stats(f, area, store),
            3 => self.week(f, area),
            _ => self.books(f, area, store),
        }
        if self.help {
            ui::help(f,"1–5 切页 · Tab 下一页 · / 过滤 · q 退出\n背单词：Space/Enter 翻面；z 重来 x 困难 c 良好 v 简单\nm 切换认识/释义拼写/听音拼写/选择题；p 发音；w 错词\n拼写：输入英文后 Enter 检查；选择题：↑↓ 后 Enter 检查\na 将 wl-paste 单词加入生词本（不读取剪贴板历史）；n 手动新增\n课表：←/→ 或 [/] 切周；j/k 选择课程；e 编辑；d 删除\n词书：j/k 选择；Enter 导入；i 导入文件；s 编辑设置\n表单：Tab/Shift+Tab 换字段；Enter 保存；Esc 取消\n发音、剪贴板在后台执行；导入请只打开可信本地文件。");
        }
        if let Some(form) = &self.form {
            let title = match form.kind {
                FormKind::Word => " 新增单词 ",
                FormKind::Course(_) => " 课程表单 ",
                FormKind::Settings => " 学习与学期设置 ",
                FormKind::Filter => " 过滤 ",
                FormKind::Import => " 导入单词 / 课表文件 ",
            };
            let h = (form.fields.len() * 2 + 4) as u16;
            let a = ui::centered(f.area(), 78, h);
            f.render_widget(ratatui::widgets::Clear, a);
            let mut lines = Vec::new();
            for (i, (label, value)) in form.fields.iter().enumerate() {
                lines.push(Line::from(Span::styled(
                    format!(
                        " {} {label}: {}{}",
                        if i == form.at { "▏" } else { " " },
                        value,
                        if i == form.at { "▏" } else { "" }
                    ),
                    if i == form.at {
                        ui::base().bg(SELECTION).fg(BLUE)
                    } else {
                        ui::base()
                    },
                )));
                lines.push(Line::raw(""));
            }
            lines.push(Line::from(ui::muted(" Tab 换字段 · Enter 保存 · Esc 取消")));
            f.render_widget(
                Paragraph::new(lines)
                    .style(ui::base())
                    .block(ui::block(title, true))
                    .wrap(Wrap { trim: false }),
                a,
            );
        }
    }
    fn today(&self, f: &mut Frame, a: Rect, store: &Store) {
        let today = Local::now().date_naive();
        let stats = store.stats(today).unwrap_or_default();
        let rows = Layout::vertical([Constraint::Length(6), Constraint::Min(6)]).split(a);
        let cols = Layout::horizontal([Constraint::Percentage(50), Constraint::Percentage(50)])
            .split(rows[0]);
        panel(
            f,
            cols[0],
            " 今日学习 ",
            vec![
                Line::from(vec![
                    ui::blue(format!("  {}", self.cards.len())),
                    Span::raw(" 张待学习   "),
                    ui::muted(format!("目标留存 {:.0}%", self.cfg.retention * 100.)),
                ]),
                Line::raw(format!(
                    "  今日完成 {} 次 · 连续打卡 {} 天",
                    stats.daily.get(&today).unwrap_or(&0),
                    stats.streak
                )),
                Line::from(ui::muted("  按 2 开始一轮专注学习")),
            ],
        );
        let next = self
            .table
            .next_json(Local::now().naive_local())
            .unwrap_or_default();
        let next_lines = if next.is_null() {
            vec![
                Line::raw("  今日已无课 · 留一点时间给自己"),
                Line::from(ui::muted("  按 4 查看整周课表")),
            ]
        } else {
            vec![
                Line::from(ui::blue(format!(
                    "  {} · {}",
                    next["course"].as_str().unwrap_or(""),
                    next["room"].as_str().unwrap_or("")
                ))),
                Line::raw(format!(
                    "  {} · {} 分钟",
                    if next["status"] == "in_class" {
                        "正在上课"
                    } else {
                        "距下一节"
                    },
                    next["remaining_minutes"]
                )),
            ]
        };
        panel(f, cols[1], " 下一节课 ", next_lines);
        let meetings = self.table.today(today).unwrap_or_default();
        let data = meetings
            .iter()
            .filter(|m| m.course.name.contains(&self.filter))
            .map(|m| {
                vec![
                    format!("{}–{}", m.start.format("%H:%M"), m.end.format("%H:%M")),
                    m.course.name.clone(),
                    m.course.room.clone(),
                    m.course.teacher.clone(),
                ]
            })
            .collect();
        ui::table(
            f,
            rows[1],
            " 今日课程 · 课表会随周次自动更新 ",
            vec!["时间", "课程", "教室", "老师"],
            data,
            &[
                Constraint::Length(13),
                Constraint::Percentage(35),
                Constraint::Percentage(30),
                Constraint::Min(5),
            ],
            self.selected,
        );
    }
    fn vocab(&self, f: &mut Frame, a: Rect, store: &Store) {
        let rows = Layout::vertical([
            Constraint::Length(3),
            Constraint::Min(9),
            Constraint::Length(4),
        ])
        .split(a);
        panel(
            f,
            rows[0],
            " 学习队列 ",
            vec![Line::from(vec![
                ui::blue(format!(" {}  ", MODES[self.mode])),
                ui::muted(format!(
                    "{} 张 · 新词上限 {} / 复习上限 {}  {}",
                    self.cards.len(),
                    self.cfg.new_limit,
                    self.cfg.review_limit,
                    if self.wrong {
                        "· 错词本"
                    } else {
                        "· FSRS 6"
                    }
                )),
            ])],
        );
        let Some(c) = self.current() else {
            panel(
                f,
                rows[1],
                " 今日任务已完成 ",
                vec![
                    Line::raw(""),
                    Line::from(ui::blue("  学习是一点一点积累的。")),
                    Line::raw("  到期卡片会自动进入队列；按 5 选择词书，n 添加单词。"),
                    Line::from(ui::muted(
                        "  / 清空过滤 · w 切换错词本 · 每日上限可在设置中调整",
                    )),
                ],
            );
            return;
        };
        let mut lines = vec![
            Line::from(ui::muted(format!(
                "  {} · {}",
                c.word.book,
                if c.last == 0 { "新词" } else { "复习" }
            ))),
            Line::raw(""),
            Line::raw(""),
        ];
        if self.mode == 0 || self.mode == 3 || self.reveal {
            lines.push(Line::from(Span::styled(
                format!("  {}", c.word.word),
                Style::default().fg(BRIGHTFG).add_modifier(Modifier::BOLD),
            )));
            lines.push(Line::from(ui::muted(format!(
                "  /{}/    p 发音",
                c.word.phonetic
            ))));
        }
        if self.mode == 1 && !self.reveal {
            lines.push(Line::from(ui::blue(format!("  {}", c.word.meaning))));
        }
        if self.mode == 2 && !self.reveal {
            lines.push(Line::from(ui::blue(
                "  听音拼写 · 按 Alt+p 播放，再输入单词",
            )));
        }
        lines.push(Line::raw(""));
        if (self.mode == 1 || self.mode == 2) && !self.reveal {
            lines.push(Line::from(Span::styled(
                format!("  ▏{}▏", self.answer),
                ui::base().bg(SELECTION),
            )));
            lines.push(Line::from(ui::muted(
                "  Enter 检查 · 不会时 Space 显示答案",
            )));
        }
        if self.mode == 3 && !self.reveal {
            let options = choices(c, store);
            for (i, opt) in options.iter().enumerate() {
                lines.push(Line::from(Span::styled(
                    format!(
                        "  {} {}. {}",
                        if self.selected % 4 == i { "▏" } else { " " },
                        i + 1,
                        opt
                    ),
                    if self.selected % 4 == i {
                        ui::base().fg(BLUE).bg(SELECTION)
                    } else {
                        ui::base()
                    },
                )));
            }
        }
        if self.reveal {
            lines.extend([
                Line::from(ui::blue(format!("  {}", c.word.meaning))),
                Line::raw(format!("  {}", c.word.definition.replace("\\n", "; "))),
                Line::raw(""),
                Line::from(ui::muted("  CLOZE / 例句")),
                Line::raw(format!("  {}", cloze(&c.word.example, &c.word.word))),
                Line::raw(""),
                Line::from(ui::muted("  词根 · 词缀 · 派生")),
                Line::raw(format!(
                    "  {}",
                    if c.word.roots.is_empty() {
                        "词库未提供；可在导入文件中补充"
                    } else {
                        &c.word.roots
                    }
                )),
            ]);
        } else if self.mode == 0 {
            lines.push(Line::from(ui::muted("  想起它的含义了吗？Space 显示释义")));
        }
        panel(f, rows[1], " 学习卡片 ", lines);
        panel(
            f,
            rows[2],
            " 回想后再评分 ",
            vec![
                Line::from(vec![
                    Span::styled("  z 重来    ", Style::default().fg(RED)),
                    Span::styled("x 困难    ", Style::default().fg(YELLOW)),
                    Span::styled("c 良好    ", Style::default().fg(GREEN)),
                    ui::blue("v 简单"),
                ]),
                Line::from(ui::muted(
                    "  FSRS 会根据你的评分调整下一次复习时间 · 先翻面才能评分",
                )),
            ],
        );
    }
    fn stats(&self, f: &mut Frame, a: Rect, store: &Store) {
        let today = Local::now().date_naive();
        let s = store.stats(today).unwrap_or_default();
        let rows = Layout::vertical([
            Constraint::Length(5),
            Constraint::Length(13),
            Constraint::Min(5),
        ])
        .split(a);
        panel(
            f,
            rows[0],
            " 学习概览 ",
            vec![
                Line::from(ui::blue(format!(
                    "  累计 {} 次   ·   连续 {} 天   ·   学习 {} 分钟",
                    s.count, s.streak, s.minutes
                ))),
                Line::from(ui::muted(format!(
                    "  回想成功率 {:.1}%（评分 > 重来 / 总复习次数） · 目标留存 {:.0}%",
                    if s.count == 0 {
                        0.
                    } else {
                        s.remembered as f32 / s.count as f32 * 100.
                    },
                    self.cfg.retention * 100.
                ))),
                Line::from(ui::muted(format!(
                    "  模型估计当前留存 {} · 学习时段：早 {} / 午 {} / 晚 {} 次",
                    if s.retention > 0. {
                        format!("{:.1}%", s.retention * 100.)
                    } else {
                        "—".into()
                    },
                    s.hours[..12].iter().sum::<u32>(),
                    s.hours[12..18].iter().sum::<u32>(),
                    s.hours[18..].iter().sum::<u32>()
                ))),
            ],
        );
        let mut lines = vec![
            Line::from(ui::muted(
                "           12 周前                                        本周",
            )),
            Line::raw(""),
        ];
        let monday = today
            - Duration::days(today.weekday().num_days_from_monday() as i64)
            - Duration::weeks(11);
        for day in 0..7 {
            let mut spans = vec![ui::muted(format!(
                "  {}  ",
                ["一", "二", "三", "四", "五", "六", "日"][day]
            ))];
            for week in 0..12 {
                let d = monday + Duration::days(week * 7 + day as i64);
                let n = *s.daily.get(&d).unwrap_or(&0);
                let color = match n {
                    0 => SURFACE,
                    1..=5 => SELECTION,
                    6..=12 => BLUE,
                    _ => GREEN,
                };
                spans.push(Span::styled(
                    if d > today { "··" } else { "  " },
                    Style::default().bg(color).fg(MUTED),
                ));
                spans.push(Span::raw("  "));
            }
            lines.push(Line::from(spans));
        }
        lines.push(Line::raw(""));
        lines.push(Line::from(ui::muted(
            "       少  ░  ▒  ▓  多      每格代表一天 · 按当地日期统计",
        )));
        panel(f, rows[1], " 学习热力图 ", lines);
        let inner = ui::block(" 未来 7 天复习预测 · 已排期，逾期计入今天 ", false).inner(rows[2]);
        f.render_widget(
            ui::block(" 未来 7 天复习预测 · 已排期，逾期计入今天 ", false),
            rows[2],
        );
        let columns = Layout::horizontal([Constraint::Fill(1); 7]).split(inner);
        for (i, n) in s.forecast.iter().enumerate() {
            let date = (today + Duration::days(i as i64))
                .format("%m/%d")
                .to_string();
            f.render_widget(
                Paragraph::new(vec![
                    Line::from(ui::muted(date)),
                    Line::from(ui::blue(format!("{n} 次"))),
                ])
                .style(ui::base()),
                columns[i],
            );
        }
    }

    fn week(&self, f: &mut Frame, a: Rect) {
        let rows = Layout::vertical([
            Constraint::Length(3),
            Constraint::Min(5),
            Constraint::Length(5),
        ])
        .split(a);
        panel(
            f,
            rows[0],
            " 周课表 ",
            vec![Line::from(ui::blue(format!(
                "  第 {} 周 · ←/→ 切周 · n 新增 · j/k 选择 · e 编辑 · d 删除",
                self.week
            )))],
        );
        let inner = ui::block("", false).inner(rows[1]);
        f.render_widget(ui::block("", false), rows[1]);
        let cols = Layout::horizontal(
            std::iter::once(Constraint::Length(9)).chain((0..7).map(|_| Constraint::Fill(1))),
        )
        .split(inner);
        let today = Local::now().date_naive();
        let now = Local::now().time();
        let bell = self.table.bell(today);
        let height = (inner.height.saturating_sub(2) / bell.periods.len().max(1) as u16).max(1);
        for day in 0..7 {
            let date = self
                .table
                .semester
                .date_for(self.week, chrono::Weekday::try_from(day).unwrap())
                .unwrap_or(today);
            let color = if date == today { BLUE } else { MUTED };
            f.render_widget(
                Paragraph::new(format!(
                    "{} {}",
                    ["周一", "周二", "周三", "周四", "周五", "周六", "周日"][day as usize],
                    date.format("%d")
                ))
                .style(ui::base().fg(color)),
                Rect::new(
                    cols[day as usize + 1].x,
                    inner.y,
                    cols[day as usize + 1].width,
                    1,
                ),
            );
            for (i, p) in bell.periods.iter().enumerate() {
                let y = inner.y + 2 + i as u16 * height;
                if y >= inner.bottom() {
                    break;
                }
                let cell = Rect::new(
                    cols[day as usize + 1].x,
                    y,
                    cols[day as usize + 1].width.saturating_sub(1),
                    height.min(inner.bottom() - y),
                );
                let matches: Vec<_> = self
                    .table
                    .courses
                    .iter()
                    .enumerate()
                    .filter(|(_, c)| {
                        c.occurs(date.weekday(), self.week)
                            && c.periods.contains(&p.period)
                            && c.name.contains(&self.filter)
                    })
                    .collect();
                let active = date == today && now >= p.start && now < p.end;
                let mut lines = Vec::new();
                for (index, c) in matches {
                    let color = [BLUE, GREEN, CYAN, YELLOW][index % 4];
                    let text = if height > 1 {
                        format!("{}\n{}", c.name, c.room)
                    } else if c.periods.iter().min() == Some(&p.period) {
                        c.name.clone()
                    } else {
                        c.room.clone()
                    };
                    lines.extend(
                        text.lines()
                            .map(|s| {
                                Line::from(Span::styled(
                                    clip(s, cell.width as usize),
                                    Style::default().fg(color),
                                ))
                            })
                            .collect::<Vec<_>>(),
                    );
                }
                f.render_widget(
                    Paragraph::new(lines).style(ui::base().bg(if active { SELECTION } else { BG })),
                    cell,
                );
            }
        }
        for (i, p) in bell.periods.iter().enumerate() {
            let y = inner.y + 2 + i as u16 * height;
            if y >= inner.bottom() {
                break;
            }
            f.render_widget(
                Paragraph::new(format!("{:02} {}", p.period, p.start.format("%H:%M"))).style(
                    ui::base().fg(if now >= p.start && now < p.end {
                        BLUE
                    } else {
                        MUTED
                    }),
                ),
                Rect::new(cols[0].x, y, cols[0].width, height.min(inner.bottom() - y)),
            );
        }

        if let Some(c) = self
            .table
            .courses
            .get(self.selected % self.table.courses.len().max(1))
        {
            panel(
                f,
                rows[2],
                " 已选课程 ",
                vec![
                    Line::from(ui::blue(format!(
                        "  {} · {} · {}",
                        c.name, c.room, c.teacher
                    ))),
                    Line::from(ui::muted(format!(
                        "  星期 {} · {:?} 节 · {} · e 编辑这门课",
                        c.weekday,
                        c.periods,
                        match c.parity {
                            WeekParity::Every => "每周",
                            WeekParity::Odd => "单周",
                            WeekParity::Even => "双周",
                        }
                    ))),
                ],
            );
        } else {
            panel(
                f,
                rows[2],
                " 尚无课程 ",
                vec![Line::raw("  n 手动新增 · i 导入 ICS / WakeUp / Excel")],
            );
        }
    }
    fn books(&self, f: &mut Frame, a: Rect, store: &Store) {
        if self.wrong {
            let cards = store.cards(&self.filter, true).unwrap_or_default();
            ui::table(
                f,
                a,
                " 错词本 · 全部历史错词 · w 返回词书 · 到期后在 2 复习 ",
                vec!["单词", "释义", "重来", "下次复习"],
                cards
                    .iter()
                    .map(|c| {
                        vec![
                            c.word.word.clone(),
                            c.word.meaning.clone(),
                            c.lapses.to_string(),
                            chrono::DateTime::from_timestamp(c.due, 0)
                                .map(|t| t.with_timezone(&Local).format("%m/%d %H:%M").to_string())
                                .unwrap_or_default(),
                        ]
                    })
                    .collect(),
                &[
                    Constraint::Percentage(24),
                    Constraint::Percentage(40),
                    Constraint::Length(5),
                    Constraint::Min(10),
                ],
                self.selected.min(cards.len().saturating_sub(1)),
            );
            return;
        }
        let rows = Layout::vertical([Constraint::Min(10), Constraint::Length(9)]).split(a);
        ui::table(
            f,
            rows[0],
            " 词书 · Enter 加入学习库 · w 错词本 ",
            vec!["词书", "来源 / 状态"],
            BOOKS
                .iter()
                .map(|(tag, name)| vec![name.to_string(), format!("ECDICT · MIT · {tag}")])
                .collect(),
            &[Constraint::Percentage(50), Constraint::Min(15)],
            self.selected % 6,
        );
        let count = store.cards("", false).map(|c| c.len()).unwrap_or(0);
        panel(
            f,
            rows[1],
            " 设置 · s 编辑 · i 导入 ",
            vec![
                Line::raw(format!(
                    "  当前词库 {count} 词 · 新词 {}/天 · 复习 {}/天",
                    self.cfg.new_limit, self.cfg.review_limit
                )),
                Line::raw(format!(
                    "  留存目标 {:.0}% · 发音 {} · 背词提醒 {}",
                    self.cfg.retention * 100.,
                    self.cfg.audio,
                    self.cfg.reminder
                )),
                Line::raw(format!(
                    "  学期开始 {} · {} 周 · 上课前 {} 分钟提醒",
                    self.table.semester.start_date,
                    self.table.semester.weeks,
                    self.cfg.before_minutes
                )),
                Line::from(ui::muted(
                    "  CSV / TXT / legacy Anki apkg · ICS / WakeUp 备份 / Excel",
                )),
                Line::from(ui::muted(
                    "  英文释义和派生来自 ECDICT；例句缺失时明确留空。",
                )),
                Line::from(ui::muted(
                    "  FSRS 参数优化：study optimize（至少 400 条复习样本）",
                )),
            ],
        );
    }
}
fn panel(f: &mut Frame, a: Rect, title: &str, lines: Vec<Line<'static>>) {
    f.render_widget(
        Paragraph::new(lines)
            .style(ui::base())
            .block(ui::block(title, false))
            .wrap(Wrap { trim: false }),
        a,
    );
}
fn choices(c: &Card, store: &Store) -> Vec<String> {
    let mut opts = store
        .cards("", false)
        .unwrap_or_default()
        .into_iter()
        .filter(|x| x.word.meaning != c.word.meaning && !x.word.meaning.is_empty())
        .take(3)
        .map(|c| c.word.meaning)
        .collect::<Vec<_>>();
    while opts.len() < 3 {
        opts.push(format!("（词库不足，备选项 {}）", opts.len() + 1));
    }
    opts.insert(c.id.rem_euclid(4) as usize, c.word.meaning.clone());
    opts
}
fn cloze(text: &str, word: &str) -> String {
    if text.is_empty() {
        return "暂无例句；可通过 CSV 导入自编例句".into();
    }
    let lower = text.to_ascii_lowercase();
    let word_lower = word.to_ascii_lowercase();
    let mut out = String::new();
    let mut last = 0;
    for (start, _) in lower.match_indices(&word_lower) {
        if text.is_char_boundary(start) && text.is_char_boundary(start + word.len()) {
            out.push_str(&text[last..start]);
            out.push_str("_____");
            last = start + word.len();
        }
    }
    out.push_str(&text[last..]);
    out
}

pub fn run(store: &mut Store, page: usize, dictionary: PathBuf, mode: usize) -> Result<()> {
    let cfg = app::settings(store)?;
    let table: Timetable = store.get("timetable")?;
    table.validate()?;
    let mut v = View {
        page: page.min(4),
        mode: mode.min(3),
        reveal: false,
        answer: String::new(),
        filter: String::new(),
        wrong: false,
        help: false,
        selected: 0,
        week: table
            .semester
            .week_on(Local::now().date_naive())
            .unwrap_or(1),
        message: "每天一点，保持好奇。  ? 查看键位".into(),
        form: None,
        card_start: Instant::now(),
        cards: Vec::new(),
        cfg,
        table,
        dictionary,
    };
    v.refresh(store)?;
    let _background = BackgroundGuard::new()?;
    let (mut terminal, _guard) = ui::terminal()?;
    let mut refreshed = Instant::now();
    let (tx, rx) = mpsc::channel::<String>();
    let mut job = None::<std::thread::JoinHandle<()>>;
    loop {
        while let Ok(msg) = rx.try_recv() {
            v.message = msg;
        }
        terminal.draw(|f| v.draw(f, store))?;
        if refreshed.elapsed() >= Wait::from_secs(1) {
            let old = v.current().map(|c| c.id);
            v.refresh(store)?;
            if old != v.current().map(|c| c.id) {
                v.reset();
            }
            refreshed = Instant::now();
        }
        if !event::poll(Wait::from_millis(200))? {
            continue;
        }
        let ev = event::read()?;
        if let Event::Mouse(m) = ev {
            match m.kind {
                MouseEventKind::Down(MouseButton::Left) if m.row == 1 || m.row == 2 => {
                    let mut left = 1u16;
                    for (i, label) in ["今日", "背单词", "统计", "课表", "词书/设置"]
                        .iter()
                        .enumerate()
                    {
                        let width = unicode_width::UnicodeWidthStr::width(*label) as u16 + 6;
                        if m.column >= left && m.column < left + width {
                            v.page = i;
                            v.selected = 0;
                            break;
                        }
                        left += width;
                    }
                }
                MouseEventKind::ScrollDown => v.selected = v.selected.saturating_add(1),
                MouseEventKind::ScrollUp => v.selected = v.selected.saturating_sub(1),
                _ => {}
            }
            continue;
        }
        let Event::Key(key) = ev else {
            continue;
        };
        if key.kind != KeyEventKind::Press {
            continue;
        }
        if key.code == K::Char('c') && key.modifiers.contains(KeyModifiers::CONTROL) {
            break;
        }
        if let Some(form) = v.form.as_mut() {
            match key.code {
                K::Esc => v.form = None,
                K::Tab => form.at = (form.at + 1) % form.fields.len(),
                K::BackTab => form.at = (form.at + form.fields.len() - 1) % form.fields.len(),
                K::Backspace => {
                    form.fields[form.at].1.pop();
                }
                K::Char(c) => form.fields[form.at].1.push(c),
                K::Enter => {
                    let form = v.form.take().unwrap();
                    match save_form(&mut v, store, &form) {
                        Ok(()) => {
                            v.refresh(store)?;
                        }
                        Err(e) => {
                            v.message = format!("无法保存：{e:#}");
                            v.form = Some(form);
                        }
                    }
                }
                _ => {}
            }
            continue;
        }
        if v.help {
            if matches!(key.code, K::Esc | K::Char('?') | K::Char('q')) {
                v.help = false;
            }
            continue;
        }
        if v.page == 1 && (v.mode == 1 || v.mode == 2) && !v.reveal {
            match key.code {
                K::Char(c) if c.is_ascii_alphabetic() || c == '\'' || c == '-' => {
                    if c == 'p' && key.modifiers.contains(KeyModifiers::ALT) {
                    } else {
                        v.answer.push(c);
                        continue;
                    }
                }
                K::Backspace => {
                    v.answer.pop();
                    continue;
                }
                K::Enter => {
                    if let Some(c) = v.current() {
                        v.message = if c.word.word.eq_ignore_ascii_case(v.answer.trim()) {
                            "拼写正确 · 请按 z/x/c/v 评价回想难度".into()
                        } else {
                            format!("拼写需再练习：{} · 建议 z 重来", c.word.word)
                        };
                        v.reveal = true;
                    }
                    continue;
                }
                K::Esc => {
                    v.reveal = true;
                    continue;
                }
                _ => {}
            }
        }
        match key.code {
            K::Char('q') => break,
            K::Char('?') => v.help = true,
            K::Char(c @ '1'..='5') => {
                v.page = c as usize - '1' as usize;
                v.selected = 0;
            }
            K::Tab => {
                v.page = (v.page + 1) % 5;
                v.selected = 0;
            }
            K::Char('/') => {
                v.form = Some(Form {
                    kind: FormKind::Filter,
                    fields: vec![("关键词（空白清除）", v.filter.clone())],
                    at: 0,
                })
            }
            K::Char('m') if v.page == 1 => {
                v.mode = (v.mode + 1) % 4;
                v.reset();
                v.message = format!("{} · 听音使用 Alt+p（拼写模式）", MODES[v.mode]);
            }
            K::Char('w') if v.page == 1 || v.page == 4 => {
                v.wrong = !v.wrong;
                v.refresh(store)?;
                v.reset();
            }
            K::Char(' ') if v.page == 1 => v.reveal = true,
            K::Enter if v.page == 1 => {
                if v.mode == 3 && !v.reveal {
                    if let Some(c) = v.current() {
                        v.message = if v.selected % 4 == c.id.rem_euclid(4) as usize {
                            "选择正确 · 请评分".into()
                        } else {
                            "选择错误 · 建议 z 重来".into()
                        };
                    }
                }
                v.reveal = true;
            }
            K::Char(c @ ('z' | 'x' | 'c' | 'v')) if v.page == 1 && v.reveal => {
                if let Some(card) = v.current() {
                    let rating = match c {
                        'z' => 1,
                        'x' => 2,
                        'c' => 3,
                        _ => 4,
                    };
                    let due = store.rate(
                        card,
                        rating,
                        Local::now().timestamp(),
                        v.card_start.elapsed().as_secs().min(3600) as u32,
                        &v.cfg,
                    )?;
                    v.message = format!(
                        "已记录 · 下次复习 {}",
                        chrono::DateTime::from_timestamp(due, 0)
                            .unwrap()
                            .with_timezone(&Local)
                            .format("%m月%d日 %H:%M")
                    );
                    v.refresh(store)?;
                    v.reset();
                }
            }
            K::Char('p') if v.page == 1 && job.as_ref().is_none_or(|j| j.is_finished()) => {
                if let Some(c) = v.current() {
                    let word = c.word.word.clone();
                    let provider = v.cfg.audio.clone();
                    let root = crate::DATA_ROOT.get().unwrap().clone();
                    let tx = tx.clone();
                    job = Some(std::thread::spawn(move || {
                        let msg = audio::speak(&word, &provider, &root)
                            .map(|_| "发音已播放".into())
                            .unwrap_or_else(|e| format!("发音：{e:#}"));
                        let _ = tx.send(msg);
                    }));
                    v.message = "正在播放发音…".into();
                }
            }
            K::Char('a') if job.as_ref().is_none_or(|j| j.is_finished()) => {
                let tx = tx.clone();
                let root = crate::DATA_ROOT.get().unwrap().clone();
                job = Some(std::thread::spawn(move || {
                    let result = (|| -> Result<String> {
                        let out = Command::new("timeout")
                            .args(["2", "wl-paste", "--no-newline", "--type", "text"])
                            .stdin(Stdio::null())
                            .stderr(Stdio::null())
                            .output()?;
                        if !out.status.success() {
                            bail!("剪贴板无文字或超时");
                        }
                        let word = String::from_utf8(out.stdout)?;
                        let word = word.trim();
                        if word.is_empty()
                            || word.len() > 100
                            || !word
                                .chars()
                                .all(|c| c.is_ascii_alphabetic() || c == '-' || c == '\'')
                        {
                            bail!("请选择一个英文单词");
                        }
                        let mut store = Store::open(&root)?;
                        let n = store.add(&[crate::blank_word(word)])?;
                        Ok(format!("剪贴板：加入 {n} 个单词；切页后刷新"))
                    })();
                    let _ = tx.send(result.unwrap_or_else(|e| format!("添加：{e:#}")));
                }));
            }
            K::Char('n') => {
                v.form = Some(if v.page == 3 {
                    course_form(None, None)
                } else {
                    Form {
                        kind: FormKind::Word,
                        fields: vec![
                            ("单词", String::new()),
                            ("中文释义", String::new()),
                            ("音标", String::new()),
                            ("英文释义", String::new()),
                            ("例句", String::new()),
                            ("词根/派生", String::new()),
                        ],
                        at: 0,
                    }
                })
            }
            K::Char('e') if v.page == 3 && !v.table.courses.is_empty() => {
                let index = v.selected % v.table.courses.len();
                v.form = Some(course_form(Some(index), v.table.courses.get(index)));
            }
            K::Char('d') if v.page == 3 && !v.table.courses.is_empty() => {
                v.table.courses.remove(v.selected % v.table.courses.len());
                store.set("timetable", &v.table)?;
                v.message =
                    crate::replan(store, &v.table).unwrap_or("课程已删除，提醒已请求更新".into());
            }
            K::Char('i') => {
                v.form = Some(Form {
                    kind: FormKind::Import,
                    fields: vec![("文件绝对路径", String::new())],
                    at: 0,
                })
            }
            K::Char('s') => {
                v.form = Some(Form {
                    kind: FormKind::Settings,
                    fields: vec![
                        ("每日新词", v.cfg.new_limit.to_string()),
                        ("每日复习", v.cfg.review_limit.to_string()),
                        ("留存目标 0.70–0.99", v.cfg.retention.to_string()),
                        ("背词提醒 HH:MM", v.cfg.reminder.clone()),
                        ("课前提醒分钟", v.cfg.before_minutes.to_string()),
                        ("发音 espeak/youdao/none", v.cfg.audio.clone()),
                        (
                            "开学日期 YYYY-MM-DD",
                            v.table.semester.start_date.to_string(),
                        ),
                        ("学期周数", v.table.semester.weeks.to_string()),
                    ],
                    at: 0,
                })
            }
            K::Enter if v.page == 4 && !v.wrong => {
                match app::select_book(store, &v.dictionary, BOOKS[v.selected % 6].0) {
                    Ok(n) => {
                        v.message = format!("已加入 {n} 个单词 · 按 2 开始");
                        v.refresh(store)?;
                    }
                    Err(e) => v.message = format!("词书：{e:#}"),
                }
            }
            K::Left | K::Char('[') if v.page == 3 => v.week = v.week.saturating_sub(1).max(1),
            K::Right | K::Char(']') if v.page == 3 => {
                v.week = (v.week + 1).min(v.table.semester.weeks)
            }
            K::Down | K::Char('j') => v.selected = v.selected.saturating_add(1),
            K::Up | K::Char('k') => v.selected = v.selected.saturating_sub(1),
            _ => {}
        }
        if v.page != 1 {
            v.refresh(store)?;
        }
    }
    Ok(())
}
fn course_form(index: Option<usize>, course: Option<&Course>) -> Form {
    let c = course.cloned().unwrap_or(Course {
        name: String::new(),
        teacher: String::new(),
        room: String::new(),
        weekday: 1,
        periods: vec![1, 2],
        weeks: Default::default(),
        parity: WeekParity::Every,
    });
    Form {
        kind: FormKind::Course(index),
        fields: vec![
            ("课程名", c.name),
            ("老师", c.teacher),
            ("教室", c.room),
            ("星期 1–7", c.weekday.to_string()),
            (
                "节次 如 1-2",
                c.periods
                    .iter()
                    .map(u8::to_string)
                    .collect::<Vec<_>>()
                    .join(","),
            ),
            (
                "周次 如 1-16（空白全部）",
                c.weeks
                    .iter()
                    .map(u8::to_string)
                    .collect::<Vec<_>>()
                    .join(","),
            ),
            (
                "单双周 every/odd/even",
                match c.parity {
                    WeekParity::Every => "every",
                    WeekParity::Odd => "odd",
                    WeekParity::Even => "even",
                }
                .into(),
            ),
        ],
        at: 0,
    }
}
fn ranges(s: &str) -> Result<Vec<u8>> {
    let mut out = Vec::new();
    for part in s.split(',').map(str::trim).filter(|s| !s.is_empty()) {
        if let Some((a, b)) = part.split_once('-') {
            let a: u8 = a.parse()?;
            let b: u8 = b.parse()?;
            if b < a || b - a > 54 {
                bail!("范围无效");
            }
            out.extend(a..=b);
        } else {
            out.push(part.parse()?);
        }
    }
    Ok(out)
}
fn save_form(v: &mut View, store: &mut Store, form: &Form) -> Result<()> {
    let s = |i: usize| form.fields[i].1.trim();
    match form.kind {
        FormKind::Filter => v.filter = s(0).into(),
        FormKind::Word => {
            let mut w = crate::blank_word(s(0));
            w.meaning = s(1).into();
            w.phonetic = s(2).into();
            w.definition = s(3).into();
            w.example = s(4).into();
            w.roots = s(5).into();
            if w.word.is_empty() {
                bail!("单词不能为空");
            }
            store.add(&[w])?;
        }
        FormKind::Course(index) => {
            let c = Course {
                name: s(0).into(),
                teacher: s(1).into(),
                room: s(2).into(),
                weekday: s(3).parse()?,
                periods: ranges(s(4))?,
                weeks: ranges(s(5))?.into_iter().collect(),
                parity: match s(6) {
                    "every" => WeekParity::Every,
                    "odd" => WeekParity::Odd,
                    "even" => WeekParity::Even,
                    _ => bail!("单双周使用 every/odd/even"),
                },
            };
            let mut table = v.table.clone();
            if let Some(i) = index {
                table.courses[i] = c;
            } else {
                table.courses.push(c);
            }
            table.validate()?;
            store.set("timetable", &table)?;
            v.table = table;
        }
        FormKind::Settings => {
            let mut cfg = v.cfg.clone();
            cfg.new_limit = s(0).parse()?;
            cfg.review_limit = s(1).parse()?;
            cfg.retention = s(2).parse()?;
            cfg.reminder = s(3).into();
            cfg.before_minutes = s(4).parse()?;
            cfg.audio = s(5).into();
            cfg.validate()?;
            let mut table = v.table.clone();
            table.semester.start_date = s(6).parse()?;
            table.semester.weeks = s(7).parse()?;
            table.validate()?;
            store.set("settings", &cfg)?;
            store.set("timetable", &table)?;
            v.cfg = cfg;
            v.table = table;
        }
        FormKind::Import => {
            crate::import_file(store, &mut v.table, &PathBuf::from(s(0)))?;
        }
    }
    v.message = "已保存".into();
    if matches!(
        form.kind,
        FormKind::Course(_) | FormKind::Settings | FormKind::Import
    ) {
        if let Some(message) = crate::replan(store, &v.table) {
            v.message = message;
        }
    }
    Ok(())
}

struct BackgroundGuard;
impl BackgroundGuard {
    fn new() -> std::io::Result<Self> {
        use std::io::Write;
        if let ratatui::style::Color::Rgb(r, g, b) = BG {
            write!(std::io::stdout(), "\x1b]11;#{r:02x}{g:02x}{b:02x}\x1b\\")?;
            std::io::stdout().flush()?;
        }
        Ok(Self)
    }
}
impl Drop for BackgroundGuard {
    fn drop(&mut self) {
        use std::io::Write;
        let _ = write!(std::io::stdout(), "\x1b]111\x1b\\");
        let _ = std::io::stdout().flush();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn case_insensitive_cloze() {
        assert_eq!(
            cloze("Curiosity feeds curiosity.", "curiosity"),
            "_____ feeds _____."
        );
    }
    #[test]
    fn inclusive_range() {
        assert_eq!(ranges("1-3,5").unwrap(), vec![1, 2, 3, 5]);
        assert!(ranges("5-2").is_err());
    }
}
