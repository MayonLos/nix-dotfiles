# Closure and PATH checks

Read this when changing Nixvim plugin dependencies, moving a tool between the
profile and an editor package, or debugging desktop-only command lookup.

## Nixvim package dependencies

Some Nixvim plugin modules enable dependencies with `lib.mkDefault true`.
Removing a package from `nixvim/packages.nix` does not necessarily remove it
from the wrapped editor. Clipboard provider packages are collected separately.
Inspect the current pinned Nixvim source before changing dependency behavior.

Historical total-closure measurements from 2026-09-14 (at an earlier pin):

| variant | editor closure |
|---|---:|
| baseline | 783 MB |
| git dependency disabled | 553 MB |
| ripgrep disabled | 776 MB |
| fzf disabled | 783 MB |
| git and ripgrep disabled | 547 MB |
| also disable fd | 541 MB |

These totals overlap internally and must not be summed package by package.
They are evidence for the tradeoff, not guaranteed sizes for the current pin.
The present profile supplies `git`, `rg`, `fzf`, `fd`, and `wl-copy` to desktop
applications. Recheck with the environment from
`systemctl --user show-environment` if changing what the editor leaves out.
Useful behavior checks after changing those dependencies: gitsigns marks,
fzf-lua file search, fzf-lua grep, and `:TodoQuickFix`.

Historically, replacing store-pinned server commands with bare PATH commands
reduced the Nixvim runtime closure from 8.9 GiB to 824 MB when there were nine
servers. Treat the sizes as historical measurements; the rule remains to keep
servers in the shared profile and out of the editor closure.

## debugpy

Neovim DAP invokes the adapter through Python. A separately
installed `python3Packages.debugpy` is not necessarily importable by the Python
used to run the debuggee. Keep it in `python3.withPackages` in
`modules/home/programs/dev/python.nix` and check the actual interpreter path.
