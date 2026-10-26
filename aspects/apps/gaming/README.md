# Gaming

Configures gaming tools for a selected user and routes shared NixOS support through `gaming-host`. The host side owns Steam, Gamescope and GameMode integration; the user side configures MangoHud and Prism Launcher. The user's GameMode group membership is part of this feature.

Outputs include Steam and host gaming support, MangoHud metrics, and Prism Launcher with the selected Java toolchains, FFmpeg, MangoHud, Gamescope, and GameMode support. When the user has an appearance palette, it also installs `~/.local/share/PrismLauncher/themes/OneDark/theme.json` and `themeStyle.qss` from the public `desktop/session-support.qt-style.nix` factory. Prism's `ApplicationTheme` remains owned by the launcher; select `One Dark` once in Prism's Settings → Appearance → Theme. GPU-specific GameMode device settings come from host facts in the hardware feature.

Owned files are `default.nix`, `host/`, `mangohud.nix`, `prismlauncher.nix`, and the explicit test hook `checks.nix`; implementation Nix files are private. Removing the feature withdraws package, service, group declarations, and both managed theme files when activated. It preserves Steam libraries, game saves, Prism instances, downloaded mods, launcher accounts, and Prism's selected theme setting.
