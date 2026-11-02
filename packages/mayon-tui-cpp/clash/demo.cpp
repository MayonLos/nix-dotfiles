// Runs the page on its own for parity checks and screenshots; the toolbox is the real entry.
#include <csignal>
#include <exception>
#include <iostream>
#include <string>
#include <vector>

#include "page.hpp"
#include "ui/page.hpp"

int main(int argc, char** argv) {
    std::signal(SIGPIPE, SIG_IGN);
    std::vector<std::string> args;
    for (int i = 1; i < argc; ++i) args.emplace_back(argv[i]);
    try {
        auto page = make_clash_page(args);
        return tui::run_page(*page);
    } catch (const std::exception& failure) {
        std::cerr << "Clash TUI：" << failure.what() << "\n";
        return 1;
    }
}
