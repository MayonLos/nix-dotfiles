//! Disk accounting and a frozen, explicitly reviewed cleanup plan.
use crate::api::{self, Disk, Engine};
use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use mayon_ui::input::TextInput;
use serde_json::Value;
use std::collections::HashSet;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Kind {
    Image,
    Container,
    Volume,
    Cache,
}
impl Kind {
    pub const ALL: [Self; 4] = [Self::Image, Self::Container, Self::Volume, Self::Cache];
    pub fn label(self) -> &'static str {
        match self {
            Self::Image => "镜像",
            Self::Container => "容器",
            Self::Volume => "卷",
            Self::Cache => "构建缓存",
        }
    }
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Entry {
    pub kind: Kind,
    pub id: String,
    pub name: String,
    pub size: Option<u64>,
    pub reclaim: Option<u64>,
    pub blocked: Option<String>,
}
impl Entry {
    pub fn key(&self) -> String {
        format!("{}:{}", self.kind.label(), self.id)
    }
    pub fn selectable(&self) -> bool {
        !self.id.is_empty() && self.blocked.is_none()
    }
    pub fn description(&self) -> String {
        format!(
            "{} · ID / 名称：{}\n{}\n占用 {} · 预计释放 {}",
            self.kind.label(),
            self.id,
            mayon_ui::theme::clip(&self.name, 64),
            bytes(self.size),
            bytes(self.reclaim)
        )
    }
}
pub fn bytes(size: Option<u64>) -> String {
    size.map(mayon_ui::theme::bytes)
        .unwrap_or_else(|| "未知".into())
}
fn positive(value: Option<i64>) -> Option<u64> {
    value.and_then(|n| u64::try_from(n).ok())
}
fn number(v: &Value, field: &str) -> Option<u64> {
    positive(v.get(field).and_then(Value::as_i64))
}
fn text<'a>(v: &'a Value, field: &str) -> &'a str {
    v.get(field).and_then(Value::as_str).unwrap_or("")
}
/// Unknown reference counts fail closed. All referenced images/volumes stay locked,
/// even when the referring container is stopped (deleting it is a separate plan).
pub fn entries(disk: &Disk) -> Vec<Entry> {
    let mut out = vec![];
    for image in &disk.images {
        let used = image.containers != 0
            || disk
                .containers
                .iter()
                .any(|c| text(c, "ImageID") == image.id);
        out.push(Entry {
            kind: Kind::Image,
            id: image.id.clone(),
            name: if api::is_dangling(&image.tags) {
                "<悬空>".into()
            } else {
                image.tags.join(", ")
            },
            size: Some(image.size),
            reclaim: positive(Some(image.shared)).map(|shared| image.size.saturating_sub(shared)),
            blocked: used.then(|| "被引用 / 未知".into()),
        });
    }
    for c in &disk.containers {
        let stopped = matches!(text(c, "State"), "exited" | "created" | "dead");
        let name = c
            .get("Names")
            .and_then(Value::as_array)
            .and_then(|xs| xs.first())
            .and_then(Value::as_str)
            .unwrap_or("")
            .trim_start_matches('/');
        out.push(Entry {
            kind: Kind::Container,
            id: text(c, "Id").into(),
            name: format!("{name} ({})", text(c, "State")),
            size: number(c, "SizeRw"),
            reclaim: number(c, "SizeRw"),
            blocked: (!stopped).then(|| "运行中 / 未知".into()),
        });
    }
    for v in &disk.volumes {
        let referenced = disk.containers.iter().any(|c| {
            c.get("Mounts").and_then(Value::as_array).is_some_and(|ms| {
                ms.iter()
                    .any(|m| text(m, "Type") == "volume" && text(m, "Name") == v.name)
            })
        });
        let unused = v.usage.as_ref().is_some_and(|u| u.refs == 0) && !referenced;
        let size = v.usage.as_ref().and_then(|u| positive(Some(u.size)));
        out.push(Entry {
            kind: Kind::Volume,
            id: v.name.clone(),
            name: v.name.clone(),
            size,
            reclaim: size,
            blocked: (!unused).then(|| "被引用 / 未知".into()),
        });
    }
    for b in &disk.build_cache {
        out.push(Entry {
            kind: Kind::Cache,
            id: b.id.clone(),
            name: b.description.clone(),
            size: Some(b.size),
            reclaim: Some(if b.is_shared { 0 } else { b.size }),
            blocked: if b.in_use || b.is_shared {
                Some("InUse / Shared：保护".into())
            } else if api::cache_prune_path(&b.id).is_err() {
                Some("ID 不支持精确清理".into())
            } else {
                None
            },
        });
    }
    out.sort_by(|a, b| b.size.cmp(&a.size).then_with(|| a.key().cmp(&b.key())));
    out
}
pub fn selected(entries: &[Entry], keys: &HashSet<String>) -> Vec<Entry> {
    entries
        .iter()
        .filter(|e| e.selectable() && keys.contains(&e.key()))
        .cloned()
        .collect()
}
pub fn sum_sizes(values: impl Iterator<Item = Option<u64>>) -> (u64, usize) {
    values.fold((0u64, 0), |(total, unknown), value| match value {
        Some(n) => (total.saturating_add(n), unknown),
        None => (total, unknown + 1),
    })
}
pub fn estimate(plan: &[Entry]) -> String {
    let (size, unknown) = sum_sizes(plan.iter().map(|e| e.reclaim));
    format!(
        "{}{}",
        mayon_ui::theme::bytes(size),
        if unknown > 0 {
            format!(" + {unknown} 项未知")
        } else {
            String::new()
        }
    )
}
pub fn summary(disk: &Disk) -> String {
    let es = entries(disk);
    let mut lines = vec!["分类         占用               安全可回收（估计）".to_string()];
    for kind in Kind::ALL {
        let subset: Vec<_> = es.iter().filter(|e| e.kind == kind).cloned().collect();
        let total = if kind == Kind::Image {
            bytes(Some(disk.layers_size))
        } else {
            let (n, u) = sum_sizes(subset.iter().map(|e| e.size));
            format!("{}{}", bytes(Some(n)), if u > 0 { " + 未知" } else { "" })
        };
        let reclaim: Vec<_> = subset.into_iter().filter(Entry::selectable).collect();
        lines.push(format!(
            "{}：占用 {total} · 可回收 {}",
            kind.label(),
            estimate(&reclaim)
        ));
    }
    lines.push("共享镜像层只计独占部分；Shared 缓存不清理；卷默认不选。".into());
    lines.join("\n")
}
// Excludes shared build cache, which is accounted in image layers already.
fn physical_usage(disk: &Disk) -> Option<u64> {
    let mut total = disk.layers_size;
    for c in &disk.containers {
        total = total.checked_add(number(c, "SizeRw")?)?;
    }
    for v in &disk.volumes {
        total = total.checked_add(positive(Some(v.usage.as_ref()?.size))?)?;
    }
    for b in &disk.build_cache {
        if !b.is_shared {
            total = total.checked_add(b.size)?;
        }
    }
    Some(total)
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Stage {
    Preview,
    Confirm,
    Volumes,
}
#[derive(Clone)]
pub struct Flow {
    pub plan: Vec<Entry>,
    pub stage: Stage,
    pub cursor: usize,
    seen: usize,
    pub input: TextInput,
    volume_cursor: usize,
}
impl Flow {
    pub fn new(plan: Vec<Entry>) -> Option<Self> {
        (!plan.is_empty() && plan.iter().all(Entry::selectable)).then_some(Self {
            plan,
            stage: Stage::Preview,
            cursor: 0,
            seen: 0,
            input: TextInput::default(),
            volume_cursor: 0,
        })
    }
    pub fn volume_phrase(&self) -> String {
        format!(
            "DELETE {}",
            self.plan
                .iter()
                .filter(|e| e.kind == Kind::Volume)
                .nth(self.volume_cursor)
                .map(|e| e.id.as_str())
                .unwrap_or("")
        )
    }
    /// Returns an authorized frozen plan only after preview AND second confirmation.
    #[cfg(test)]
    pub fn key(&mut self, key: KeyCode) -> Option<Vec<Entry>> {
        self.handle_key(KeyEvent::new(key, KeyModifiers::NONE))
    }
    pub fn handle_key(&mut self, event: KeyEvent) -> Option<Vec<Entry>> {
        let key = event.code;
        if self.stage != Stage::Volumes
            && event
                .modifiers
                .intersects(KeyModifiers::CONTROL | KeyModifiers::ALT)
        {
            return None;
        }
        match self.stage {
            Stage::Preview => match key {
                KeyCode::Down | KeyCode::Char('j') => {
                    self.cursor = (self.cursor + 1).min(self.plan.len() - 1);
                    self.seen = self.seen.max(self.cursor);
                }
                KeyCode::Up | KeyCode::Char('k') => self.cursor = self.cursor.saturating_sub(1),
                KeyCode::Char('y') if self.seen + 1 == self.plan.len() => {
                    self.stage = Stage::Confirm
                }
                _ => (),
            },
            Stage::Confirm if key == KeyCode::Char('y') => {
                if self.plan.iter().any(|e| e.kind == Kind::Volume) {
                    self.stage = Stage::Volumes;
                } else {
                    return Some(self.plan.clone());
                }
            }
            Stage::Volumes => match key {
                KeyCode::Enter if self.input.as_str() == self.volume_phrase() => {
                    self.volume_cursor += 1;
                    if self.volume_cursor
                        == self.plan.iter().filter(|e| e.kind == Kind::Volume).count()
                    {
                        return Some(self.plan.clone());
                    }
                    self.input.clear();
                }
                _ => {
                    self.input.handle_key(event);
                }
            },
            _ => (),
        }
        None
    }
    pub fn body(&self) -> String {
        match self.stage {
            Stage::Preview => format!("预览准确清单 {}/{} · 总预计释放 {}\n\n{}\n\n只删除清单内 ID，不停止容器，不删除容器关联卷。\n卷数据不可恢复；卷需要另行输入名称确认。\n\nj/k 逐项查看 · 查看全部后 y 进入二次确认 · Esc 取消", self.cursor+1, self.plan.len(), estimate(&self.plan), self.plan[self.cursor].description()),
            Stage::Confirm => format!("二次确认：删除已预览的 {} 项？\n预计释放 {}（共享层、并发活动可能影响实际值）\n\n容器 writable layer、卷内数据删除后不可恢复。\n执行前重新验证引用状态；状态改变的项目跳过。\n\ny 确认 · Esc 取消", self.plan.len(), estimate(&self.plan)),
            Stage::Volumes => format!("卷数据不可恢复！每个卷均需单独确认。\n输入以下完整文本，再按 Enter：\n\n{}\n\n输入：\n\nEsc 取消", self.volume_phrase()),
        }
    }
}
#[derive(Debug, Default)]
pub struct Report {
    pub lines: Vec<String>,
    pub failed: usize,
}
impl Report {
    pub fn body(&self) -> String {
        self.lines.join("\n")
    }
}
/// Every mutation is scoped to one reviewed ID, non-forcing, and preceded by a
/// fresh snapshot. Engine conflict checks remain the final race protection.
pub async fn execute(engine: &Engine, plan: &[Entry]) -> Report {
    let mut report = Report::default();
    let before = engine.disk().await.ok().as_ref().and_then(physical_usage);
    let mut cache_reclaimed = 0u64;
    for entry in plan {
        let result = async {
            let fresh = entries(&engine.disk().await?);
            if !fresh
                .iter()
                .any(|e| e.kind == entry.kind && e.id == entry.id && e.selectable())
            {
                return Err("状态改变、被引用或已不存在；跳过".to_string());
            }
            match entry.kind {
                Kind::Container => engine.remove_container(&entry.id).await?,
                Kind::Image => engine.remove_image(&entry.id).await?,
                Kind::Volume => engine.remove_volume(&entry.id).await?,
                Kind::Cache => {
                    let response = engine.remove_cache(&entry.id).await?;
                    let deleted = response.get("CachesDeleted").and_then(Value::as_array);
                    if !deleted.is_some_and(|ids| ids.iter().any(|v| v.as_str() == Some(&entry.id)))
                    {
                        return Err("daemon 未确认删除此缓存（可能已在使用）".into());
                    }
                    cache_reclaimed = cache_reclaimed.saturating_add(
                        response
                            .get("SpaceReclaimed")
                            .and_then(Value::as_u64)
                            .unwrap_or(0),
                    );
                }
            }
            Ok::<(), String>(())
        }
        .await;
        match result {
            Ok(()) => report
                .lines
                .push(format!("已删除 {} {}", entry.kind.label(), entry.id)),
            Err(error) => {
                report.failed += 1;
                report
                    .lines
                    .push(format!("失败 {} {}：{error}", entry.kind.label(), entry.id));
            }
        }
    }
    let after = engine.disk().await.ok().as_ref().and_then(physical_usage);
    let actual = before.zip(after).map(|(b, a)| b.saturating_sub(a));
    report.lines.insert(
        0,
        format!(
            "完成 {} 项 · 失败 {} 项",
            plan.len() - report.failed,
            report.failed
        ),
    );
    report.lines.insert(
        1,
        format!("实际释放（daemon 占用前后差值）：{}", bytes(actual)),
    );
    report.lines.insert(
        2,
        format!(
            "其中缓存 API SpaceReclaimed：{}",
            bytes(Some(cache_reclaimed))
        ),
    );
    report.lines.insert(
        3,
        "占用差值受并发活动影响；未知大小或查询失败时不推算实际值。".into(),
    );
    report
}

#[cfg(test)]
#[path = "cleanup_tests.rs"]
mod tests;
