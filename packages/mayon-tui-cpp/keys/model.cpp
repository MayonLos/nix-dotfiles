#include "model.hpp"

#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <nlohmann/json.hpp>
#include <optional>
#include <set>
#include <unordered_set>

#include "ui/text.hpp"

namespace keys {
namespace {
enum class Device { Keyboard, Pointer, Gesture };
struct Parsed {
    std::string chord;
    std::string normalized;
    std::string action;
    std::vector<std::string> args;
    Device device = Device::Keyboard;
};
std::string ascii_lower(std::string_view text) {
    std::string out(text);
    for (char& ch : out) {
        if (ch >= 'A' && ch <= 'Z') ch = static_cast<char>(ch + 32);
    }
    return out;
}
std::string ascii_upper(std::string_view text) {
    std::string out(text);
    for (char& ch : out) {
        if (ch >= 'a' && ch <= 'z') ch = static_cast<char>(ch - 32);
    }
    return out;
}
std::vector<std::string_view> split(std::string_view text, char separator) {
    std::vector<std::string_view> out;
    while (true) {
        const auto at = text.find(separator);
        out.push_back(text.substr(0, at));
        if (at == std::string_view::npos) return out;
        text.remove_prefix(at + 1);
    }
}
std::string join(const std::vector<std::string>& parts, std::string_view separator) {
    std::string out;
    for (size_t i = 0; i < parts.size(); ++i) {
        if (i > 0) out += separator;
        out += parts[i];
    }
    return out;
}
bool has(std::string_view text, std::string_view part) { return text.find(part) != std::string_view::npos; }
bool any_of(std::string_view value, std::initializer_list<std::string_view> options) {
    return std::find(options.begin(), options.end(), value) != options.end();
}
size_t modifier_order(std::string_view value) {
    if (value == "SUPER") return 0;
    if (value == "CTRL" || value == "CONTROL") return 1;
    if (value == "ALT") return 2;
    if (value == "SHIFT") return 3;
    return 4;
}
// Display form, then the form conflicts compare.
std::pair<std::string, std::string> normalize_modifiers(std::string_view modifiers) {
    std::vector<std::string> mods;
    for (const std::string_view part : split(modifiers, '+')) {
        std::string value = ascii_upper(trim_unicode(part));
        if (value == "CONTROL") value = "CTRL";
        if (!value.empty() && value != "NONE") mods.push_back(std::move(value));
    }
    std::stable_sort(mods.begin(), mods.end(), [](const std::string& a, const std::string& b) { return modifier_order(a) < modifier_order(b); });
    mods.erase(std::unique(mods.begin(), mods.end()), mods.end());
    std::vector<std::string> display;
    for (const std::string& modifier : mods) {
        if (modifier == "SUPER") display.emplace_back("Super");
        else if (modifier == "CTRL") display.emplace_back("Ctrl");
        else if (modifier == "ALT") display.emplace_back("Alt");
        else if (modifier == "SHIFT") display.emplace_back("Shift");
        else display.push_back(modifier);
    }
    return {join(display, "+"), join(mods, "+")};
}
std::string key_name(std::string_view value) {
    static const std::vector<std::pair<std::string_view, std::string_view>> names{
        {"return", "Enter"},
        {"escape", "Esc"},
        {"space", "Space"},
        {"grave", "`"},
        {"page_up", "PageUp"},
        {"page_down", "PageDown"},
        {"left", "Left"},
        {"right", "Right"},
        {"up", "Up"},
        {"down", "Down"},
        {"minus", "-"},
        {"equal", "="},
        {"print", "Print"},
        {"xf86audioraisevolume", "AudioRaiseVolume"},
        {"xf86audiolowervolume", "AudioLowerVolume"},
        {"xf86audiomute", "AudioMute"},
        {"xf86audiomicmute", "AudioMicMute"},
        {"xf86monbrightnessup", "MonBrightnessUp"},
        {"xf86monbrightnessdown", "MonBrightnessDown"},
        {"xf86audioplay", "AudioPlay"},
        {"xf86audiostop", "AudioStop"},
        {"xf86audioprev", "AudioPrev"},
        {"xf86audionext", "AudioNext"},
    };
    const std::string lower = ascii_lower(value);
    for (const auto& [from, to] : names) {
        if (lower == from) return std::string(to);
    }
    return std::string(value);
}
std::string_view direction_name(std::string_view direction) {
    const std::string lower = ascii_lower(direction);
    if (any_of(lower, {"left", "previous", "prev"})) return "左";
    if (any_of(lower, {"right", "next"})) return "右";
    if (lower == "up") return "上";
    if (lower == "down") return "下";
    return "未知";
}
Parsed parse_binding(const Binding& binding) {
    std::vector<std::string_view> fields = split(binding.raw, ',');
    for (std::string_view& field : fields) field = trim_unicode(field);
    const bool gesture = binding.kind.starts_with("gesturebind");
    if (fields.size() < (gesture ? 4U : 3U)) throw Error("invalid " + binding.kind + " binding: " + binding.raw);
    Parsed parsed;
    size_t action_index = 2;
    if (gesture) {
        const auto [display, normalized] = normalize_modifiers(fields[0]);
        const std::string direction(fields[1]);
        const std::string fingers(fields[2]);
        parsed.chord = (display.empty() ? "" : display + " + ") + fingers + "指滑动 " + std::string(direction_name(direction));
        parsed.normalized = "gesture:" + normalized + ":" + ascii_lower(direction) + ":" + fingers;
        parsed.device = Device::Gesture;
        action_index = 3;
    } else {
        const auto [display, normalized] = normalize_modifiers(fields[0]);
        const std::string key = key_name(fields[1]);
        parsed.chord = display.empty() ? key : display + "+" + key;
        parsed.normalized = normalized + "+" + ascii_lower(fields[1]);
        parsed.device = binding.kind.starts_with("mousebind") ? Device::Pointer : Device::Keyboard;
    }
    parsed.action = std::string(fields[action_index]);
    for (size_t i = action_index + 1; i < fields.size(); ++i) parsed.args.emplace_back(fields[i]);
    return parsed;
}
bool modes_overlap(std::string_view left, std::string_view right) { return left == "common" || right == "common" || left == right; }
std::string arg(const Parsed& parsed, size_t index, std::string_view fallback = "") {
    return std::string(index < parsed.args.size() ? std::string_view(parsed.args[index]) : fallback);
}
std::string media_description(const std::string& raw) {
    if (has(raw, "play-pause")) return "播放或暂停";
    if (has(raw, "previous")) return "上一首";
    if (has(raw, "next")) return "下一首";
    if (has(raw, "stop")) return "停止播放";
    return "媒体控制：" + raw;
}
std::string describe_spawn(const std::vector<std::string>& args, const Binding& binding) {
    const std::string raw = join(args, " ");
    const std::string lower = ascii_lower(raw);
    // First match wins, so this order is part of the behaviour.
    static const std::vector<std::pair<std::string_view, std::string_view>> before_media{
        {"workspace-files", "打开文件管理器"},
        {"workspace-browser", "打开浏览器"},
        {"workspace-terminal", "打开终端"},
        {"herdr-terminal", "打开 Herdr 终端代理"},
        {"mango-keybindings", "查看 Mango 快捷键说明"},
        {"/less ", "查看 Mango 快捷键说明"},
        {"launchpad", "打开应用启动器"},
        {"window-switcher", "按住 Alt 切换窗口，松开确认"},
        {"notification-dnd-toggle", "切换勿扰模式"},
        {"caffeine-toggle", "切换防休眠"},
        {"panel-toggle control-center", "打开控制中心"},
        {"panel-toggle launcher", "打开启动器"},
        {"panel-toggle session", "打开会话菜单"},
        {"panel-toggle clipboard", "打开剪贴板历史"},
        {"session lock", "锁定屏幕"},
        {"wallpaper-random", "随机更换壁纸"},
        {"mark-shot", "区域截图"},
        {"screenshot-screen", "截图并复制全屏"},
        {"wayscrollshot", "滚动截图"},
        {"ocr-region", "识别选区文字"},
        {"ocr-screen", "识别全屏文字"},
        {"headset-mic", "切换蓝牙耳机麦克风"},
    };
    for (const auto& [needle, text] : before_media) {
        if (has(lower, needle)) return std::string(text);
    }
    if (has(lower, "playerctl")) return media_description(lower);
    static const std::vector<std::pair<std::string_view, std::string_view>> after_media{
        {"mic-mute", "切换麦克风静音"},
        {"volume-up", "调高音量"},
        {"volume-down", "调低音量"},
        {"volume-mute", "切换静音"},
        {"brightness-up", "调亮屏幕"},
        {"brightness-down", "调暗屏幕"},
    };
    for (const auto& [needle, text] : after_media) {
        if (has(lower, needle)) return std::string(text);
    }
    if (has(raw, "mayon-voice") || (has(raw, "toggle") && has(binding.raw, "mayonVoice"))) {
        return binding.kind == "bindr" ? "松开录音键开始或停止语音输入" : "开始或停止语音输入";
    }
    return "启动：" + raw;
}
std::string scratchpad_description(const std::vector<std::string>& args) {
    const std::string id = args.empty() ? "" : args[0];
    if (id == "mayon-scratch") return "呼出或隐藏临时终端";
    if (id == "mayon-files") return "呼出或隐藏文件管理器 Yazi";
    if (id == "mayon-monitor") return "呼出或隐藏系统监视器 btop";
    if (id == "mayon-clash") return "呼出或隐藏 Clash TUI";
    if (id == "mayon-tools") return "呼出或隐藏工具箱";
    if (id == "mayon-bili") return "呼出或隐藏 Bilibili TUI";
    return args.empty() ? "toggle_named_scratchpad" : "toggle_named_scratchpad " + join(args, " ");
}
std::string describe_action(const Binding& binding, const Parsed& parsed) {
    const std::string& action = parsed.action;
    const std::string first = arg(parsed, 0);
    const std::string direction(direction_name(first));
    if (action == "spawn") return describe_spawn(parsed.args, binding);
    if (action == "focusdir") return "聚焦" + direction + "方向窗口";
    if (action == "move_client") return "将窗口移向" + direction;
    if (action == "tagmon") return "将窗口移到" + direction + "侧显示器";
    if (action == "viewtoright" || action == "viewnext_have_client") return "切换到下一个占用工作区";
    if (action == "viewtoleft" || action == "viewprev_have_client") return "切换到上一个占用工作区";
    if (action == "overcircle") return has(first, "prev") ? "切换到同工作区上一个窗口" : "切换到同工作区下一个窗口";
    if (action == "tagtoright") return "将窗口移到右侧工作区";
    if (action == "tagtoleft") return "将窗口移到左侧工作区";
    if (action == "view") return "切换到工作区 " + arg(parsed, 0, "?");
    if (action == "tagsilent") return "移到工作区 " + arg(parsed, 0, "?") + "，留在当前页";
    if (action == "tag") return "移到工作区 " + arg(parsed, 0, "?") + " 并跟随";
    if (action == "focusstack") return first == "prev" ? "切换到上一个窗口" : "切换到下一个窗口";
    if (action == "focuslast") return "返回上一个窗口";
    if (action == "switcher") return "切换器：向前切换一项";
    if (action == "toggleoverview") return "切换窗口概览";
    if (action == "togglejump") return "切换跳转标签";
    if (action == "toggle_special_tag") return "切换特殊工作区";
    if (action == "setkeymode") return "切换按键模式：" + join(parsed.args, " ");
    if (action == "incnmaster") return std::string("主窗口数量 ") + (first.starts_with('-') ? "减少" : "增加") + " " + first;
    if (action == "setmfact") return "调整主区域比例：" + join(parsed.args, " ");
    if (action == "togglemaximizescreen") return "切换最大化";
    if (action == "togglefullscreen") return "切换全屏";
    if (action == "centerwin") return "居中窗口";
    if (action == "resizewin") return "调整窗口大小：" + join(parsed.args, "，");
    if (action == "togglefloating") return "切换浮动窗口";
    if (action == "switch_layout") return "切换布局";
    if (action == "zoom") return "将当前窗口与主窗口交换";
    if (action == "togglegaps") return "切换窗口间距";
    if (action == "switch_proportion_preset") return "切换滚动布局比例";
    if (action == "minimized") return "最小化窗口";
    if (action == "toggle_scratchpad") return "找回最小化窗口";
    if (action == "toggle_named_scratchpad") return scratchpad_description(parsed.args);
    if (action == "moveresize") {
        if (first == "curmove") return "按住拖动窗口";
        if (first == "curresize") return "按住调整窗口大小";
        return "移动或调整窗口：" + first;
    }
    if (action == "toggleglobal") return "切换跨工作区显示";
    if (action == "toggleoverlay") return "切换窗口置顶";
    if (action == "tag_special_silent") return "移入或取回特殊工作区窗口";
    if (action == "sleep_monitor") return "关闭显示器";
    if (action == "wakeup_monitor") return "唤醒显示器";
    if (action == "reload_config") return "重载 Mango 配置";
    if (action == "killclient") return "关闭当前窗口";
    return parsed.args.empty() ? action : action + " " + join(parsed.args, " ");
}
std::string describe(const Binding& binding, const Parsed& parsed) {
    std::string description = describe_action(binding, parsed);
    if (!binding.kind.starts_with("gesturebind")) return description;
    // The raw, untrimmed fields, exactly as the Rust tool reads them.
    const auto fields = split(binding.raw, ',');
    const std::string fingers(fields.size() > 2 ? fields[2] : std::string_view("?"));
    const std::string direction(direction_name(fields.size() > 1 ? fields[1] : std::string_view()));
    return fingers + "指滑动 " + direction + "：" + description;
}
size_t group_for(const Parsed& parsed, const std::string& description) {
    const std::string& action = parsed.action;
    const bool spawn = action == "spawn";
    if (spawn && std::any_of(parsed.args.begin(), parsed.args.end(), [](const std::string& item) { return has(item, "playerctl "); })) return 5;
    if (action == "focusdir") return 0;
    if (any_of(action, {"viewnext_have_client", "viewprev_have_client"})) return 1;
    if (action == "toggle_named_scratchpad") return 3;
    if (spawn && has(description, "切换窗口")) return 0;
    if (any_of(action, {"view", "viewtoright", "viewtoleft", "tag", "tagsilent", "tagtoright", "tagtoleft", "toggle_special_tag", "tag_special_silent", "togglejump"})) return 1;
    if (any_of(action, {"move_client", "tagmon", "overcircle", "focusstack", "focuslast", "toggleoverview", "switcher", "setkeymode", "incnmaster", "setmfact", "togglemaximizescreen",
                        "togglefullscreen", "centerwin", "resizewin", "moveresize", "togglefloating", "switch_layout", "zoom", "togglegaps", "switch_proportion_preset", "minimized",
                        "toggle_scratchpad", "toggleglobal", "toggleoverlay", "killclient"})) {
        return 0;
    }
    if (has(description, "截图") || has(description, "识别")) return 4;
    if (has(description, "播放") || has(description, "音量") || has(description, "静音") || has(description, "麦克风") || has(description, "耳机")) return 5;
    if (any_of(description, {"锁定屏幕", "切换勿扰模式", "切换防休眠", "打开控制中心", "打开会话菜单", "随机更换壁纸", "调亮屏幕", "调暗屏幕"})) return 6;
    return spawn ? 2 : 6;
}
}  // namespace

bool is_space(char32_t ch) {
    return (ch >= 0x09 && ch <= 0x0D) || ch == 0x20 || ch == 0x85 || ch == 0xA0 || ch == 0x1680 || (ch >= 0x2000 && ch <= 0x200A) || ch == 0x2028 || ch == 0x2029 || ch == 0x202F ||
           ch == 0x205F || ch == 0x3000;
}
std::string_view trim_unicode(std::string_view text) {
    const std::u32string chars = tui::decode(text);
    size_t first = 0;
    size_t last = chars.size();
    while (first < last && is_space(chars[first])) ++first;
    while (last > first && is_space(chars[last - 1])) --last;
    // Byte offsets of the kept range, found by re-encoding what was dropped.
    const size_t lead = tui::encode(std::u32string_view(chars).substr(0, first)).size();
    const size_t tail = tui::encode(std::u32string_view(chars).substr(last)).size();
    return text.substr(lead, text.size() - lead - tail);
}
std::vector<Entry> entries(const Export& data) {
    if (data.version != 1) throw Error("unsupported keybinding export version " + std::to_string(data.version));
    std::vector<Parsed> parsed;
    parsed.reserve(data.bindings.size());
    for (const Binding& binding : data.bindings) parsed.push_back(parse_binding(binding));
    std::unordered_set<size_t> conflicts;
    for (size_t left = 0; left < parsed.size(); ++left) {
        for (size_t right = left + 1; right < parsed.size(); ++right) {
            if (parsed[left].device != parsed[right].device || parsed[left].normalized != parsed[right].normalized) continue;
            if (!modes_overlap(data.bindings[left].mode, data.bindings[right].mode)) continue;
            conflicts.insert(left);
            conflicts.insert(right);
        }
    }
    std::vector<Entry> out;
    out.reserve(parsed.size());
    for (size_t i = 0; i < parsed.size(); ++i) {
        std::string description = describe(data.bindings[i], parsed[i]);
        const size_t group = group_for(parsed[i], description);
        out.push_back(Entry{data.bindings[i], std::move(parsed[i].chord), std::move(parsed[i].action), group, std::move(description), conflicts.contains(i)});
    }
    return out;
}
Export parse_export(std::string_view text) {
    using nlohmann::json;
    const std::string invalid = "快捷键 JSON 格式无效";
    json root;
    try {
        root = json::parse(text);
    } catch (const json::exception& error) {
        throw Error(invalid, error.what());
    }
    const auto string_field = [&](const json& row, const char* name) -> std::string {
        const auto found = row.find(name);
        if (found == row.end()) throw Error(invalid, std::string("missing field `") + name + "`");
        if (!found->is_string()) throw Error(invalid, std::string("field `") + name + "` is not a string");
        return found->get<std::string>();
    };
    if (!root.is_object()) throw Error(invalid, "expected an object");
    const auto version = root.find("version");
    if (version == root.end()) throw Error(invalid, "missing field `version`");
    if (!version->is_number_unsigned() || version->get<uint64_t>() > UINT32_MAX) throw Error(invalid, "field `version` is not a u32");
    const auto bindings = root.find("bindings");
    if (bindings == root.end()) throw Error(invalid, "missing field `bindings`");
    if (!bindings->is_array()) throw Error(invalid, "field `bindings` is not an array");
    Export out;
    out.version = version->get<uint32_t>();
    out.bindings.reserve(bindings->size());
    for (const json& row : *bindings) {
        if (!row.is_object()) throw Error(invalid, "a binding is not an object");
        std::string mode = string_field(row, "mode");
        std::string kind = string_field(row, "kind");
        out.bindings.push_back(Binding{std::move(mode), std::move(kind), string_field(row, "raw")});
    }
    return out;
}
std::string default_data_path() {
    if (const char* path = std::getenv("KEYS_MAYON_DATA")) return path;
    if (const char* base = std::getenv("XDG_CONFIG_HOME")) return (std::filesystem::path(base) / "keys-mayon/bindings.json").string();
    if (const char* home = std::getenv("HOME")) return (std::filesystem::path(home) / ".config/keys-mayon/bindings.json").string();
    throw Error("缺少 XDG_CONFIG_HOME / HOME，请用 --data 指定生成的 JSON");
}
std::string to_json(const std::vector<Entry>& items) {
    // nlohmann sorts keys and escapes like serde_json without preserve_order.
    nlohmann::json out = nlohmann::json::array();
    for (const Entry& entry : items) {
        out.push_back({{"mode", entry.binding.mode},
                       {"kind", entry.binding.kind},
                       {"raw", entry.binding.raw},
                       {"chord", entry.chord},
                       {"group", std::string(kGroups[entry.group])},
                       {"description", entry.description},
                       {"conflict", entry.conflict}});
    }
    return out.dump(2) + "\n";
}
std::string to_text(const std::vector<Entry>& items) {
    std::string out;
    for (size_t group = 0; group < kGroups.size(); ++group) {
        out += "\n" + std::string(kGroups[group]) + "\n";
        for (const Entry& entry : items) {
            if (entry.group != group) continue;
            out += (entry.conflict ? "冲突 " : "") + entry.chord + " [" + entry.binding.mode + " · " + entry.binding.kind + "] " + entry.description + "\n  " + entry.binding.raw + "\n";
        }
    }
    return out;
}
}  // namespace keys
