// Runs the tool on its own for parity checks and screenshots; the toolbox is the real entry.
#include <exception>
#include <iostream>
#include <string>
#include <vector>

#include "page.hpp"

int main(int argc, char** argv) {
    const int code = docker_cli(argc, argv);
    if (code >= 0) return code;
    std::vector<std::string> args;
    for (int i = 1; i < argc; ++i) args.emplace_back(argv[i]);
    auto page = make_docker_page(args);
    try {
        return tui::run_page(*page);
    } catch (const std::exception& error) {
        std::cerr << "Error: " << error.what() << "\n";
        return 1;
    }
}
