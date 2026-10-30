use anyhow::{ensure, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;

pub const GROUPS: [&str; 7] = ["窗口", "工作区", "应用", "TUI 工具", "截图", "媒体", "系统"];

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct Export {
    pub version: u32,
    pub bindings: Vec<Binding>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct Binding {
    pub mode: String,
    pub kind: String,
    pub raw: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Entry {
    pub binding: Binding,
    pub chord: String,
    pub action: String,
    pub group: usize,
    pub description: String,
    pub conflict: bool,
}

#[derive(Clone, Debug)]
struct Parsed {
    chord: String,
    normalized: String,
    action: String,
    args: Vec<String>,
    device: Device,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
enum Device {
    Keyboard,
    Pointer,
    Gesture,
}

pub fn entries(export: Export) -> Result<Vec<Entry>> {
    ensure!(
        export.version == 1,
        "unsupported keybinding export version {}",
        export.version
    );
    let parsed = export
        .bindings
        .iter()
        .map(parse_binding)
        .collect::<Result<Vec<_>>>()?;
    let conflicts = conflict_indices(&export.bindings, &parsed);
    Ok(export
        .bindings
        .into_iter()
        .zip(parsed)
        .enumerate()
        .map(|(index, (binding, parsed))| {
            let description = describe(&binding, &parsed);
            let group = group_for(&parsed, &description);
            Entry {
                binding,
                chord: parsed.chord,
                action: parsed.action,
                group,
                description,
                conflict: conflicts.contains(&index),
            }
        })
        .collect())
}

fn parse_binding(binding: &Binding) -> Result<Parsed> {
    let fields = binding.raw.split(',').map(str::trim).collect::<Vec<_>>();
    let gesture = binding.kind.starts_with("gesturebind");
    let required = if gesture { 4 } else { 3 };
    ensure!(
        fields.len() >= required,
        "invalid {} binding: {}",
        binding.kind,
        binding.raw
    );
    let (chord, normalized, action_index, device) = if gesture {
        let fingers = fields[2];
        let direction = fields[1];
        let (mod_display, mod_normalized) = normalize_modifiers(fields[0]);
        let gesture = format!(
            "{}:{}:{}",
            mod_normalized,
            direction.to_ascii_lowercase(),
            fingers
        );
        let chord = format!(
            "{}{}指滑动 {}",
            if mod_display.is_empty() {
                String::new()
            } else {
                format!("{mod_display} + ")
            },
            fingers,
            direction_name(direction)
        );
        (chord, format!("gesture:{gesture}"), 3, Device::Gesture)
    } else {
        let (chord, normalized) = normalize_chord(fields[0], fields[1]);
        let device = if binding.kind.starts_with("mousebind") {
            Device::Pointer
        } else if binding.kind.starts_with("gesturebind") {
            Device::Gesture
        } else {
            Device::Keyboard
        };
        (chord, normalized, 2, device)
    };
    let action = fields[action_index].to_owned();
    let args = fields[action_index + 1..]
        .iter()
        .map(|part| (*part).to_owned())
        .collect();
    Ok(Parsed {
        chord,
        normalized,
        action,
        args,
        device,
    })
}

fn normalize_chord(modifiers: &str, key: &str) -> (String, String) {
    let (display, normalized_modifiers) = normalize_modifiers(modifiers);
    let key_display = key_name(key);
    let normalized = format!("{}+{}", normalized_modifiers, key.to_ascii_lowercase());
    let chord = if display.is_empty() {
        key_display
    } else {
        format!("{}+{}", display, key_display)
    };
    (chord, normalized)
}

fn normalize_modifiers(modifiers: &str) -> (String, String) {
    let mut mods = modifiers
        .split('+')
        .map(|value| match value.trim().to_ascii_uppercase().as_str() {
            "CONTROL" => "CTRL".to_owned(),
            value => value.to_owned(),
        })
        .filter(|value| !value.is_empty() && value != "NONE")
        .collect::<Vec<_>>();
    mods.sort_by_key(|value| modifier_order(value));
    mods.dedup();
    let display = mods
        .iter()
        .map(|modifier| match modifier.as_str() {
            "SUPER" => "Super",
            "CTRL" | "CONTROL" => "Ctrl",
            "ALT" => "Alt",
            "SHIFT" => "Shift",
            other => other,
        })
        .collect::<Vec<_>>();
    (display.join("+"), mods.join("+"))
}

fn modifier_order(value: &str) -> usize {
    match value {
        "SUPER" => 0,
        "CTRL" | "CONTROL" => 1,
        "ALT" => 2,
        "SHIFT" => 3,
        _ => 4,
    }
}

fn key_name(value: &str) -> String {
    match value.to_ascii_lowercase().as_str() {
        "return" => "Enter".into(),
        "escape" => "Esc".into(),
        "space" => "Space".into(),
        "grave" => "`".into(),
        "page_up" => "PageUp".into(),
        "page_down" => "PageDown".into(),
        "left" => "Left".into(),
        "right" => "Right".into(),
        "up" => "Up".into(),
        "down" => "Down".into(),
        "minus" => "-".into(),
        "equal" => "=".into(),
        "print" => "Print".into(),
        "xf86audioraisevolume" => "AudioRaiseVolume".into(),
        "xf86audiolowervolume" => "AudioLowerVolume".into(),
        "xf86audiomute" => "AudioMute".into(),
        "xf86audiomicmute" => "AudioMicMute".into(),
        "xf86monbrightnessup" => "MonBrightnessUp".into(),
        "xf86monbrightnessdown" => "MonBrightnessDown".into(),
        "xf86audioplay" => "AudioPlay".into(),
        "xf86audiostop" => "AudioStop".into(),
        "xf86audioprev" => "AudioPrev".into(),
        "xf86audionext" => "AudioNext".into(),
        other if other.starts_with("xf86") => value.to_owned(),
        _ => value.to_owned(),
    }
}

fn conflict_indices(bindings: &[Binding], parsed: &[Parsed]) -> HashSet<usize> {
    let mut conflicts = HashSet::new();
    for left in 0..bindings.len() {
        for right in left + 1..bindings.len() {
            let a = &parsed[left];
            let b = &parsed[right];
            if a.device != b.device || a.normalized != b.normalized {
                continue;
            }
            if !modes_overlap(&bindings[left].mode, &bindings[right].mode) {
                continue;
            }
            conflicts.insert(left);
            conflicts.insert(right);
        }
    }
    conflicts
}

fn modes_overlap(left: &str, right: &str) -> bool {
    left == "common" || right == "common" || left == right
}

fn describe(binding: &Binding, parsed: &Parsed) -> String {
    let description = describe_action(binding, parsed);
    if binding.kind.starts_with("gesturebind") {
        return format!(
            "{}指滑动 {}：{}",
            binding.raw.split(',').nth(2).unwrap_or("?"),
            direction_name(binding.raw.split(',').nth(1).unwrap_or("")),
            description
        );
    }
    description
}

fn describe_action(binding: &Binding, parsed: &Parsed) -> String {
    match parsed.action.as_str() {
        "spawn" => describe_spawn(&parsed.args, binding),
        "focusdir" => format!(
            "聚焦{}方向窗口",
            direction_name(parsed.args.first().map(String::as_str).unwrap_or(""))
        ),
        "move_client" => format!(
            "将窗口移向{}",
            direction_name(parsed.args.first().map(String::as_str).unwrap_or(""))
        ),
        "tagmon" => format!(
            "将窗口移到{}侧显示器",
            direction_name(parsed.args.first().map(String::as_str).unwrap_or(""))
        ),
        "viewtoright" => "切换到下一个占用工作区".into(),
        "viewtoleft" => "切换到上一个占用工作区".into(),
        "overcircle" => {
            if parsed.args.first().is_some_and(|arg| arg.contains("prev")) {
                "切换到同工作区上一个窗口".into()
            } else {
                "切换到同工作区下一个窗口".into()
            }
        }
        "tagtoright" => "将窗口移到右侧工作区".into(),
        "tagtoleft" => "将窗口移到左侧工作区".into(),
        "view" => format!("切换到工作区 {}", arg(parsed, 0, "?")),
        "tagsilent" => format!("移到工作区 {}，留在当前页", arg(parsed, 0, "?")),
        "tag" => format!("移到工作区 {} 并跟随", arg(parsed, 0, "?")),
        "focusstack" => {
            if arg(parsed, 0, "") == "prev" {
                "切换到上一个窗口".into()
            } else {
                "切换到下一个窗口".into()
            }
        }
        "focuslast" => "返回上一个窗口".into(),
        "switcher" => "切换器：向前切换一项".into(),
        "toggleoverview" => "切换窗口概览".into(),
        "togglejump" => "切换跳转标签".into(),
        "toggle_special_tag" => "切换特殊工作区".into(),
        "setkeymode" => format!("切换按键模式：{}", parsed.args.join(" ")),
        "incnmaster" => format!(
            "主窗口数量 {} {}",
            if arg(parsed, 0, "").starts_with('-') {
                "减少"
            } else {
                "增加"
            },
            arg(parsed, 0, "")
        ),
        "setmfact" => format!("调整主区域比例：{}", parsed.args.join(" ")),
        "togglemaximizescreen" => "切换最大化".into(),
        "togglefullscreen" => "切换全屏".into(),
        "centerwin" => "居中窗口".into(),
        "resizewin" => format!("调整窗口大小：{}", parsed.args.join("，")),
        "togglefloating" => "切换浮动窗口".into(),
        "switch_layout" => "切换布局".into(),
        "zoom" => "将当前窗口与主窗口交换".into(),
        "togglegaps" => "切换窗口间距".into(),
        "switch_proportion_preset" => "切换滚动布局比例".into(),
        "minimized" => "最小化窗口".into(),
        "toggle_scratchpad" => "找回最小化窗口".into(),
        "toggle_named_scratchpad" => scratchpad_description(&parsed.args),
        "moveresize" => match arg(parsed, 0, "") {
            "curmove" => "按住拖动窗口".into(),
            "curresize" => "按住调整窗口大小".into(),
            other => format!("移动或调整窗口：{other}"),
        },
        "toggleglobal" => "切换跨工作区显示".into(),
        "toggleoverlay" => "切换窗口置顶".into(),
        "tag_special_silent" => "移入或取回特殊工作区窗口".into(),
        "sleep_monitor" => "关闭显示器".into(),
        "wakeup_monitor" => "唤醒显示器".into(),
        "reload_config" => "重载 Mango 配置".into(),
        "killclient" => "关闭当前窗口".into(),
        "viewnext_have_client" => "切换到下一个占用工作区".into(),
        "viewprev_have_client" => "切换到上一个占用工作区".into(),
        action => action_description(action, &parsed.args, binding),
    }
}

fn action_description(action: &str, args: &[String], _binding: &Binding) -> String {
    let raw = if args.is_empty() {
        action.to_owned()
    } else {
        format!("{action} {}", args.join(" "))
    };
    match action {
        "focusdir" => format!(
            "聚焦{}方向窗口",
            args.first().map(|s| direction_name(s)).unwrap_or("未知")
        ),
        _ => raw,
    }
}

fn describe_spawn(args: &[String], binding: &Binding) -> String {
    let raw = args.join(" ");
    let lower = raw.to_ascii_lowercase();
    if lower.contains("workspace-files") {
        return "打开文件管理器".into();
    }
    if lower.contains("workspace-browser") {
        return "打开浏览器".into();
    }
    if lower.contains("workspace-terminal") {
        return "打开终端".into();
    }
    if lower.contains("herdr-terminal") {
        return "打开 Herdr 终端代理".into();
    }
    if lower.contains("mango-keybindings") || lower.contains("/less ") {
        return "查看 Mango 快捷键说明".into();
    }
    if lower.contains("launchpad") {
        return "打开应用启动器".into();
    }
    if lower.contains("window-switcher") {
        return "按住 Alt 切换窗口，松开确认".into();
    }
    if lower.contains("notification-dnd-toggle") {
        return "切换勿扰模式".into();
    }
    if lower.contains("caffeine-toggle") {
        return "切换防休眠".into();
    }
    if lower.contains("panel-toggle control-center") {
        return "打开控制中心".into();
    }
    if lower.contains("panel-toggle launcher") {
        return "打开启动器".into();
    }
    if lower.contains("panel-toggle session") {
        return "打开会话菜单".into();
    }
    if lower.contains("panel-toggle clipboard") {
        return "打开剪贴板历史".into();
    }
    if lower.contains("session lock") {
        return "锁定屏幕".into();
    }
    if lower.contains("wallpaper-random") {
        return "随机更换壁纸".into();
    }
    if lower.contains("mark-shot") {
        return "区域截图".into();
    }
    if lower.contains("screenshot-screen") {
        return "截图并复制全屏".into();
    }
    if lower.contains("wayscrollshot") {
        return "滚动截图".into();
    }
    if lower.contains("ocr-region") {
        return "识别选区文字".into();
    }
    if lower.contains("ocr-screen") {
        return "识别全屏文字".into();
    }
    if lower.contains("headset-mic") {
        return "切换蓝牙耳机麦克风".into();
    }
    if lower.contains("playerctl") {
        return media_description(&lower);
    }
    if lower.contains("mic-mute") {
        return "切换麦克风静音".into();
    }
    if lower.contains("volume-up") {
        return "调高音量".into();
    }
    if lower.contains("volume-down") {
        return "调低音量".into();
    }
    if lower.contains("volume-mute") {
        return "切换静音".into();
    }
    if lower.contains("brightness-up") {
        return "调亮屏幕".into();
    }
    if lower.contains("brightness-down") {
        return "调暗屏幕".into();
    }
    if raw.contains("mayon-voice") || raw.contains("toggle") && binding.raw.contains("mayonVoice") {
        return if binding.kind == "bindr" {
            "松开录音键开始或停止语音输入"
        } else {
            "开始或停止语音输入"
        }
        .into();
    }
    format!("启动：{raw}")
}

fn media_description(raw: &str) -> String {
    if raw.contains("play-pause") {
        "播放或暂停".into()
    } else if raw.contains("previous") {
        "上一首".into()
    } else if raw.contains("next") {
        "下一首".into()
    } else if raw.contains("stop") {
        "停止播放".into()
    } else {
        format!("媒体控制：{raw}")
    }
}

fn scratchpad_description(args: &[String]) -> String {
    let id = args.first().map(String::as_str).unwrap_or("");
    match id {
        "mayon-scratch" => "呼出或隐藏临时终端".into(),
        "mayon-files" => "呼出或隐藏文件管理器 Yazi".into(),
        "mayon-monitor" => "呼出或隐藏系统监视器 btop".into(),
        "mayon-clash" => "呼出或隐藏 Clash TUI".into(),
        "mayon-tools" => "呼出或隐藏工具箱".into(),
        "mayon-bili" => "呼出或隐藏 Bilibili TUI".into(),
        _ => {
            if args.is_empty() {
                "toggle_named_scratchpad".to_owned()
            } else {
                format!("toggle_named_scratchpad {}", args.join(" "))
            }
        }
    }
}

fn group_for(parsed: &Parsed, description: &str) -> usize {
    if parsed.action == "spawn" && parsed.args.iter().any(|arg| arg.contains("playerctl ")) {
        return 5;
    }
    if parsed.action == "focusdir" {
        return 0;
    }
    if matches!(
        parsed.action.as_str(),
        "viewnext_have_client" | "viewprev_have_client"
    ) {
        return 1;
    }
    if parsed.action == "toggle_named_scratchpad" {
        return 3;
    }
    if parsed.action == "spawn" && description.contains("切换窗口") {
        return 0;
    }
    if matches!(
        parsed.action.as_str(),
        "view"
            | "viewtoright"
            | "viewtoleft"
            | "tag"
            | "tagsilent"
            | "tagtoright"
            | "tagtoleft"
            | "toggle_special_tag"
            | "tag_special_silent"
            | "togglejump"
    ) {
        return 1;
    }
    if matches!(
        parsed.action.as_str(),
        "focusdir"
            | "move_client"
            | "tagmon"
            | "overcircle"
            | "focusstack"
            | "focuslast"
            | "toggleoverview"
            | "switcher"
            | "setkeymode"
            | "incnmaster"
            | "setmfact"
            | "togglemaximizescreen"
            | "togglefullscreen"
            | "centerwin"
            | "resizewin"
            | "moveresize"
            | "togglefloating"
            | "switch_layout"
            | "zoom"
            | "togglegaps"
            | "switch_proportion_preset"
            | "minimized"
            | "toggle_scratchpad"
            | "toggleglobal"
            | "toggleoverlay"
            | "killclient"
    ) {
        return 0;
    }
    let desc = description.to_ascii_lowercase();
    if desc.contains("截图") || desc.contains("识别") {
        return 4;
    }
    if desc.contains("播放")
        || desc.contains("音量")
        || desc.contains("静音")
        || desc.contains("麦克风")
        || desc.contains("耳机")
    {
        return 5;
    }
    if matches!(
        description,
        "锁定屏幕"
            | "切换勿扰模式"
            | "切换防休眠"
            | "打开控制中心"
            | "打开会话菜单"
            | "随机更换壁纸"
            | "调亮屏幕"
            | "调暗屏幕"
    ) {
        return 6;
    }
    if parsed.action == "spawn"
        && (description.contains("应用")
            || description.contains("浏览器")
            || description.contains("文件管理器")
            || description.contains("终端")
            || description.contains("启动器"))
    {
        return 2;
    }
    if parsed.action == "spawn" {
        return 2;
    }
    6
}

fn direction_name(direction: &str) -> &'static str {
    match direction.to_ascii_lowercase().as_str() {
        "left" | "previous" | "prev" => "左",
        "right" | "next" => "右",
        "up" => "上",
        "down" => "下",
        _ => "未知",
    }
}

fn arg<'a>(parsed: &'a Parsed, index: usize, default: &'a str) -> &'a str {
    parsed
        .args
        .get(index)
        .map(String::as_str)
        .unwrap_or(default)
}

#[cfg(test)]
pub fn fuzzy(query: &str, text: &str) -> bool {
    mayon_ui::search::Matcher::new(query).matches(text)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn binding(mode: &str, kind: &str, raw: &str) -> Binding {
        Binding {
            mode: mode.into(),
            kind: kind.into(),
            raw: raw.into(),
        }
    }

    fn model(rows: Vec<Binding>) -> Vec<Entry> {
        entries(Export {
            version: 1,
            bindings: rows,
        })
        .unwrap()
    }

    #[test]
    fn keeps_unknown_actions_and_every_input_row() {
        let rows = vec![binding(
            "default",
            "bind",
            "SUPER+SHIFT,X,brand_new_action,arg,more",
        )];
        let result = model(rows.clone());
        assert_eq!(result.len(), rows.len());
        assert_eq!(result[0].description, "brand_new_action arg more");
        assert_eq!(result[0].binding, rows[0]);
    }

    #[test]
    fn marks_identical_chords_that_share_a_mode_or_common_mode() {
        let result = model(vec![
            binding("default", "bind", "SUPER+CTRL,X,one"),
            binding("default", "bindl", "CTRL+SUPER,x,two"),
            binding("common", "bind", "SUPER+CTRL,X,three"),
            binding("resize", "bind", "SUPER+CTRL,X,four"),
        ]);
        assert!(result[0].conflict && result[1].conflict && result[2].conflict);
        assert!(result[3].conflict);
        assert_eq!(result[0].chord, "Super+Ctrl+X");
    }

    #[test]
    fn keeps_mouse_and_gestures_in_separate_device_domains() {
        let result = model(vec![
            binding("default", "bind", "SUPER,Left,one"),
            binding("default", "mousebind", "SUPER,btn_left,two"),
            binding("default", "gesturebind", "none,left,4,one"),
        ]);
        assert!(result.iter().all(|entry| !entry.conflict));
        assert!(result[2].chord.contains("4指滑动"));
    }

    #[test]
    fn non_common_different_modes_do_not_conflict() {
        let result = model(vec![
            binding("default", "bind", "NONE,Escape,one"),
            binding("resize", "bind", "NONE,Escape,two"),
            binding("Resize", "bind", "NONE,Escape,three"),
            binding("Resize", "bind", "NONE,Escape,four"),
            binding("Common", "bind", "NONE,Escape,five"),
        ]);
        assert!(!result[0].conflict && !result[1].conflict);
        assert!(result[2].conflict && result[3].conflict);
        assert!(!result[4].conflict);
    }

    #[test]
    fn system_spawn_actions_and_mouse_resize_are_grouped_by_purpose() {
        let result = model(vec![
            binding("default", "bind", "SUPER,L,spawn,noctalia msg session lock"),
            binding(
                "default",
                "bind",
                "SUPER,D,spawn,noctalia msg notification-dnd-toggle",
            ),
            binding(
                "default",
                "bind",
                "SUPER,I,spawn,noctalia msg caffeine-toggle",
            ),
            binding(
                "default",
                "bind",
                "SUPER,S,spawn,noctalia msg panel-toggle control-center",
            ),
            binding(
                "default",
                "bind",
                "SUPER,X,spawn,noctalia msg wallpaper-random",
            ),
            binding(
                "default",
                "bind",
                "SUPER,B,spawn,noctalia msg brightness-up",
            ),
            binding("default", "bind", "SUPER,T,spawn,unknown-command"),
            binding(
                "default",
                "bind",
                "ALT,Tab,spawn,noctalia msg window-switcher hold",
            ),
            binding(
                "default",
                "mousebind",
                "SUPER,btn_right,moveresize,curresize",
            ),
        ]);
        for entry in result.iter().take(6) {
            assert_eq!(entry.group, 6, "{}", entry.description);
        }
        assert_eq!(result[6].group, 2);
        assert_eq!(result[7].group, 0);
        assert_eq!(result[8].group, 0);
    }

    #[test]
    fn previous_and_next_tracks_belong_to_media() {
        let result = model(vec![
            binding(
                "common",
                "bindl",
                "NONE,XF86AudioPrev,spawn,playerctl previous",
            ),
            binding("common", "bindl", "NONE,XF86AudioNext,spawn,playerctl next"),
        ]);
        assert!(result.iter().all(|entry| entry.group == 5));
    }

    #[test]
    fn toolbox_bilibili_and_release_voice_bindings_have_current_descriptions() {
        let result=entries(Export {version:1,bindings:vec![
            binding("default","bind","SUPER+SHIFT,D,toggle_named_scratchpad,mayon-tools,none,kitty mayon-tools"),
            binding("default","bind","SUPER+SHIFT,B,toggle_named_scratchpad,mayon-bili,none,kitty bilitui"),
            binding("default","bindr","SUPER+SHIFT,XF86Assistant,spawn,/nix/store/fixture-mayon-voice/bin/mayon-voice toggle"),
        ]}).unwrap();
        assert_eq!(result[0].description, "呼出或隐藏工具箱");
        assert_eq!(result[1].description, "呼出或隐藏 Bilibili TUI");
        assert_eq!(result[2].chord, "Super+Shift+XF86Assistant");
        assert!(result[2].description.starts_with("松开"));
    }
    #[test]
    fn fuzzy_matching_is_case_insensitive_and_supports_chinese_subsequences() {
        assert!(fuzzy("super x", "Super+Shift+X 打开工具箱"));
        assert!(fuzzy("文件管", "呼出或隐藏文件管理器 Yazi"));
        assert!(!fuzzy("浏览器", "打开文件管理器"));
        assert!(fuzzy("", "anything"));
    }

    #[test]
    fn control_alias_and_gesture_modifiers_are_normalized() {
        let result = model(vec![
            binding("default", "bind", "CTRL,X,one"),
            binding("default", "bind", "CONTROL,x,two"),
            binding("default", "gesturebind", "NONE,left,4,toggleoverview"),
            binding("default", "gesturebindl", "CTRL,left,4,toggleoverview"),
        ]);
        assert!(result[0].conflict && result[1].conflict);
        assert_eq!(result[3].chord, "Ctrl + 4指滑动 左");
        assert!(result[2].description.contains("切换窗口概览"));
    }

    #[test]
    fn mouse_actions_and_unknown_scratchpads_keep_readable_descriptions() {
        let result = model(vec![
            binding("default", "mousebind", "SUPER,btn_left,moveresize,curmove"),
            binding(
                "default",
                "bind",
                "SUPER,X,toggle_named_scratchpad,custom-tool,none,run custom",
            ),
            binding(
                "default",
                "bind",
                "SUPER,F1,spawn,${kitty} --title Mango-keybindings less keys.txt",
            ),
        ]);
        assert_eq!(result[0].description, "按住拖动窗口");
        assert!(result[1]
            .description
            .contains("toggle_named_scratchpad custom-tool"));
        assert_eq!(result[2].description, "查看 Mango 快捷键说明");
    }
}
