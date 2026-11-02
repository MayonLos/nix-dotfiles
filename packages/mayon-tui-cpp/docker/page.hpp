// Public entry of the docker tool: the page the toolbox embeds and its command line.
// Everything else in this directory is private.
#pragma once
#include <memory>
#include <string>
#include <vector>

#include "ui/page.hpp"

// Docker-only page. It does not connect before the page is first activated and shows the
// unavailable state when no Docker socket is configured.
std::unique_ptr<tui::Page> make_docker_page();
// Same page with the tool's own arguments; only `--host` matters here.
std::unique_ptr<tui::Page> make_docker_page(const std::vector<std::string>& args);
// `argv[0]` is the tool name. Handles --help/--version, df and clean with the Rust output,
// messages and exit codes. Returns -1 when the caller should open the TUI.
int docker_cli(int argc, char** argv);
