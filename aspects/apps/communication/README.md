# Communication

Installs desktop communication clients: QQ, WeMeet, WeChat, Vesktop, and Thunderbird. The feature uses package availability and the selected session environment; it has no identity or appearance schema input.

It wraps QQ with PipeWire available for runtime loading and selects its Wayland or X11 backend from the active session. This does not enable QQ screen sharing in Mango: the locked QQ picker is X11-only and Mango's rootless Xwayland has no target window. The optional Xorg session still requires a real call and capture acceptance test. Vesktop enables the system Vencord integration; Thunderbird accounts and credentials remain interactive.

Owned files are `default.nix`, `im.nix`, and `thunderbird.nix`; the feature owns the corresponding Home Manager package and Thunderbird declarations. These Nix files are private. Removing the feature removes package and application declarations on the next generation; it retains Thunderbird profiles, account credentials, chat histories, and application data.
