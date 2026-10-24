# Command-line shell

Provides the Zsh command-line environment and related tools. Inputs are `user.appearance` for theme data, `user.secretExports` for runtime secret export names, and the host's SOPS paths; it also includes the shared `workspace-task` command.

Outputs include Zsh, Starship, zoxide, Atuin, fzf/fzf-tab, Git/delta/lazygit, direnv, tmux, yazi, Nix index, and system information tools, together with shell aliases, completion, key bindings, and CLI theme files. Secrets are read from their runtime files and exported by the shell; secret values are not embedded in generated configuration. The host provider installs its shell support once per host.

`default.nix`, `contract.nix`, `checks.nix`, and the directly imported shell modules are owned by this feature. `checks.nix` is a public test hook with signature `{ pkgs, lib, system, nixos, home, appearance }` (arguments are used as needed); other Nix files are private. `contract.nix` defines the `secretExports` and `flakePath` entity inputs used here.

Removing the feature removes its shell selection, generated shell files, tools, and runtime exports on activation. It preserves shell history, Git repositories, credentials, Atuin history, project files, and user-owned configuration/data unless separately edited by the user.

Astra §8 supplies the two-line Starship prompt. It shows the directory in blue,
the Git branch in purple, compact change counts, failures, and muted command
duration; identity appears for SSH or root sessions. tmux preserves `Ctrl+a`
window/session operations and tmuxp layouts while adding a flat status line,
blue underlined active window, conditional blue/yellow/purple `PREFIX`, `COPY`,
and `ZOOM` badges, and a blue active-pane edge with subdued inactive dividers.
tmux declares underline-style support for `xterm-kitty` and `tmux-256color`, so
the blue underline color works for Kitty clients and inside tmux. Zoomed windows
show a yellow `Z` marker.
Its smart-splits integration routes `Ctrl+h/j/k/l` to Neovim or pane navigation
and `Alt+h/j/k/l` to Neovim or resize. Copy mode retains its native vi
cursor/selection keys.

Yazi uses its rounded full-border plugin and the native `indicator.current` /
`indicator.padding` theme fields for a blue hover mark and the shared selection
surface. `mgr.marker_symbol` is reserved for marked files and is not the hover
indicator. LazyGit uses rounded native panels, a thin blue active border, a
surface-colored inactive border, and the same selection fill; Delta supplies
the palette-based additions and deletions. Fastfetch places the small NixOS
logo beside a flat list of system and hardware values, with blue keys and a
bright foreground title. btop uses its native `rounded_corners` setting,
subtle palette-colored panel outlines, and blue-to-cyan CPU, memory, and I/O
gradients. Existing sessions and user histories are preserved; runtime
navigation and TUI appearance still need acceptance.

`herdr` is selected independently by engineering-workbench. tmux continues to own
the existing general terminal sessions, shortcuts and tmuxp layouts; herdr adds
agent/project workspaces in a separate window. See [herdr](../herdr/README.md)
for its single configuration writer, desktop entry and Mango shortcut.
