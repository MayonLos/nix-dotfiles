# Project workbench

This aspect adds one launcher for each project explicitly supplied through the
user option `workspaceProjects`. It does not discover directories, inspect
project files, install project dependencies, or start commands from project
history.

```sh
workspace-project list
workspace-project <project-id> [terminal|editor|files] [-- ARG ...]
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
or install an additional GUI file manager. Desktop entries open the terminal
view for their project.

`checks.nix` contains isolated tests using temporary project directories and
spy executables. It does not start Kitty, open a real project, or read user
project data.
