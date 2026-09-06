---
name: nix-modules
description: Structure rules for this NixOS flake — how modules are discovered and imported, which nixpkgs channel a package must come from, and what arguments a module file receives. Use when adding, moving, renaming or deleting any .nix file under modules/, when a new module is silently not applied or breaks evaluation, when deciding between pkgs and pkgs-unstable for a package, when touching flake.nix inputs or flake/system.nix, or when wondering why nixvim lives in the repo root instead of under modules/.
---

# Module structure

## importDir: every .nix file is loaded, no exceptions

`lib/import-dir.nix` (exposed as `importDir` from `lib/default.nix`, used by
`flake/system.nix` and `hosts/nixos-btw/default.nix`) recurses a directory and
imports **every** `.nix` file it finds.

- `modules/home/` → Home Manager modules for user `mayon`
- `modules/system/` → NixOS modules, pulled in by the host entry

Adding a module means dropping a file in the right directory. There is no
import list to update.

**There is no skip mechanism** — not for `_`-prefixed directories either.
`modules/home/_assets` and `modules/home/wm/niri/_plugins` survive only because
neither contains a `.nix` file. Consequences:

- Never put a non-module `.nix` file (a helper, a package expression, a
  fragment meant to be `import`ed by hand) anywhere under `modules/`. It will
  be evaluated as a module and fail.
- This is why the Neovim config lives at `nixvim/` in the repo root: its ~70
  files are nixvim modules, and `importDir` would load each one as a broken
  Home Manager module. `modules/home/programs/dev/nvim.nix` is the single file
  that reaches out to it.

Same rule applies to anything else you might be tempted to add: package
expressions, shared option sets, data files with a `.nix` extension. Put them
in `lib/` or the repo root, not `modules/`.

## Module file shape

Every module file is a function:

```nix
_: {
  # no arguments needed
}
```

```nix
{ pkgs, lib, ... }: {
  # ...
}
```

`specialArgs` (NixOS) and `extraSpecialArgs` (Home Manager) both carry
`inputs` and `pkgs-unstable`, so any module can take them:

```nix
{ pkgs, pkgs-unstable, inputs, ... }: { }
```

## Which channel

| | Channel | Use for |
|---|---|---|
| `pkgs` | `nixpkgs` — **nixos-26.05** stable | system packages and most user packages; the default |
| `pkgs-unstable` | `nixpkgs-unstable`, plus the `claude-code` overlay | fast-moving packages only: `claude-code`, `github-copilot-cli`, `antigravity` |

`allowUnfree = true` on both. Reach for `pkgs-unstable` only when stable is
demonstrably too old for a package that must track upstream; a package pulled
from unstable drags its own dependency closure alongside the stable one.

Packages that come from a flake input rather than either channel (the
`llm-agents` agents, zen-browser, noctalia, mark-shot) are wired up in their
own modules — see `dev-toolchain` and `editors-ide`.

## Home Manager runs as a NixOS module

Activated via `home-manager.nixosModules.home-manager` with
`useGlobalPkgs = true` — not standalone. There is no separate `home-manager
switch`; a `nixos-rebuild switch` applies both. `home-manager.backupFileExtension
= "backup"` is set in `flake/system.nix`, which matters whenever a module owns
a file some application also rewrites at runtime (see `editors-ide` on ZCode).

## flake inputs

| Input | Used for |
|---|---|
| `nixpkgs` / `nixpkgs-unstable` | stable (nixos-26.05) + unstable channels |
| `flake-parts` | flake structure |
| `home-manager` | Home Manager as a NixOS module (release-26.05) |
| `nixvim` | Neovim module system; the config itself is in-tree at `nixvim/` |
| `mcp-hub` | MCP server binary that `nixvim/plugins/ai/mcphub.nix` points mcphub.nvim at |
| `noctalia` | Bar, launcher, lock screen, clipboard, session menu, OSD (quickshell) |
| `noctalia-plugins-official` / `noctalia-plugins-community` | plugin source trees (`flake = false`), consumed as `kind = "path"` so nothing is cloned at startup |
| `noctalia-greeter` | greetd login UI matching noctalia |
| `zen-browser` | Zen browser + its home-manager module (not in nixpkgs) |
| `mark-shot` / `wayscrollshot` | Wayland screenshot tools, neither in nixpkgs |
| `claude-code` | Claude Code CLI (overlay adds it to `pkgs-unstable`) |
| `llm-agents` | AI coding agents nixpkgs lacks or lags — codex, chatgpt, dsh, grok, zcode, opencode, and the review/usage tooling |
| `sops-nix` | encrypted secrets |
| `nix-index-database` | prebuilt weekly nix-index DB (command-not-found, `nix-locate`, comma) |
| `treefmt-nix` | formatter orchestration — not a hand-written formatter config |

niri is **not** an input; it comes from nixpkgs via `programs.niri.enable` in
`modules/system/desktop/niri.nix`.

**Do not add `inputs.nixpkgs.follows` to the inputs that lack it.**
`noctalia-greeter`, `mark-shot`, `wayscrollshot` and `llm-agents` each build
from source or publish to their own binary cache; pointing them at this flake's
nixpkgs breaks their builds or misses every prebuilt binary. Those four carry a
comment in `flake.nix` saying so. The cost is an extra nixpkgs evaluation.

`lib/default.nix` exposes exactly one helper, `importDir`. Keep it that way
unless something genuinely needs sharing across host and flake.

## Commands

The build, format and dev-shell commands are in AGENTS.md and are not repeated
here. Two notes that belong with structure rather than with the command list:

- `treefmt-nix` orchestrates the formatters (nixfmt + deadnix + statix). There
  is no hand-written formatter config to edit — change the treefmt settings in
  `flake/dev.nix`, not a `.nixfmt` file. Run `nix fmt` before committing.
- The real verdict on a structural change is
  `nix build .#nixosConfigurations.nixos-btw.config.system.build.toplevel`.
  Its `evaluation warning:` lines are where nixpkgs deprecations surface.
