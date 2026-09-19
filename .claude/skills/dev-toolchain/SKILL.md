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
`latex.nix`, `octave.nix`. The line is: `toolchain.nix` is about *editing* code, the
per-language modules are about *running* it.

`embedded.nix` is the STM32/Cortex-M toolchain: `gcc-arm-embedded` (ARM's own
build, which substitutes from cache -- `pkgsCross.arm-embedded` would compile
the whole toolchain locally), `openocd` + `stlink` + `probe-rs-tools` for
flashing and on-chip debug, `dfu-util` + `stm32flash` for the bootloader routes
that need no probe, `stm32cubemx` for HAL generation, and `tio` for the serial
console. It deliberately does **not** repeat `cmake`, `ninja`, `pkg-config` or
`gdb` -- `llvm.nix` already has them. Note `arm-none-eabi-gdb` comes inside
`gcc-arm-embedded`; the host `gdb` cannot debug a Cortex-M. Probe access is a
system concern and lives in `modules/system/hardware/debug-probes.nix`.

A firmware repo that pins its own toolchain should do it with a `.envrc`
(`use flake`) rather than by growing `embedded.nix` -- that is what direnv is
here for.

`octave.nix` is the MATLAB replacement (MATLAB cannot be packaged — its
installer needs a MathWorks login). It builds `octaveFull.withPackages` with
seven toolbox equivalents; the toolboxes compile against that exact octave, so
the first rebuild after a bump is local, not substituted. `~/.octaverc` is left
unmanaged on purpose: `pkg load signal` is per-project taste.

## Never pin a server binary into an editor's runtime closure

Every `cmd` in `nixvim/plugins/lsp/servers.nix` names its binary as a bare
string (`"lua-language-server"`), never `"${pkgs.lua-language-server}/bin/..."`.

Interpolating the store path puts the server in nvim's **runtime closure**.
jdt-language-server alone dragged in a full openjdk. Unpinning the servers took
that closure from **8.9 GiB to 824 MB** (measured when there were nine; there
are fourteen now, and the rule holds for all of them). The servers are on `PATH` via
`toolchain.nix` anyway.

If a server is not found at runtime, the fix is to add it to `toolchain.nix` —
never to interpolate a store path back into `servers.nix`.

## Plugin runtime dependencies can be enabled implicitly

Source audit on 2026-09-14, at nixvim revision
`68c2edd2787f055d9c306bcfe726f3b8f11b9441` (local source NAR hash checked
against `flake.lock` at the time). `flake.lock` has since moved on; the
conclusions below were re-read against the current pin, but if a dependency
default surprises you, re-check the source rather than trusting this list:

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

Measured the same day by building one variant per change and comparing the
**total** editor closure — individual package closure sizes overlap heavily
and must never be summed:

| variant | total | delta |
|---|---:|---:|
| baseline | 783 MB | — |
| `git.enable = false` | 553 MB | -230 MB |
| `ripgrep.enable = false` | 776 MB | -7 MB |
| `fzf.enable = false` | 783 MB | 0 |
| git + ripgrep | 547 MB | -236 MB |
| ...and fd as well | 541 MB | -6 MB |

git alone was 29% of the editor. `nixvim/packages.nix` now disables git and
ripgrep and keeps fzf and fd: trading self-containment for zero or near-zero
bytes is a pure loss, and fd is what fzf-lua lists files with.

The failure mode to guard against is an editor launched somewhere with a
thinner PATH than an interactive shell. The one that matters here is
`systemctl --user show-environment`, which is what a desktop entry inherits:
it carries `/etc/profiles/per-user/mayon/bin`, and git, rg, fzf, fd and
wl-copy all resolve inside it. Verified under exactly that PATH, not the
caller's: gitsigns produced an identical mark count before and after,
`<leader>ff` listed files, `<leader>fg` returned a grep hit, and
`:TodoQuickFix` returned an entry. Re-run those four if this set changes
again, and never take `vim.fn.executable` in your own shell as the answer.

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
`early-init.el`, `init.el` and the whole `lisp/` directory are store symlinks.
There is **no** `services.emacs` daemon unit in this repo; if you want one, add
it — do not assume it exists.

### The tree mirrors nixvim

`init.el` is a **loader only**: it puts `lisp/` on the load-path, `require`s the
modules named in `my/modules`, and loads `custom.el` and `personal.el`. Every
setting lives in exactly one file under `lisp/`, named after the nixvim
directory it corresponds to:

| nixvim | emacs/lisp |
|---|---|
| `core/`, `options.nix`, `autocmds.nix` | `core-perf.el`, `core-defaults.el`, `core-autocmds.el` |
| `plugins/appearance/`, `theme.nix` | `ui-fonts.el`, `ui-theme.el`, `ui-icons.el`, `ui-modeline.el`, `ui-frame.el` |
| `plugins/editing/` | `edit-evil.el`, `edit-textobj.el`, `edit-multicursor.el`, `edit-treesit.el` |
| `plugins/completion/` | `cmp-corfu.el`, `cmp-snippets.el` |
| `plugins/navigation/` | `nav-minibuffer.el`, `nav-harpoon.el`, `nav-dired.el` |
| `plugins/lsp/` | `lsp-eglot.el`, `diag-trouble.el` |
| `plugins/formatting/` | `fmt-apheleia.el` |
| `plugins/git/` | `git-magit.el` |
| `plugins/debug/` | `dbg-dape.el` |
| `plugins/ai/` | `ai-gptel.el` |
| `plugins/terminal/`, `plugins/utility/` | `tool-terminal.el`, `tool-session.el`, `tool-utility.el` |
| `plugins/lang/`, `plugins/utility/render-markdown.nix`, snacks' math | `lang-org.el`, `lang-markdown.el`, `lang-tex.el`, `lang-math.el` |
| `keymappings.nix`, `which-key.nix` | `keymaps.el` |
| — (no nvim counterpart) | `commands.el` |

`commands.el` is the one file with no nixvim mirror: small helpers with no
package of their own, required before every module that calls one and before
`keymaps.el`, which binds most of them. `my/on-first-frame` lives there — the
Emacs process can start before the compositor has given it a frame, so anything
probing frame parameters at load time has to wait for the first client.

That is 32 files; if this table and `ls lisp/` disagree, the table is the one
that is wrong.

Adding a module means writing the file **and** naming it in `my/modules`; the
directory is linked wholesale, so a file nobody requires is dead weight rather
than an error. A module that throws is caught, recorded in `my/module-errors`
and reported as a warning after startup — the editor still comes up with keys.

### The leader map is the nvim leader map

`keymaps.el` uses nvim's groups letter for letter (`a b c d f g h i l m n o p s
t u w x`). Three Emacs-only groups took the shifted key of whatever displaced
them: **`SPC H` help-map**, **`SPC P` project**, **`SPC N` org notes**, and
`SPC U` is `universal-argument`. Do not "fix" `SPC h` back to help — it is
Harpoon on both sides on purpose.

### The failure mode to check for

**A command bound in `keymaps.el` must be autoloaded.** Most packages here are
deferred by `:hook` or `:after`, and a function without an autoload cookie is
`void-function` until its file loads. `:after` is the trap: it defers the whole
`use-package` form, *including the autoloads `:commands` would have installed*,
so `org-download-clipboard` under `:after org` was void until org loaded for
some other reason. Either list the command in `:commands` on a form with no
`:after`, or write a bare `(autoload 'cmd "feature" nil t)` next to it. This is
the same job lz-n's `keys` trigger does in nvim.

Verify without a rebuild — this catches both classes in one run:

```sh
em=$(nix build --no-link --print-out-paths \
      .#nixosConfigurations.nixos-btw.config.home-manager.users.mayon.programs.emacs.finalPackage)
t=$(mktemp -d); src=modules/home/programs/dev/emacs
sed "s|@treesitGrammars@||" $src/early-init.el > $t/early-init.el
cp $src/init.el $t/; cp -r $src/lisp $t/
grep -oE "#'[a-zA-Z0-9/_-]+" $t/lisp/keymaps.el | sed "s/#'//" | sort -u > $t/cmds
$em/bin/emacs --batch --init-directory=$t -l $t/early-init.el \
  --eval '(package-activate-all)' -l $t/init.el \
  --eval '(progn (dolist (f my/module-errors) (princ (format "MODULE-FAIL %S\n" f)))
                 (with-temp-buffer (insert-file-contents (expand-file-name "cmds" user-emacs-directory))
                   (dolist (c (split-string (buffer-string) "\n" t))
                     (unless (fboundp (intern c)) (princ (format "VOID %s\n" c))))))'
```

Measured 2026-09-18 after the split: 31 modules, 0 failures, 145 leader
commands, 0 void.

### Everything else

- **Packages can only be added in `default.nix`.** There is no writable
  `package-user-dir`, so `M-x package-install` cannot work. The list there is
  grouped by the `lisp/` module that consumes each package; keep it that way.
- New files under `emacs/` must be `git add`-ed before `nixos-rebuild` sees
  them — a flake only reads tracked files, and an untracked `lisp/` fails
  evaluation with a `git add` hint rather than a missing-module error.
- `package-enable-at-startup` must stay **on** — `package-activate-all` is the
  only thing that loads each package's `-autoloads.el` out of
  `share/emacs/site-lisp/elpa/`. Turn it off and the packages land on the
  load-path with every autoloaded command still void (`void-function
  doom-modeline-mode`). `early-init.el` is authoritative here.
- Tree-sitter grammars are a curated subset; `with-all-grammars` is 279 MiB.
  The chosen path is substituted into `early-init.el`, and the subset has to
  match the remaps in `lisp/edit-treesit.el`.
- Scratch config that should not require a rebuild goes in
  `~/.config/emacs/personal.el`, loaded last.
- gptel reads `/run/secrets/deepseek-api-key` through a lambda, not an env var
  — the daemon never sourced the zsh profile. See the `sops-secrets` skill.
- The theme is `doom-tokyo-night`, the same scheme as nvim, noctalia and the
  rest of the host. (It used to be `doom-nord` against nvim's OneDark, on the
  theory that Emacs should match the fcitx5 candidate window; that whole
  divergence was retired on 2026-09-19.) `doom-themes`, not a standalone
  tokyonight package, because doom ships the face definitions magit, org and
  doom-modeline expect. Emacs cannot follow noctalia at runtime, so it is
  hand-pinned — see the two-tier colour rule in `desktop-apps`.

## Per-project environments

direnv + nix-direnv (`modules/home/programs/dev/direnv.nix`). Drop a `.envrc`
containing `use flake` in a project directory. Do not add project-specific
toolchains to `toolchain.nix`.
