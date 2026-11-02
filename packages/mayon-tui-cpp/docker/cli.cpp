#include "cli.hpp"

#include <algorithm>
#include <stdexcept>

namespace dock {
bool parse_cli_args(const std::vector<std::string>& input, CliArgs& parsed, std::string& error) {
    for (size_t i = 0; i < input.size(); ++i) {
        const std::string& arg = input[i];
        if (arg == "--host") {
            if (i + 1 >= input.size()) {
                error = "--host requires unix:// endpoint";
                return false;
            }
            parsed.host = input[++i];
            continue;
        }
        if ((arg == "df" || arg == "clean") && !parsed.command) {
            parsed.command = arg;
            continue;
        }
        if (arg == "--yes") {
            parsed.yes = true;
            continue;
        }
        std::optional<cleanup::Kind> kind;
        if (arg == "--image") kind = cleanup::Kind::Image;
        else if (arg == "--container") kind = cleanup::Kind::Container;
        else if (arg == "--cache") kind = cleanup::Kind::Cache;
        else if (arg == "--volume") kind = cleanup::Kind::Volume;
        if (kind) {
            if (i + 1 >= input.size() || input[i + 1].empty() || input[i + 1].front() == '-') {
                error = "选择器需要完整 ID / 卷名";
                return false;
            }
            const std::string id = input[++i];
            const auto pair = std::make_pair(*kind, id);
            if (std::find(parsed.targets.begin(), parsed.targets.end(), pair) == parsed.targets.end()) parsed.targets.push_back(pair);
            continue;
        }
        error = "unknown argument; use --help";
        return false;
    }
    if (parsed.command != "clean" && (parsed.yes || !parsed.targets.empty())) {
        error = "--yes 与资源选择器仅用于 clean";
        return false;
    }
    if (parsed.command == "clean" && parsed.targets.empty()) {
        error = "clean 需要明确 ID / 卷名；不提供一键全清";
        return false;
    }
    return true;
}
std::vector<cleanup::Entry> plan_for(const std::vector<cleanup::Entry>& entries,
                                     const std::vector<std::pair<cleanup::Kind, std::string>>& targets) {
    std::vector<cleanup::Entry> plan;
    for (const auto& [kind, id] : targets) {
        const auto found = std::find_if(entries.begin(), entries.end(), [&](const cleanup::Entry& entry) {
            return entry.kind == kind && entry.id == id && entry.selectable();
        });
        if (found == entries.end()) {
            throw std::runtime_error(std::string("不可清理或不存在：") + cleanup::label(kind) + " " + id);
        }
        plan.push_back(*found);
    }
    return plan;
}
}  // namespace dock
