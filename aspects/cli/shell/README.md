# Command-line shell

Provides the Zsh command-line environment and related tools. Inputs are `user.appearance` for theme data, `user.secretExports` for runtime secret export names, and the host's SOPS paths; it also includes the shared `workspace-task` command.

Outputs include Zsh, Starship, zoxide, Atuin, fzf/fzf-tab, Git/delta/lazygit, direnv, tmux, yazi, Nix index, and system information tools, together with shell aliases, completion, key bindings, and CLI theme files. Secrets are read from their runtime files and exported by the shell; secret values are not embedded in generated configuration. The host provider installs its shell support once per host.

`default.nix`, `contract.nix`, `checks.nix`, and the directly imported shell modules are owned by this feature. `checks.nix` is a public test hook with signature `{ pkgs, lib, system, nixos, home, appearance }` (arguments are used as needed); other Nix files are private. `contract.nix` defines the `secretExports` and `flakePath` entity inputs used here.

Removing the feature removes its shell selection, generated shell files, tools, and runtime exports on activation. It preserves shell history, Git repositories, credentials, Atuin history, project files, and user-owned configuration/data unless separately edited by the user.

r43 uses a single-line Starship prompt: directory, neutral Git metadata and a
blue `❯`. The right prompt shows duration only from three seconds; Zsh hides it
when input needs the space. SSH shows `@hostname`, actual UID 0 shows the root
username, and a failed command adds `✘` plus its status. Language and Nix-shell
versions are omitted. A cached sudo credential does not add a root marker.

fzf and fzf-tab share a borderless reverse list, top search, neutral selected
text and a blue pointer. File (`Ctrl+t`) and directory (`Alt+c`) previews start
hidden; `Ctrl+/` toggles them. `Ctrl+r` remains Atuin. tmux-fzf also starts with
its preview hidden and uses the same toggle. No shell or Atuin history is
migrated or cleared.

tmux keeps `Ctrl+a`, vi copy mode, tmuxp layouts, resurrect and continuum.
The top status line contains session and window text; the active window has a
blue underline. `PREFIX`, `COPY` and `ZOOM` appear only while active, without
filled badges. It has no permanent clock or path. `allow-passthrough on` retains
Neovim OSC 11 background sync/restore; the status background inherits the
terminal default. The locked tmux drops background-color passthrough while a pane/client
redraw is pending. `tmux-package.nix` / `tmux-passthrough.patch` keeps these
OSC 11/111 background-color sequences, while preserving `on` visibility checks and suspended
client rejection. The native PTY check covers OSC 11 in the same write as an
alternate-screen redraw and suppression from a background window.
Underline-style support is declared for `xterm-kitty` and
`tmux-256color`. The existing tmux-fzf CopyQ suppression remains: clipboard
daemons belong to the Xorg session. Smart-splits still routes `Ctrl+h/j/k/l`
and `Alt+h/j/k/l` between Neovim and tmux navigation/resize.

Yazi uses list + preview (`0:5:4`) with the parent path in its breadcrumb;
there is no full-border plugin. Below 100 terminal columns the preview folds
automatically; `!` toggles it at either width. A manual choice lasts through
reflow until the width crosses that threshold. The local
`resources/yazi-responsive.lua` hooks the locked Yazi `Tab.layout` before its
native split/reflow, retaining navigation, selections, Git, previewers and
trash. The pinned Glow plugin has a local adapter for Yazi 26's singular
`Command:arg` / `ya.preview_widget` APIs, uses the pane width and the shared
Glow style, and disables paging in a preview. DuckDB receives its required
setup call before CSV/TSV/JSON/Parquet previews. Its pure transition check and real Yazi startup run in the runtime check.

LazyGit's local `lazygit-package.nix` / `lazygit-title-focus.patch` separates
gocui's existing title and frame colors: the active title (including search)
is blue while every frame edge stays low contrast. Unfocused titles and their
selected tab labels use the normal foreground, without borrowing focus blue. Command-log and footer
chrome are hidden; native keyboard help is still available with `?`. Delta
uses the terminal background for unchanged/add/delete lines, keeping stronger
color only for word changes. Bat defaults to plain output; use `bat --style=full`
or `delta --line-numbers --side-by-side` for detailed review.

Fastfetch has no logo and reports title, System, Kernel, Terminal and Memory
with gray labels and bright values. Its ten-cell label column accommodates
Terminal. btop starts with CPU aggregate, memory and processes, without disk,
GPU, battery, frequency, power or temperature readouts. `3` toggles the native
network panel, `p` cycles presets, and the local `v` key toggles individual
CPU threads. `btop-package.nix` / `btop-compact.patch` adds `show_cpu_cores`
(upstream default true; this feature selects false) and keeps the aggregate
graph, total and load average when rows are hidden. All local patches fail on
changed source anchors, so package upgrades require review. Themes, histories,
repositories, credentials and persisted sessions are preserved on removal;
these generated configurations retain their existing Home Manager writer.

`herdr` is selected independently by engineering-workbench. tmux continues to own
the existing general terminal sessions, shortcuts and tmuxp layouts; herdr adds
agent/project workspaces in a separate window. See [herdr](../herdr/README.md)
for its single configuration writer, desktop entry and Mango shortcut.
