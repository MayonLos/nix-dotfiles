# Themes and config ownership

Noctalia renders the live palette for GTK, Qt, Kitty, zathura, and other configured apps. Follow that output where possible. Use terminal color indexes instead of fixed hex values for terminal UI; keep fixed colors only where the program cannot follow the palette at runtime.

Firefox's browser chrome follows the Noctalia palette through a local user template that updates only the managed block in the mutable profile `chrome/userChrome.css`. Firefox reads that stylesheet at startup, so palette changes require restarting Firefox; the Home Manager activation seed supplies a usable static fallback before Noctalia's first render.

The wrapped Firefox package pins the currently used Dark Reader XPI and locks the browser to its built-in dark theme. This keeps a theme restored by Firefox Sync from replacing the Noctalia browser-chrome colors. The four legacy synchronized theme add-ons are blocked by enterprise policy because locking the active-theme preference alone did not deactivate Frostlit in the existing profile. Account, bookmarks and session data are preserved. Activation reuses cached palette values only, ensuring stale rendered CSS cannot replace the current Nix-managed layout.

`modules/home/base/gtk.nix` leaves GTK4's explicit theme unset so libadwaita can use Noctalia's CSS, and selects the GTK3 theme expected by the generated GTK3 CSS. The cursor and icon themes are configured there as well. Check the current template output before adding another theme manager.

System fonts are in `modules/system/user/fonts.nix`; this host uses Noto CJK SC for sans/serif and JetBrainsMono Nerd Font for monospace. `nerd-fonts.symbols-only` provides a separately named Symbols Nerd Font Mono family used by icon fonts; do not assume the patched mono family satisfies that lookup.

`modules/home/base/qt.nix` seeds qt6ct and qt5ct config files pointing to the Noctalia palette; `modules/home/wm/mango/config.nix` sets the Qt platform theme. Qt apps that rewrite settings need mutable files rather than `home.file` symlinks.

Several apps require seed files for generated theme output. Seed only missing files and check each target separately. Similar create-if-absent patterns appear in kitty, Qt, and zathura; preserve user edits and verify the generated paths.
