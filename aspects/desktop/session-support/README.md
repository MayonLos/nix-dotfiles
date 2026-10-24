# Graphical session support

Provides shared support consumed by graphical sessions: input method, GTK/Qt, fonts, portal/audio/polkit host support, environment, Xresources, and session target wiring. Inputs are host/user appearance palettes, host facts where hardware/display details apply, and the selected session's target names.

The public module option is `nixDotfiles.graphicalSessionTargets`; session features contribute their targets and shared modules use that list to attach session-scoped services. This aspect also selects the shared `workspace-task` utility and grants the input group to users who select graphical support. It does not select or start a compositor.

`default.nix`, `session-targets.nix`, `input-method.nix`, `gtk.nix`, `qt.nix`, `xresources.nix`, `environment.nix`, `tools.nix`, and `host/` implement the feature. Rime-specific source and packaging live under `rime/`; `rime-checks.nix` and the nested `rime/README.md` document that implementation. No files here are public Nix imports other than the registered feature entry and the declared module option.

Removing shared support removes its settings, host services, and group contribution after activation. It preserves input-method dictionaries/history and user GTK/Qt application data. Session-owned targets disappear with their consuming session features.

`checks.nix` is the public test hook for the Rime runtime check, taking the standard check arguments as needed. Private class and resource modules are not public imports.
