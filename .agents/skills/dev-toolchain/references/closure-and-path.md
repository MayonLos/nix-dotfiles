# Closure, PATH, and Emacs startup checks

Read this when changing Nixvim plugin dependencies, moving a tool between the
profile and an editor package, debugging desktop-only command lookup, or
changing Emacs autoload/module wiring.

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

Neovim DAP and Emacs dape invoke the adapter through Python. A separately
installed `python3Packages.debugpy` is not necessarily importable by the Python
used to run the debuggee. Keep it in `python3.withPackages` in
`modules/home/programs/dev/python.nix` and check the actual interpreter path.

## Emacs autoload and modules

`modules/home/programs/dev/emacs/init.el` loads modules named in `my/modules`;
the `lisp/` directory being linked does not load every file. Check a new module
is named there and that its package is listed in `default.nix`.

Commands bound in `keymaps.el` must resolve before another action loads their
package. `use-package :after` defers the whole declaration; its `:commands`
does not install autoloads until the form runs. Use a bare `(autoload 'cmd
"feature" nil t)` when needed. Keep `package-enable-at-startup` enabled because
`package-activate-all` loads package autoload files.

For a command sweep, build Emacs and check every command bound in `keymaps.el`
before any other action loads its package. This previously used procedure runs
the config in a temporary init directory and reports module failures or void
commands; it does not assume an Emacs daemon:

```sh
em=$(nix build --no-link --print-out-paths \
      .#nixosConfigurations.nixos-btw.config.home-manager.users.mayon.programs.emacs.finalPackage)
t=$(mktemp -d); src=modules/home/programs/dev/emacs
sed "s|@treesitGrammars@||" "$src/early-init.el" > "$t/early-init.el"
cp "$src/init.el" "$t/"; cp -r "$src/lisp" "$t/"
grep -oE "#'[a-zA-Z0-9/_-]+" "$t/lisp/keymaps.el" | sed "s/#'//" | sort -u > "$t/cmds"
"$em/bin/emacs" --batch --init-directory="$t" -l "$t/early-init.el" \
  --eval '(package-activate-all)' -l "$t/init.el" \
  --eval '(progn (dolist (f my/module-errors) (princ (format "MODULE-FAIL %S\n" f)))
                 (with-temp-buffer (insert-file-contents (expand-file-name "cmds" user-emacs-directory))
                   (dolist (c (split-string (buffer-string) "\n" t))
                     (unless (fboundp (intern c)) (princ (format "VOID %s\n" c))))))'
```

No `services.emacs` daemon unit exists in this repository.
