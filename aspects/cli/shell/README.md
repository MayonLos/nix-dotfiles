# Command-line shell

Provides the Zsh command-line environment and related tools. Inputs are `user.appearance` for theme data, `user.secretExports` for runtime secret export names, and the host's SOPS paths; it also includes the shared `workspace-task` command.

Outputs include Zsh, Starship, zoxide, Atuin, fzf/fzf-tab, Git/delta/lazygit, direnv, tmux, yazi, Nix index, and system information tools, together with shell aliases, completion, key bindings, and CLI theme files. Secrets are read from their runtime files and exported by the shell; secret values are not embedded in generated configuration. The host provider installs its shell support once per host.

`default.nix`, `contract.nix`, `checks.nix`, and the directly imported shell modules are owned by this feature. `checks.nix` is a public test hook with signature `{ pkgs, lib, system, nixos, home, appearance }` (arguments are used as needed); other Nix files are private. `contract.nix` defines the `secretExports` and `flakePath` entity inputs used here.

Removing the feature removes its shell selection, generated shell files, tools, and runtime exports on activation. It preserves shell history, Git repositories, credentials, Atuin history, project files, and user-owned configuration/data unless separately edited by the user.

Astra §8 supplies the two-line Starship prompt and tmux rounded-character capsules.
The prompt shows short Git counts and numeric failures; identity appears for SSH
or root sessions. tmux preserves `Ctrl+a` window/session operations and tmuxp
layouts while adding smart-splits integration: pane-local `@pane-is-vim` routes
`Ctrl+h/j/k/l` to Neovim or pane navigation and `Alt+h/j/k/l` to Neovim or resize.
Copy mode retains its native vi cursor/selection keys. `@rounded-caps off` selects a bracket fallback
for terminals whose font cannot render Powerline round ends. Existing sessions
and user histories are preserved; runtime joint navigation still needs acceptance.
