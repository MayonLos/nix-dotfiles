---
name: editors-ide
description: 修改 JetBrains、VS Code 与 AI CLI 的 Nix 打包；排查 IDE 运行库、wrapper、桌面启动器和 ai-agents.nix。
---

# IDEs and coding agents

The configuration is under `modules/home/programs/dev/`. Keep fixes at the
packaging boundary that owns the failure and verify against the current pinned
packages before removing an existing wrapper.

## JetBrains

`jetbrains.nix` wraps each IDE with `LD_LIBRARY_PATH` entries for graphics,
X11, fonts, and C++ runtime libraries. The wrapper addresses a Skiko renderer
failure associated with a build-time RPATH in the pinned package. Do not call
it redundant based only on successful evaluation; inspect the current package
and confirm its runtime behavior before removing it.

## VS Code

`vscode.nix` uses `pkgs.vscode-fhs` because extension-shipped binaries may
require system libraries such as `libstdc++` and `libudev`. If another library
is missing, extend the FHS package with
`pkgs.vscode.fhsWithPackages (ps: [ ... ])` rather than accumulating ad hoc
library patches.

## Coding-agent packages

`ai-agents.nix` takes selected prebuilt packages from the locked `llm-agents`
flake input; `github-copilot-cli` is managed elsewhere.
Inspect `flake.lock` and package definitions before relying on version, cache,
binary, or command-line details. Do not infer CLI behavior from package names.

The codex package here is the user's ChatGPT-account CLI; its
`~/.codex/config.toml` is unmanaged by Nix. The package list also includes
`dsh`, `grok`, `opencode`, `ccusage`, `crit`, `mcporter`,
`sandbox-runtime` (binary `srt`), and `workmux`; verify current package
attributes before adding or removing entries.

`bin/codex` is shadowed by a `--no-daemon` shim in the same module, because
codex 0.157 needs a complete CLI package layout (manifest, `codex-path/rg`, an
in-root `codex-resources/bwrap`) before it will install its app-server daemon,
and llm-agents ships only the binaries. Do not "fix" this by completing the
layout: the daemon copies the CLI into `~/.codex` and then runs a network
auto-updater, which would replace the Nix-provided binary. Re-read the comment
in `ai-agents.nix` before touching it, and drop the shim only when llm-agents
handles the layout itself.

`dsh` uses the shipped web/headless profiles; do not assume every profile named
in upstream help is packaged. Its plugins are mutable runtime data.
`ai-agents.nix` installs a patched `dshCli` rather than `agents.dsh`: nixpkgs
Node is compiled with leaf frame pointers, which breaks the
`node-addon-require-builtin` machine-code decoder at boot ("x64 sysv getter is
not a recognized this->field accessor ..."). The patch stubs that addon to
`require` plus the already-passed `--expose-internals`; keep it until a fixed
Node or dsh lands (NixOS/nixpkgs#565667, llm-agents.nix#9994).
For an Electron app that rewrites its desktop entry, check whether Exec still
uses the wrapper and whether an old Home Manager `.backup` blocks activation.
Resolve file ownership before adding `force = true`; see `desktop-apps`.

ZCode was explicitly removed after it pushed to a user repository without
being asked. Do not restore it unless the user explicitly requests it.
Antigravity (IDE + CLI) was removed on 2026-09-20 as unused and re-added on
2026-10-01 at the user's request; `programs/antigravity.nix` is the module.
The IDE needs `pkgs-unstable.antigravity-ide-fhs` (stable 26.05 has no
`antigravity-ide-fhs` attribute; the FHS build is what lets extension language
servers load), while the CLI is `agents.antigravity-cli` from llm-agents
(binary `agy`, newer than unstable). `codecompanion`'s CLI agent list drives
`agy`; keep the three in sync when moving packages around.

## Verification

Distinguish evaluation, build, and runtime checks. An evaluation confirms Nix
expressions resolve; a build checks derivations; launching the actual wrapped
application checks runtime library and desktop-entry behavior. Avoid commands
or delegation instructions that depend on Claude-specific skills or tools;
repository-wide agent coordination belongs in `AGENTS.md`.

ChatGPT desktop was removed at the user's request on 2026-09-28 after task
startup kept hanging. Keep Codex CLI installed. Desktop-only `node_repl`,
`browser`, `unified-computer-use`, and `codex-app-tools` integrations were
disabled in mutable Codex configuration; user data was retained.
