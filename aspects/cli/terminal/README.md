# Terminal

Installs Kitty and renders its configuration from `user.appearance`, including the shared ANSI palette and reduced-motion preference. Kitty uses its documented `tab_bar_style custom` hook to underline the active tab in the palette blue; other tabs stay on the deep background. Selecting this aspect makes Kitty configuration a complete managed file; Noctalia is not a second Kitty template writer.

Owned files are `default.nix`, `kitty.nix`, and `tab-bar.nix`, all private. Outputs are the Kitty package, `kitty/kitty.conf`, and `kitty/tab_bar.py`. Removing the aspect removes those declarations in the next generation; Kitty scrollback files and other user data remain intact.

The Astra §8 reading surface is opaque `deep` with `brightFg` text and 12 padding.
Tabs stay on the `deep` background; the active tab uses a blue underline and
inactive titles use `fg`. Cursor, selection, underline and ANSI colors consume
the same palette. The underline uses Kitty's custom Python tab-bar renderer
because the built-in tab styles do not provide an active underline. No
compositor blur rule is required; reduced motion disables cursor blinking and
trail animation.
