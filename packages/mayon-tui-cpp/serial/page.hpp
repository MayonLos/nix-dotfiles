// Public entry of the serial tool: the page the toolbox embeds and its command line.
// Everything else in this directory is private.
//
// The page keeps the Rust tool's keys, capture limits and the shared serial-mayon data
// directories, so both versions can use one profile. One deliberate addition: the UI asks
// for confirmation before running the configured flash command (the Rust F5 runs it
// immediately). The key is X instead of F5 because the shared input parser does not decode
// function keys yet.
#pragma once
#include <memory>
#include <string>
#include <vector>

#include "ui/page.hpp"

std::unique_ptr<tui::Page> make_serial_page();
// Same page with `argv[1..]` from the command line: `<port> [-b baud]`.
std::unique_ptr<tui::Page> make_serial_page(const std::vector<std::string>& args);
// `argv[0]` is the tool name. Handles `list`, `--help`/`-h` and validates
// `<port> [-b baud]`. Returns 0 when a non-interactive command ran, 1 on argument
// errors (message on stderr), and -1 when the caller should open the TUI.
int serial_cli(int argc, char** argv);
