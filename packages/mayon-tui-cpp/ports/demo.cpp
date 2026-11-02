// Runs the tool on its own for parity checks and screenshots; the toolbox is the real entry.
#include <iostream>
#include <string>
#include <vector>

#include "page.hpp"

int main(int argc, char** argv) {
    std::vector<std::string> args;
    for (int i = 1; i < argc; ++i) args.emplace_back(argv[i]);
    const int code = ports_cli(argc, argv);
    if (code >= 0) return code;
    const auto page = make_ports_page(args);
    return tui::run_page(*page);
}
