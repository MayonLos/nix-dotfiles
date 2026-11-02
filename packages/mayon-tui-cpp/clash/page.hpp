// Public entry of the clash tool: the page the toolbox embeds and its command line.
// Everything else in this directory is private.
#pragma once
#include <memory>
#include <string>
#include <vector>

#include "ui/page.hpp"

// The interactive page with default paths. Preferences come from
// $XDG_CONFIG_HOME/mayon-tui/clash.toml unless present in `args`.
std::unique_ptr<tui::Page> make_clash_page();
// The same page for the main program's arguments (after argv[0]).
std::unique_ptr<tui::Page> make_clash_page(const std::vector<std::string>& args);
// `argv[0]` is the tool name, as in main. Handles
// `profile add|list|update|use|rename|url|delete|generate`, `settings KEY VALUE`,
// `service start|stop` and the global options. Returns -1 when no non-interactive
// subcommand is present (the caller then runs the page), >= 0 after handling one,
// and 1 with the Rust error text on stderr for invalid arguments.
int clash_cli(int argc, char** argv);
