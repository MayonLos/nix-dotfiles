---
name: editors-ide
description: Packaging workarounds for the GUI IDEs and AI coding agents installed on this host — JetBrains, VS Code, Antigravity, and the llm-agents CLIs (codex, grok, opencode, dsh, zcode). Use when a JetBrains welcome screen hangs or its renderer fails to load, when a VS Code extension's bundled binary cannot find a shared library, when adding or upgrading an AI coding agent, when editing jetbrains.nix / vscode.nix / antigravity.nix / ai-agents.nix, or when ZCode's desktop entry or fcitx5 input breaks after an update.
---

# IDEs and agent CLIs

All of these live in `modules/home/programs/dev/`.

## jetbrains.nix — the wrapper is load-bearing

IDEA / PyCharm / CLion / WebStorm / DataGrip / RustRover. Each is wrapped in a
`symlinkJoin` + `wrapProgram` that prepends `libGL`, `libx11`, `fontconfig` and
`libstdc++` to `LD_LIBRARY_PATH`.

**Do not delete this wrapper as redundant.** nixpkgs' 2026.2 JetBrains packages
ship `lib/skiko-awt-runtime-all/libskiko-linux-x64.so` with its RPATH pointing
at the *build* directory (`/build/…/remote-dev-server/selfcontained/lib`). The
Compose/Skiko renderer then fails to load: the welcome screen spins forever and
clicks do nothing.

Upstream's `extraLdPath` argument cannot be reached through `overrideAttrs` — it
sits in `lib.extendMkDerivation`'s `excludeDrvArgNames` — which is why the fix
has to be an outer wrapper. Remove it only once nixpkgs fixes the RPATH.

## vscode.nix — use vscode-fhs, not per-library patching

Uses `pkgs.vscode-fhs`. Extension-shipped binaries (cpptools' `OpenDebugAD7`,
STM32Cube's node-usb binding) need `libstdc++` *and* `libudev`; patching
libraries one at a time was whack-a-mole and kept regressing.

If another library is ever needed, switch to
`pkgs.vscode.fhsWithPackages (ps: [ … ])` rather than going back to a
hand-rolled `LD_LIBRARY_PATH` override.

## antigravity.nix

Goes through the Home Manager `programs.antigravity` / `programs.antigravity-cli`
modules. The CLI binary is `agy`.

Both packages are set **explicitly** to `pkgs-unstable.*`, because those modules
default to `pkgs.antigravity*` from **stable**, where 26.05 carries only an
older IDE (1.23.2) and no `antigravity-cli` at all. Do not drop the explicit
`package` on the assumption the default is fine.

The IDE is the **FHS** variant (`antigravity-ide-fhs`): it pulls prebuilt
binaries for extensions and language servers, which need a normal filesystem
layout to load. Same reasoning as `vscode-fhs` above.

## ai-agents.nix — the llm-agents input

Every AI coding agent that comes from the `llm-agents` flake input rather than
nixpkgs: `codex`, `chatgpt`, `dsh`, `grok`, `opencode`, `zcode`, plus `ccusage`,
`crit`, `mcporter`, `sandbox-runtime` (binary is `srt`) and `workmux`.

All of it is prebuilt on `cache.numtide.com` — the substituter is added in
`modules/system/core/nix.nix`. Nothing here compiles locally, so an unexplained
long build means the substituter or the input pin is wrong.

`claude-code` and `github-copilot-cli` stay in `modules/home/packages.nix`;
their own sources track upstream closely enough.

Notes worth knowing before touching this file:

- **codex** used to be its own module (`dev/codex/`) that wrapped the
  `codex-cli` input in a launcher forcing DeepSeek onto bare `codex`. That is
  gone. Bare `codex` is now the ChatGPT account, which is the point.
  `~/.codex/config.toml` is codex's own file, unmanaged by Nix.
- **dsh** alone is an error — it needs a profile, and only `dsh web` and
  `dsh --profile headless "<task>"` ship. The `tui` and `code` profiles in
  upstream's `--help` do not exist here. Plugins install at runtime via pnpm
  into `$DSH_HOME`, i.e. mutable state outside the store.
- **grok** provides both `grok` (interactive) and `agent` (automation).
  Auth is browser OAuth on first launch, or `XAI_API_KEY`.

## ZCode's desktop entry — why the module owns it

ZCode rewrites `~/.local/share/applications/zcode.desktop` on **every launch**,
pointing `Exec` at `lib/ZCode/zcode`, the raw Electron binary rather than the
`bin/zcode` wrapper. Since `~/.local/share` outranks `/etc/profiles` in
`XDG_DATA_DIRS`, that self-written entry wins for both the launcher and the
`zcode://` OAuth callback. Result: ZCode starts without `--enable-wayland-ime`
(so no fcitx5 input) and without xdg-utils on `PATH`, from a hard-coded store
path that `nh clean` later turns dangling.

`ai-agents.nix` owns the file so every activation restores the correct entry.
It does **not** stop the rewrite — ZCode unlinks the symlink and writes a fresh
0600 file. The entry is only guaranteed correct between an activation and the
next launch.

`force = true` is what keeps this from breaking boot: with
`home-manager.backupFileExtension = "backup"`, the second activation after a
rewrite found a leftover `zcode.desktop.backup` in the way, failed
`checkLinkTargets`, and took `home-manager-mayon.service` down at startup.
`force` overwrites in place and never backs up. **Do not remove it.**

`xdg.enable` is false on this host, so `xdg.desktopEntries` emits nothing —
that is why the file is written through `home.file` directly.

## Delegating work to the agent CLIs

See AGENTS.md's "Delegating to another engine" section, and the `delegate-cli`
skill it points at, before hand-rolling any invocation of these binaries.
