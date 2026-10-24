# Project workbench

This aspect adds one launcher for each project explicitly supplied through the
user option `workspaceProjects`. It does not discover directories, inspect
project files, install project dependencies, or start commands from project
history.

```sh
workspace-project list
workspace-project <project-id> [terminal|editor|files|workspace] [-- ARG ...]
```

The default view is an interactive Kitty shell in the configured directory.
`editor` starts the existing `workspace-editor` wrapper in Kitty, while `files`
opens the directory through the existing `workspace-files` wrapper. Editor and
file-manager arguments after `--` remain separate argv values. The terminal
view does not accept extra command arguments.

Project IDs are lowercase ASCII words with hyphens. Each project supplies an
absolute `directory` and a plain-text `label`. The launcher checks that the
directory already exists before starting anything; it never creates a missing
directory or falls back to another working directory. When a project contains
`.envrc`, editor and file-manager launches require the installed `direnv` and
use `direnv exec`; an untrusted file is rejected by direnv and is never
automatically approved. Interactive terminals rely on the existing shell
direnv hook.

The aspect requires Kitty. The editor and file-manager views require the
existing `workspace-editor` and `workspace-files` commands, provided by
`defaultTools` when those roles are configured. It does not select a new editor
or install an additional GUI file manager. Every project receives separate
Editor and Files actions inside its existing desktop entry; the default
desktop action remains the terminal view.

Projects may opt into `workspace = true`. This adds the `workspace` CLI view
and a Workspace desktop action. The aspect writes a public tmuxp JSON config
for one session named `workspace-<project-id>`, with one window containing an
editor pane and two ordinary interactive shells. It runs no build, test, or log
commands. Kitty starts `tmuxp load -y`; tmuxp creates a missing session or
attaches to the configured session when it already exists. Repeated loads keep
the declared window and panes without duplicating them. The launcher never
kills or replaces a session. `tmux` and `tmuxp` are installed when at least one
project opts in. The workspace view rejects extra command arguments.

When `.envrc` exists, workspace launch also uses `direnv exec`; an untrusted
file is rejected without automatic approval. The generated tmuxp config only
contains the configured project directory and fixed layout; it does not read
project files or write into the project.

`checks.nix` contains tests using temporary project directories and spy
executables. Its tmuxp integration test starts a real server on a private
temporary socket, uses an isolated home and XDG directories, and launches an
editor spy. It does not start Kitty, open a real project, or read user project
data; the running system configuration is not applied.

Inputs are the typed `user.workspaceProjects` schema from `contract.nix`; each
project supplies a path and label, with an optional fixed workspace layout.
`default.nix` and `runner.py` own the generated launcher and desktop entries,
while `tests.py` and `checks.nix` implement verification. `contract.nix` is the
public schema and `checks.nix` is a public test hook using `{ pkgs, lib,
system, nixos, home, appearance }` as needed. Other Nix files are private.

Removing this feature withdraws its launcher, desktop entries, and optional
tmuxp configuration when activated. It never deletes project directories,
project files, `.envrc` files, or existing tmux sessions.
