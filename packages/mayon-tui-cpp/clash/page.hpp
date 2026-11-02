// Public entry of the clash tool: the page the toolbox embeds. Everything else here is private.
#pragma once
#include <memory>

#include "ui/page.hpp"

std::unique_ptr<tui::Page> make_clash_page();
