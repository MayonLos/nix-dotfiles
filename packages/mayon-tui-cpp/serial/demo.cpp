// Runs the tool on its own for parity checks and screenshots; the toolbox is the real entry.
#include <unistd.h>

#include <exception>
#include <iostream>
#include <string>
#include <vector>

#include "page.hpp"
#include "ui/page.hpp"

int main(int argc, char** argv) {
    const int code = serial_cli(argc, argv);
    if (code >= 0) return code;
    // Refuse before touching the store when there is no terminal: the page would otherwise
    // create the private data directories and then fail while switching the terminal to raw mode.
    if (::isatty(STDIN_FILENO) == 0 || ::isatty(STDOUT_FILENO) == 0) {
        std::cerr << "Error: 打开串口 TUI 需要终端\n";
        return 1;
    }
    std::vector<std::string> args;
    for (int i = 1; i < argc; ++i) args.emplace_back(argv[i]);
    try {
        auto page = make_serial_page(args);
        return tui::run_page(*page);
    } catch (const std::exception& error) {
        std::cerr << "Error: " << error.what() << "\n";
        return 1;
    }
}
