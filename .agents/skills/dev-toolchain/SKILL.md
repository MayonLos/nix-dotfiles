---
name: dev-toolchain
description: 修改共享 LSP、formatter、linter、编译器、解释器或 DAP 配置；排查工具 PATH、Python 导入与编辑器闭包。
---

# Development toolchain

`modules/home/programs/dev/toolchain.nix` is the shared profile source for
language servers, formatters, and linters used by Neovim. One set of
executable versions keeps the profile and the editor from drifting.

## Placement and runtime paths

- Tools that an editor executes belong in `toolchain.nix`. Neovim LSP
  definitions in `nixvim/plugins/lsp/servers.nix` name bare commands; do not
  interpolate Nix store paths there, which would pull server closures into the
  editor package.
- Compilers and interpreters belong in their language modules (`llvm.nix`,
  `python.nix`, `java.nix`, `lua.nix`, `latex.nix`, `octave.nix`,
  `embedded.nix`), not the editor toolchain. The version each module installs
  and the editor tools built against it are single-sourced in
  `lib/toolchains.nix` (`llvm`, `python`, `lua`; Java's multi-version Temurin
  set is `lib/java.nix`). Project-pinned dependencies go in the project's
  direnv/flake environment.
- Activation/build-time scripts may use `pkgs.python3` directly (for example,
  `screenshot.nix`, `firefox.nix`, `wm/mango/noctalia.nix`, and
  `pkgs/matlab.nix`); they need not track `lib/toolchains.nix`. That shared
  Python source covers the development interpreter, its packages, and
  nvim-dap's bare `python3` command only.
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
- Emacs was removed and is not installed. Do not add it back unless the user
  asks; the editor tools come from `toolchain.nix` and are started by nvim.

For the measured Nixvim closure tradeoffs and PATH checks, read
[closure and PATH notes](references/closure-and-path.md).

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
environment the editor inherits. Do not report
evaluation as build or runtime verification.
