# Mango session

Provides the Mango Wayland desktop and its Noctalia shell integration. Inputs are `user.appearance`, host display facts, selected `noctaliaIntegrations`, and the public `nixDotfiles.graphicalSessionTargets` option from session support.

Outputs include Mango/Noctalia configuration, clipboard bridges, screenshot and OCR tools, per-session environment, and host-side Mango/portal modules routed through `interactive-session-host`. The `noctaliaIntegrations` quirk is declared here and validated by `contract.nix` before it is consumed to render selected application integrations. The feature owns its session target and Noctalia service lifecycle; it does not select the login greeter.

Noctalia settings are rendered by `noctalia.nix`; its package is built from the locked `pkgs.local.noctalia` derivation with `noctalia/astra-selection.patch`, which adapts launcher, Home shortcut, and focused workspace colors to the shared palette. The feature also supplies the pinned Neovim terminal desktop entry and `notify-send` (`libnotify`) for notification review. The managed Noctalia user service sets `LC_TIME=zh_CN.UTF-8` for Chinese date labels.

`default.nix` and `contract.nix` are public. `mango.nix`, `noctalia.nix`, `noctalia/`, `clipboard.nix`, `screenshot.nix`, `tesseract-ocr.nix`, and `host/` are private implementation. `checks.nix` is a public test hook with signature `{ pkgs, lib, system, nixos, home, appearance }` (as needed). Other Nix files are private.

Removing the feature withdraws Mango and Noctalia configuration, session services, and screenshot/clipboard declarations when a new generation is activated. It leaves user documents, Noctalia history/settings outside declared paths, saved sessions, and other application state untouched; it does not stop or switch the running session by itself.

HM owns `Pictures/Wallpapers/managed` as a store link. The `wallpaperLocalDirectory` activation only creates a missing `Pictures/Wallpapers/local/`, preserves existing directories and directory symlinks, and refuses other existing objects without replacement. Noctalia scans the parent recursively, following directory symlinks with canonical-path deduplication. User local images remain outside Git/store and survive feature removal. Native automation also chooses a random image at shell startup; the declared default and greeter use Quiet Bay, while the lockscreen follows the current desktop wallpaper.
