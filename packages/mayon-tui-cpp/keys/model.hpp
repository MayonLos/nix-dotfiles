// Private: turns the generated Mango export into described, grouped, conflict-marked rows.
#pragma once
#include <array>
#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace keys {
inline constexpr std::array<std::string_view, 7> kGroups{"窗口", "工作区", "应用", "TUI 工具", "截图", "媒体", "系统"};

struct Binding {
    std::string mode;
    std::string kind;
    std::string raw;
};
struct Export {
    uint32_t version = 0;
    std::vector<Binding> bindings;
};
struct Entry {
    Binding binding;
    std::string chord;
    std::string action;
    size_t group = 0;
    std::string description;
    bool conflict = false;
};
// A failure with the same two levels the command line prints: message, then "Caused by".
struct Error : std::runtime_error {
    Error(const std::string& message, std::string detail = {}) : std::runtime_error(message), cause(std::move(detail)) {}
    std::string cause;
};

// Rust's str::trim and split_whitespace treat the same Unicode set as white space.
bool is_space(char32_t ch);
std::string_view trim_unicode(std::string_view text);

std::vector<Entry> entries(const Export& data);
// Throws Error on anything that is not a version 1 export of string fields.
Export parse_export(std::string_view json);
// KEYS_MAYON_DATA, then $XDG_CONFIG_HOME or ~/.config; throws Error when none is set.
std::string default_data_path();
// `list --json`: byte compatible with the Rust tool's pretty printer.
std::string to_json(const std::vector<Entry>& items);
// `list`: the plain text form.
std::string to_text(const std::vector<Entry>& items);
}  // namespace keys
