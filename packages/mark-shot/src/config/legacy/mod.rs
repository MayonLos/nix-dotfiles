//! 【原版配置】【启动转换】仅转换运行时字段，保存始终基于原始 JSON 对象

use serde_json::Value;
use std::{io, path::Path};

pub(crate) mod capture;
pub(super) mod history;
mod pinned;
mod shortcuts;
mod startup;
mod values;

/// Highest number of invalid fields one recovery pass may remove.
const MAX_REMOVED_FIELDS: usize = 64;

/// Result of a tolerant JSON decode: the usable config plus every field that
/// was dropped because the typed config rejected it.
pub(super) struct Recovered {
    pub config: super::Config,
    pub removed: Vec<(String, Value)>,
}

/// 【原版配置】【完整解析】按 text 返回原生运行参数，明确配置保留，原始厂商数据不重写为另一格式
pub(super) fn decode(text: &str) -> io::Result<super::Config> {
    let root = super::document::root(Path::new("config.json"), text)?;
    from_root(&root).map_err(io::Error::other)
}

/// 【原版配置】【容错解析】按 text 返回可用运行参数并报告被跳过的非法字段，供启动与修复共用
pub(super) fn decode_recovering(text: &str) -> io::Result<Recovered> {
    let root = super::document::root(Path::new("config.json"), text)?;
    let (root, removed) = recover_root(&root).map_err(io::Error::other)?;
    let config = from_root(&root).map_err(io::Error::other)?;
    Ok(Recovered { config, removed })
}

/// 【原版配置】【字段剔除】返回删除非法字段后的原始 JSON 对象及字段值；未知键、旧分组和厂商字段保持不变
///
/// A single invalid value (for example a toolbar size stored as a word) must
/// not discard every other setting. The search drops one leaf at a time and
/// proves with the strict decoder that the remaining document is valid, so the
/// repaired file is written in its original shape instead of the normalized
/// startup representation.
pub(super) fn recover_root(root: &Value) -> Result<(Value, Vec<(String, Value)>), String> {
    let mut cleaned = root.clone();
    let mut removed = Vec::new();
    for _ in 0..MAX_REMOVED_FIELDS {
        if from_root(&cleaned).is_ok() {
            return Ok((cleaned, removed));
        }
        let mut paths = Vec::new();
        locate(&cleaned, &mut Vec::new(), &mut paths);
        if paths.is_empty() {
            let error = from_root(&cleaned).err().unwrap_or_default();
            return Err(error);
        }
        let before = removed.len();
        for path in paths {
            if let Some(value) = take(&mut cleaned, &path) {
                removed.push((path.join("."), value));
            }
        }
        if removed.len() == before {
            return Err("invalid configuration cannot be repaired".into());
        }
    }
    Err("too many invalid configuration fields".into())
}

/// 【原版配置】【类型解码】把原始对象规范化为运行时配置，返回第一个类型错误；不做容错
fn from_root(root: &Value) -> Result<super::Config, String> {
    let mut normalized = normalized(root);
    let mut config: super::Config =
        serde_json::from_value(normalized.take()).map_err(|error| error.to_string())?;
    if let Some(color) = normalized.color {
        config.tools.color = color;
    }
    super::interface_theme::apply_root(&mut config, root);
    config.resolve();
    super::loading::validate(&mut config);
    Ok(config)
}

struct Normalized {
    value: Value,
    color: Option<crate::theme::Rgba>,
}

impl Normalized {
    fn take(&mut self) -> Value {
        std::mem::take(&mut self.value)
    }
}

/// 【原版配置】【字段归一】按 root 生成运行时字段名，返回对象与编辑器颜色覆盖
fn normalized(root: &Value) -> Normalized {
    let mut normalized = root
        .as_object()
        .expect("root was checked as an object")
        .clone();
    if let Some(history) = history::section(root) {
        normalized.insert("history".into(), history);
    }
    if let Some(pinned) = pinned::section(root) {
        normalized.insert("pinned".into(), pinned);
    }
    normalized.insert("capture".into(), capture::settings(root));
    normalized.insert("region_detection".into(), capture::detection(root, true));
    normalized.insert("window_detection".into(), capture::detection(root, false));
    normalized.remove("regionDetection");
    normalized.remove("windowDetection");
    normalized.insert("keys".into(), shortcuts::section(root));
    let (startup, color) = startup::section(root);
    normalized.insert("startup".into(), startup);
    normalized.insert("log".into(), startup::log(root));
    if let Some(ui) = normalized.get_mut("ui").and_then(Value::as_object_mut) {
        ui.retain(|key, value| !matches!(key.as_str(), "language" | "theme") || value.is_string());
    }
    Normalized {
        value: normalized.into(),
        color,
    }
}

/// 【原版配置】【字段定位】向 out 追加导致整份配置无法解码的原始 JSON 字段路径
fn locate(root: &Value, path: &mut Vec<String>, out: &mut Vec<Vec<String>>) {
    if decodes(root, path) {
        return;
    }
    let value = at(root, path);
    match value {
        Some(Value::Object(map)) if !map.is_empty() => {
            let before = out.len();
            for key in map.keys() {
                path.push(key.clone());
                locate(root, path, out);
                path.pop();
            }
            if out.len() == before {
                if path.is_empty() {
                    locate_top_level(root, out);
                } else {
                    out.push(path.clone());
                }
            }
        }
        Some(_) | None if !path.is_empty() => out.push(path.clone()),
        _ => locate_top_level(root, out),
    }
}

/// 【原版配置】【顶层定位】子树单独解码正常但组合失败时，逐个删除顶层分组确认可恢复的字段
fn locate_top_level(root: &Value, out: &mut Vec<Vec<String>>) {
    let Some(map) = root.as_object() else {
        return;
    };
    for key in map.keys() {
        let mut trial = root.clone();
        if let Some(object) = trial.as_object_mut() {
            object.remove(key);
        }
        if from_root(&trial).is_ok() {
            out.push(vec![key.clone()]);
            return;
        }
    }
}

/// 【原版配置】【子树判定】path 指向的子树（连同规范化规则）是否能被强类型配置接受
fn decodes(root: &Value, path: &[String]) -> bool {
    if path.is_empty() {
        return from_root(root).is_ok();
    }
    at(root, path).is_none_or(|value| from_root(&wrapped(value, path)).is_ok())
}

/// 【原版配置】【路径取值】按 path 返回 root 对应节点
fn at<'a>(root: &'a Value, path: &[String]) -> Option<&'a Value> {
    path.iter().try_fold(root, |value, key| value.get(key))
}

/// 【原版配置】【路径包装】按 path 把 value 放回原始嵌套层级，供解码器单独验证
fn wrapped(value: &Value, path: &[String]) -> Value {
    let mut current = value.clone();
    for key in path.iter().rev() {
        let mut object = serde_json::Map::new();
        object.insert(key.clone(), current);
        current = Value::Object(object);
    }
    current
}

/// 【原版配置】【路径删除】按 path 从 root 移除并返回节点，缺失返回空值
fn take(root: &mut Value, path: &[String]) -> Option<Value> {
    let (last, parents) = path.split_last()?;
    let parent = parents
        .iter()
        .try_fold(root, |value, key| value.get_mut(key))?;
    parent.as_object_mut()?.remove(last)
}
