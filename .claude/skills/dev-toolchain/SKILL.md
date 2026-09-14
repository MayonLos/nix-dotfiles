---
name: dev-toolchain
description: Where language servers, formatters, linters, compilers and debug adapters are declared on this host, and the closure-size and sys.path rules that govern them. Use when adding or upgrading an LSP server, formatter or linter for nvim or Emacs, when a server starts in one editor but not the other, when a server is not found at runtime, when editing modules/home/programs/dev/toolchain.nix or nixvim/plugins/lsp/servers.nix, when nvim's closure or rebuild time blows up, when adding a language's compiler or interpreter, or when a DAP adapter (debugpy in particular) fails to start.
---

# Toolchain: servers, formatters, linters

## One source: toolchain.nix

`modules/home/programs/dev/toolchain.nix` is **the single place** every
language server, formatter and linter is declared. nvim and Emacs both consume
it, which is what stops the two editors from drifting onto different versions
of the same server.

- Adding a server for nvim? Add it to `toolchain.nix`, not to `nixvim/`.
- `nixvim/packages.nix` declares **no servers, formatters or linters** — only
  `dependencies.fd.enable` explicitly (fzf-lua shells out to `fd`). `fd` is
  also in the user profile as of 2026-09-14; the previous claim that it was
  absent was stale. Plugin modules enable other dependencies implicitly, as
  detailed below. `nix run` on the nixvim package alone
  therefore gets you an editor with zero language servers. That is intentional,
  not a bug to fix. It also sets `withRuby = false` / `withPython3 = false`;
  this config has no remote plugins and the ruby host alone was 98 MB.
- `modules/home/programs/dev/emacs/default.nix` declares none either — the
  servers eglot starts and the formatters apheleia shells out to all come from
  `toolchain.nix`.

**Compilers and interpreters do not belong here.** They stay in their
per-language modules — `llvm.nix`, `python.nix`, `java.nix`, `lua.nix`,
`latex.nix`. The line is: `toolchain.nix` is about *editing* code, the
per-language modules are about *running* it.

## Never pin a server binary into an editor's runtime closure

Every `cmd` in `nixvim/plugins/lsp/servers.nix` names its binary as a bare
string (`"lua-language-server"`), never `"${pkgs.lua-language-server}/bin/..."`.

Interpolating the store path puts the server in nvim's **runtime closure**.
jdt-language-server alone dragged in a full openjdk. Unpinning all nine servers
took that closure from **8.9 GiB to 824 MB**. The servers are on `PATH` via
`toolchain.nix` anyway.

If a server is not found at runtime, the fix is to add it to `toolchain.nix` —
never to interpolate a store path back into `servers.nix`.

## Plugin runtime dependencies can be enabled implicitly

Source audit on 2026-09-14, at the locked nixvim revision
`68c2edd2787f055d9c306bcfe726f3b8f11b9441` (local source NAR hash checked
against `flake.lock`):

- `plugins/by-name/gitsigns/default.nix:13` declares `dependencies = [ "git" ];`.
- `plugins/by-name/todo-comments/default.nix:23` declares
  `dependencies = [ "ripgrep" ];`.
- `plugins/by-name/fzf-lua/default.nix:35` declares `dependencies = [ "fzf" ];`.

These are paths in the nixvim input, not this repository. Its
`lib/plugins/mk-neovim-plugin.nix` calls `enableDependencies` when the plugin
is enabled. `lib/plugins/utils.nix:132` implements that with `lib.mkDefault
true`; `modules/dependencies.nix` collects enabled packages into
`extraPackages`, and `modules/top-level/output.nix:334` prefixes the wrapper's
PATH with them. Omitting a dependency from `nixvim/packages.nix` therefore
does **not** disable it. An explicit `dependencies.<name>.enable = false`
overrides these defaults without `mkForce`.

Clipboard takes a separate route: nixvim's `modules/clipboard.nix:55` adds
enabled provider packages to `extraPackages`. It does not interpolate their
binary paths into Lua. Neovim 0.12.4's
`runtime/autoload/provider/clipboard.vim` checks `executable('wl-copy')` and
`executable('wl-paste')` and calls those bare commands through PATH. Disabling
an ordinary `dependencies` entry does not remove this provider package.

The reported editor closure at this audit was 783 MB. No removal or saving
was verified: the sandbox denied Nix daemon socket access for the editor
build, system evaluation and `nix fmt`. Keep each dependency until a separate
built variant demonstrates a reduction in the **total editor closure**;
individual package closure sizes overlap and cannot be added. Verify profile
PATH tools with actual fzf-lua file/live-grep pickers and gitsigns in a fresh
terminal editor, and verify clipboard copy/paste before changing its provider.

## debugpy is deliberately not in toolchain.nix

debugpy must be importable *by the interpreter that runs the debuggee*, so it
rides along with `python.nix`'s `python3.withPackages`. A loose
`python3Packages.debugpy` in the user profile is not on that python's
`sys.path`, and the DAP adapter then fails to start silently — no error, the
session just never attaches.

Any other tool that has to be *imported* rather than *executed* follows the
same rule: it belongs in the interpreter's `withPackages`, not the profile.

## Neovim

`EDITOR` is nvim. The config is nixvim modules at `nixvim/` in the repo root,
bridged by `modules/home/programs/dev/nvim.nix`.

**Everything about the editor itself — adding a plugin, lazy-loading, keymaps —
is the `nvim-config` skill.** What belongs here is only the boundary above: the
tools nvim *starts* live in `toolchain.nix`, and `servers.nix` names them as bare
binaries.

## Emacs

`modules/home/programs/dev/emacs/` — `emacs30-pgtk` (Wayland-native; the plain
`emacs` attribute is still the X11 build), configured through `programs.emacs`.
`init.el` and `early-init.el` are store symlinks. There is **no** `services.emacs`
daemon unit in this repo; if you want one, add it — do not assume it exists.

- **Packages can only be added in `default.nix`.** There is no writable
  `package-user-dir`, so `M-x package-install` cannot work.
- `package-enable-at-startup` must stay **on** — `package-activate-all` is the
  only thing that loads each package's `-autoloads.el` out of
  `share/emacs/site-lisp/elpa/`. Turn it off and the packages land on the
  load-path with every autoloaded command still void (`void-function
  doom-modeline-mode`). `early-init.el` is authoritative here; the comment in
  `default.nix` claiming early-init sets it to nil is stale.
- Tree-sitter grammars are a curated subset; `with-all-grammars` is 279 MiB.
  The chosen path is substituted into `early-init.el`.
- Scratch config that should not require a rebuild goes in
  `~/.config/emacs/personal.el`, loaded last.
- gptel reads `/run/secrets/deepseek-api-key` through a lambda, not an env var
  — the daemon never sourced the zsh profile. See the `sops-secrets` skill.

## Per-project environments

direnv + nix-direnv (`modules/home/programs/dev/direnv.nix`). Drop a `.envrc`
containing `use flake` in a project directory. Do not add project-specific
toolchains to `toolchain.nix`.
