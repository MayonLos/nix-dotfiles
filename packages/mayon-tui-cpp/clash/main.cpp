// clashtui-next: no subcommand opens the TUI; profile/settings/service run headless.
#include <csignal>
#include <iostream>
#include <string>
#include <vector>

#include "app.hpp"
#include "page.hpp"
#include "ui/page.hpp"

int main(int argc, char** argv) {
    std::signal(SIGPIPE, SIG_IGN);
    std::vector<std::string> args;
    for (int i = 1; i < argc; ++i) args.emplace_back(argv[i]);
    const bool subcommand = !args.empty() && (args.front() == "profile" || args.front() == "settings" || args.front() == "service");
    if (subcommand) return clash_cli(argc, argv);
    clash::Options options;
    std::string error;
    const auto parsed = clash::parse_options(args, options, error);
    if (parsed == clash::ParseResult::Exit) return 0;
    if (parsed == clash::ParseResult::Error) {
        std::cerr << "Clash TUI：" << error << "\n";
        return 1;
    }
    try {
        auto page = make_clash_page(args);
        return tui::run_page(*page);
    } catch (const std::exception& failure) {
        std::cerr << "Clash TUI：" << failure.what() << "\n";
        return 1;
    }
}
