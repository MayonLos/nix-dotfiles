# Terminal

Installs Kitty and renders its configuration from `user.appearance`, including the shared ANSI palette and reduced-motion preference. Kitty uses its documented `tab_bar_style custom` hook to underline the active tab in the palette blue; other tabs stay on the deep background. Selecting this aspect makes Kitty configuration a complete managed file; Noctalia is not a second Kitty template writer.

Owned files are `default.nix`, `kitty.nix`, and `tab-bar.nix`, all private. Outputs are the Kitty package, `kitty/kitty.conf`, and `kitty/tab_bar.py`. Removing the aspect removes those declarations in the next generation; Kitty scrollback files and other user data remain intact.

The r43 reading surface uses `deep` at 0.96 background opacity, `brightFg` text,
11 pt Maple Mono NF CN and 10 pt padding.
The character grid is anchored at the top left; fractional-scale remainder strips
use the current terminal background so status markers cannot bleed into them. Neovim temporarily synchronizes the terminal
background with its Normal highlight through OSC 11, including tmux passthrough,
and restores the previous background on suspend/exit.
Tabs appear at the top only with two or more Kitty sessions. They show title
text without duplicate numeric indices; the active title uses a blue underline
and inactive titles use `fg`, all on `deep`. Prefer one Kitty tab when tmux owns
window navigation. Cursor, selection, underline and ANSI colors consume
the same palette. The underline uses Kitty's custom Python tab-bar renderer
because the built-in tab styles do not provide an active underline. Compositor blur must be supplied by the desktop owner (Mango); Kitty does not
change compositor rules. Headless Sway verifies opacity, cells and padding but
has no blur. Reduced motion disables cursor blinking and trail animation.
OSC 11 changes the default background at the same 0.96 opacity, so equal
application cells and padding remain seamless; it does not make Neovim opaque.

Maple Mono NF CN uses `calt` programming ligatures, `cv01` normalized symbols
and a dotted `zero`, across regular, bold and italic faces. These are native
features of the pinned Maple 7.9 font; explicit SemiBold/SemiBoldItalic selectors
also cover Fontconfig's automatic bold choice. See the [upstream feature list](https://github.com/subframe7536/maple-font/blob/v7/source/features/README.md).
Kitty scales cell height to 108% while preserving cell width and the CJK two-cell
grid. Neovim's TUI uses this terminal spacing; `linespace` is not a TUI control.
The setting also applies to tmux, btop and Lazygit. Cursor trails remain short
and honor reduced motion; Neovim supplies its own mode shapes and colors.
