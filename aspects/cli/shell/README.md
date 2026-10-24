# Command-line shell

Provides the Zsh command-line environment and related tools. Inputs are `user.appearance` for theme data, `user.secretExports` for runtime secret export names, and the host's SOPS paths; it also includes the shared `workspace-task` command.

Outputs include Zsh, Starship, zoxide, Atuin, fzf/fzf-tab, Git/delta/lazygit, direnv, tmux, yazi, Nix index, and system information tools, together with shell aliases, completion, key bindings, and CLI theme files. Secrets are read from their runtime files and exported by the shell; secret values are not embedded in generated configuration. The host provider installs its shell support once per host.

`default.nix`, `contract.nix`, `checks.nix`, and the directly imported shell modules are owned by this feature. `checks.nix` is a public test hook with signature `{ pkgs, lib, system, nixos, home, appearance }` (arguments are used as needed); other Nix files are private. `contract.nix` defines the `secretExports` and `flakePath` entity inputs used here.

Removing the feature removes its shell selection, generated shell files, tools, and runtime exports on activation. It preserves shell history, Git repositories, credentials, Atuin history, project files, and user-owned configuration/data unless separately edited by the user.
