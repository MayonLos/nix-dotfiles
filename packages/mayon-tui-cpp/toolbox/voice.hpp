// Public entry of the voice dashboard: the page the toolbox embeds.
// Everything else here is private (see voice_internal.hpp).
//
// The page only reads the daemon's control socket through the protocol in
// packages/mayon-voice/src/lib.rs (`status` / `toggle` on
// $XDG_RUNTIME_DIR/mayon-voice/control.sock, one newline-terminated JSON line).
// Recording, models and delivery stay in mayon-voice; nothing is reimplemented here.
// `make_voice_page` throws std::runtime_error when config.toml is invalid, which the
// toolbox shows as its retryable error page, like the Rust toolbox.
#pragma once
#include <memory>

#include "ui/page.hpp"

std::unique_ptr<tui::Page> make_voice_page();
