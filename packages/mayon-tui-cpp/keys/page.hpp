// Public entry of the keys tool: the page the toolbox embeds and its command line.
// Everything else here is private.
#pragma once
#include <memory>
#include <string>

#include "ui/page.hpp"

// Reads the default data path. A missing or invalid file shows an error state with `R` to
// retry rather than failing, like the Rust toolbox's error screen.
std::unique_ptr<tui::Page> make_keys_page();
// The same page for an explicit `--data` path.
std::unique_ptr<tui::Page> make_keys_page(const std::string& data_path);
// `argv[0]` is the tool name, as in main. [--data PATH] [list [--json]], --help, --version.
// Without `list` it opens the page on its own terminal. Returns the process exit code.
int keys_cli(int argc, char** argv);
