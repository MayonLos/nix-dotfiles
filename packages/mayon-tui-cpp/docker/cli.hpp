// Command-line parsing shared by the docker CLI and its tests. Private to this tool.
#pragma once
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "cleanup.hpp"

namespace dock {
struct CliArgs {
    std::optional<std::string> host;
    std::optional<std::string> command;
    std::vector<std::pair<cleanup::Kind, std::string>> targets;
    bool yes = false;
};
// Matches the Rust parse_args exactly: unknown arguments, selector shape and the
// no-blanket-cleanup rule all return the Rust message in `error`.
bool parse_cli_args(const std::vector<std::string>& input, CliArgs& parsed, std::string& error);
std::vector<cleanup::Entry> plan_for(const std::vector<cleanup::Entry>& entries,
                                     const std::vector<std::pair<cleanup::Kind, std::string>>& targets);
}  // namespace dock
