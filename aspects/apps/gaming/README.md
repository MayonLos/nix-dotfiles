# Gaming

Configures gaming tools for a selected user and routes shared NixOS support through `gaming-host`. The host side owns Steam, Gamescope and GameMode integration; the user side configures MangoHud and Prism Launcher. The user's GameMode group membership is part of this feature.

Outputs include Steam and host gaming support, MangoHud metrics, and Prism Launcher with the selected Java toolchains, FFmpeg, MangoHud, Gamescope, and GameMode support. The feature has no appearance contract. GPU-specific GameMode device settings come from host facts in the hardware feature.

Owned files are `default.nix`, `host/`, `mangohud.nix`, and `prismlauncher.nix`; all Nix files are private. Removing the feature withdraws package, service, and group declarations when activated. It preserves Steam libraries, game saves, Prism instances, downloaded mods, and launcher accounts.
