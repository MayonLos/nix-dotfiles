# Themes and config ownership

Noctalia renders the live palette for GTK, Qt, Kitty, zathura, Chrome (via a local user template, not the community catalog — see media and messaging), and other configured apps. Follow that output where possible. Use terminal color indexes instead of fixed hex values for terminal UI; keep fixed colors only where the program cannot follow the palette at runtime.

`modules/home/base/gtk.nix` leaves GTK4's explicit theme unset so libadwaita can use Noctalia's CSS, and selects the GTK3 theme expected by the generated GTK3 CSS. The cursor and icon themes are configured there as well. Check the current template output before adding another theme manager.

System fonts are in `modules/system/user/fonts.nix`; this host uses Noto CJK SC for sans/serif and JetBrainsMono Nerd Font for monospace. `nerd-fonts.symbols-only` provides a separately named Symbols Nerd Font Mono family used by icon fonts; do not assume the patched mono family satisfies that lookup.

`modules/home/base/qt.nix` seeds qt6ct and qt5ct config files pointing to the Noctalia palette; `modules/home/wm/mango/config.nix` sets the Qt platform theme. Qt apps that rewrite settings need mutable files rather than `home.file` symlinks.

Several apps require seed files for generated theme output. Seed only missing files and check each target separately. Similar create-if-absent patterns appear in kitty, Qt, and zathura; preserve user edits and verify the generated paths.
