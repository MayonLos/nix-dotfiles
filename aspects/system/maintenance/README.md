# System maintenance

Provides system-wide Nix settings, locale/time zone, sudo-rs policy, basic maintenance tools, and `nh` cleanup configuration. `host.flakePath` is an optional host binding input consumed by `nh`; the aspect does not discover a repository path.

Outputs include bounded journald storage, automatic Nix store optimization, configured substituters/keys and experimental features, locale definitions, password-authenticated wheel sudo-rs, maintenance utilities, and `nh` retention (`--keep 5 --keep-since 14d`). This feature does not remove logs or run cleanup itself.

`contract.nix`, `default.nix`, `nix.nix`, `locale.nix`, `tools.nix`, and `nh.nix` are owned private files. Removing the feature withdraws these system declarations after a system activation. Existing logs, generations, user files, and store contents remain until separate cleanup actions are explicitly run.
