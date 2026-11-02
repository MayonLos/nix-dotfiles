// Public entry of the docker tool: the page the toolbox embeds. Everything else here is private.
#pragma once
#include <memory>

#include "ui/page.hpp"

std::unique_ptr<tui::Page> make_docker_page();
