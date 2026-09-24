---
name: dev-toolchain
description: 修改共享 LSP、formatter、linter、编译器、解释器、DAP 或 Emacs 配置；排查工具 PATH、Python 导入与编辑器闭包。
---

# Development toolchain

`modules/home/programs/dev/toolchain.nix` is the shared profile source for
language servers, formatters, and linters used by Neovim and Emacs. Keep both
editors on the same executable versions.

## Placement and runtime paths

- Tools that an editor executes belong in `toolchain.nix`. Neovim LSP
  definitions in `nixvim/plugins/lsp/servers.nix` name bare commands; do not
  interpolate Nix store paths there, which would pull server closures into the
  editor package.
- Compilers and interpreters belong in their language modules (`llvm.nix`,
  `python.nix`, `java.nix`, `lua.nix`, `latex.nix`, `octave.nix`,
  `embedded.nix`), not the editor toolchain. Project-pinned dependencies go in
  the project's direnv/flake environment.
- A server declared for an editor must also exist on that editor's effective
  PATH. Desktop applications inherit the user systemd environment, so a tool
  working in an interactive shell does not prove it is available to an editor.
- `nixvim/packages.nix` intentionally does not make the editor self-contained
  with language servers, formatters, or linters. Plugin module dependencies
  can still add packages implicitly; see
  [closure and PATH notes](references/closure-and-path.md).

## Interpreter and editor-specific rules

- Tools invoked as commands can be in the profile. Tools imported by the
  debuggee interpreter cannot: `debugpy` belongs in `python.nix`'s
  `python3.withPackages`, so `python -m debugpy` uses an interpreter that can
  import it.
- Emacs uses built-in Eglot plus packages from
  `modules/home/programs/dev/emacs/default.nix`; language servers and
  formatters still come from `toolchain.nix`.
- A command bound in Emacs `keymaps.el` must be autoloaded even when its
  package is deferred. `:after` delays the whole use-package form, including
  its `:commands`; use a bare autoload or an available autoload cookie.
- Emacs config is a loader plus modules under `emacs/lisp/`. Adding a module
  requires listing it in `my/modules`; packages are declared in `default.nix`.
  There is no Emacs daemon service configured here.

For the measured Nixvim closure tradeoffs, PATH checks, and Emacs startup
invariants, read [closure and PATH notes](references/closure-and-path.md).

## Language runtimes

`embedded.nix` uses `gcc-arm-embedded`, including `arm-none-eabi-gdb`;
host GDB is not a substitute for Cortex-M debugging. Probe permissions belong
in `modules/system/hardware/debug-probes.nix`. Avoid duplicating LLVM module tools.

`octave.nix` provides Octave with matching toolboxes. MATLAB also has a separate
`matlab.nix` / `pkgs/matlab.nix` FHS wrapper around the user's installed tree;
it does not fetch the licensed application into a derivation. Read those files
before changing installation or theme behavior; the removed managed
`Documents/MATLAB/startup.m` theme setting was intentionally reverted.

## Verification boundaries

`nix eval` inspects evaluated values; it does not build packages or verify that
commands are on a launched editor's PATH. Build the relevant package or system
configuration for build validation, then verify the command from the same
environment the editor inherits. For Emacs key bindings, test that each bound
command is callable before its feature is otherwise loaded. Do not report
evaluation as build or runtime verification.
