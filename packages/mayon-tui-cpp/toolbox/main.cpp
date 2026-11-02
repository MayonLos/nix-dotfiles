// mayon-tools-next: the five-page toolbox. Page code stays in each tool directory;
// this file only dispatches subcommands and composes the pages behind the tab bar.
//
// Rust behaviour mirrored from packages/mayon-tui/crates/tools/src/main.rs: Ports is the
// default page, `[`/`]` switch while no page has a text cursor, a click on the tab row
// switches, pages are built on first visit, hidden pages stop refreshing, and every
// non-interactive subcommand goes to the tool's own `*_cli`.
#include <algorithm>
#include <array>
#include <exception>
#include <iostream>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "docker/page.hpp"
#include "keys/page.hpp"
#include "ports/page.hpp"
#include "serial/page.hpp"
#include "shell.hpp"
#include "ui/page.hpp"
#include "voice.hpp"

namespace {
constexpr const char* kVersion = "mayon-tools 0.2.0";
constexpr const char* kHelp =
    "mayon-tools [docker|ports|serial|keys|voice] [参数]\n"
    "\n"
    "默认打开 Ports；[ / ] 切换工具，内部数字键保留。\n"
    "mayon-tools docker df|clean ...\n"
    "mayon-tools ports --help\n"
    "mayon-tools serial list|<端口> [-b 波特率]\n"
    "mayon-tools keys list [--json]\n";
constexpr const char* kVoiceError = "mayon-tools voice 没有非交互子命令；录音命令仍由 mayon-voice 提供";
constexpr const char* kUnknown = "未知工具；请运行 mayon-tools --help";

int fail(const std::string& message) {
    std::cerr << "Error: " << message << "\n";
    return 1;
}

// argv[0] is the tool name for every `*_cli`, like the standalone binaries.
struct Argv {
    explicit Argv(std::vector<std::string> values_in) : values(std::move(values_in)) {
        pointers.reserve(values.size() + 1);
        for (std::string& value : values) pointers.push_back(value.data());
        pointers.push_back(nullptr);
    }
    int argc() const { return static_cast<int>(values.size()); }
    std::vector<std::string> values;
    std::vector<char*> pointers;
};

Argv tool_argv(size_t page, const std::vector<std::string>& args) {
    std::vector<std::string> values{toolbox::kTools[page].name};
    values.insert(values.end(), args.begin(), args.end());
    return Argv(std::move(values));
}

// The embedded keys page only understands `--data PATH`; everything else is the CLI's.
// `embed` stays true only when the arguments are just --data pairs, the case where the
// Rust toolbox opens the page; keys_cli would otherwise start its own terminal.
std::optional<std::string> keys_page_path(const std::vector<std::string>& args, bool& embed) {
    embed = true;
    std::optional<std::string> path;
    for (size_t i = 0; i < args.size(); ++i) {
        if (args[i] != "--data" || i + 1 >= args.size()) {
            embed = false;
            return std::nullopt;
        }
        if (!path) path = args[i + 1];
        ++i;
    }
    return path;
}

// Returns -1 when the toolbox should open the page instead of exiting.
int dispatch(size_t page, const std::vector<std::string>& args) {
    switch (page) {
        case 0: {
            Argv argv = tool_argv(0, args);
            return docker_cli(argv.argc(), argv.pointers.data());
        }
        case 1: {
            Argv argv = tool_argv(1, args);
            return ports_cli(argv.argc(), argv.pointers.data());
        }
        case 2: {
            Argv argv = tool_argv(2, args);
            return serial_cli(argv.argc(), argv.pointers.data());
        }
        case 3: {
            bool embed = false;
            keys_page_path(args, embed);
            if (embed) return -1;
            Argv argv = tool_argv(3, args);
            return keys_cli(argv.argc(), argv.pointers.data());
        }
        default:
            if (!args.empty()) {
                fail(kVoiceError);
                return 1;
            }
            return -1;
    }
}

std::unique_ptr<tui::Page> make_keys(const std::vector<std::string>& args) {
    bool embed = true;
    const auto path = keys_page_path(args, embed);
    return path ? make_keys_page(*path) : make_keys_page();
}

std::array<toolbox::Factory, 5> factories() {
    return {{
        [](const std::vector<std::string>& args) { return make_docker_page(args); },
        [](const std::vector<std::string>& args) { return make_ports_page(args); },
        [](const std::vector<std::string>& args) { return make_serial_page(args); },
        [](const std::vector<std::string>& args) { return make_keys(args); },
        [](const std::vector<std::string>&) { return make_voice_page(); },
    }};
}
}  // namespace

int main(int argc, char** argv) {
    std::vector<std::string> args;
    for (int i = 1; i < argc; ++i) args.emplace_back(argv[i]);
    if (!args.empty() && (args.front() == "--help" || args.front() == "-h")) {
        std::cout << kHelp;
        return 0;
    }
    if (!args.empty() && args.front() == "--version") {
        std::cout << kVersion << "\n";
        return 0;
    }
    size_t page = 1;
    std::vector<std::string> rest;
    if (!args.empty()) {
        const auto found = std::find_if(toolbox::kTools.begin(), toolbox::kTools.end(), [&](const toolbox::Tool& tool) { return args.front() == tool.name; });
        if (found == toolbox::kTools.end()) return fail(kUnknown);
        page = static_cast<size_t>(found - toolbox::kTools.begin());
        rest.assign(args.begin() + 1, args.end());
    }
    try {
        const int code = dispatch(page, rest);
        if (code >= 0) return code;
        std::vector<std::vector<std::string>> page_args(toolbox::kTools.size());
        page_args[page] = rest;
        toolbox::Shell shell(factories(), page, std::move(page_args));
        return tui::run_page(shell);
    } catch (const std::exception& error) {
        return fail(error.what());
    }
}
