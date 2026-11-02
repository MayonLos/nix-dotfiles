// Public entry of the ports tool: the page the toolbox embeds and its command line.
// Everything else lives in app.hpp and stays private to this directory.
#pragma once

#include <memory>
#include <string>
#include <vector>

#include "ui/page.hpp"

// Reads /proc and /etc/passwd on construction; the page refreshes every two seconds.
std::unique_ptr<tui::Page> make_ports_page();
// The same page for the tool arguments. Only `--docker-map` is meaningful.
std::unique_ptr<tui::Page> make_ports_page(const std::vector<std::string>& args);
// [--docker-map], --help/-h, --version. Without a non-interactive command it returns -1 and
// the caller opens make_ports_page(args) on its own terminal, like the Rust toolbox.
int ports_cli(int argc, char** argv);
