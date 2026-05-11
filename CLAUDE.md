# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Format

```sh
# Rebuild the system (includes home-manager)
sudo nixos-rebuild switch --flake .#nixos-btw
# or via nh alias:
nr   # nh os switch ~/nix-dotfiles

# Clean old generations
nc   # nh clean all

# Format all Nix files (nixfmt + deadnix + statix via treefmt)
nix fmt

# Enter dev shell (git, gnumake, clang-tools; or use cuda shell)
nix develop
```

## Architecture

This is a NixOS + Home Manager configuration using **flake-parts**. There is one host: `nixos-btw` (Intel + NVIDIA laptop, 2560×1600, niri compositor).

### Module auto-import

The `importDir` function (defined in both [flake/system.nix](flake/system.nix) and [hosts/nixos-btw/default.nix](hosts/nixos-btw/default.nix)) recursively imports every `.nix` file in a directory — just add a `.nix` file and it's automatically included. No manual import registration needed.

- `modules/home/` → auto-imported into Home Manager (user `mayon`)
- `modules/system/` → auto-imported into NixOS via the host entry

### Dual channel setup

- `pkgs` = **nixos-25.11** (stable) — used for system packages and most user packages
- `pkgs-unstable` = **nixos-unstable** — used for fast-moving packages (claude-code, copilot-cli, qq, go-musicfox, codex, gemini-cli)
- `specialArgs` passes both to all NixOS and Home Manager modules
- `allowUnfree = true` globally, USTC mirror configured for faster downloads in China

### Key flake inputs

| Input | Used for |
|---|---|
| `niri-flake` | NixOS module for niri compositor (auto-starts via systemd) |
| `MyNixvim` | Custom Neovim build from separate repo |
| `noctalia-shell` | Launcher, lock screen, clipboard, session menu |
| `claude-code-nix` | Claude Code CLI (overlay adds it to unstable) |
| `treefmt-nix` | Formatter orchestration (not a manual formatter config) |

### lib/ helpers

The [lib/](lib/) directory provides reusable Nix helpers:

- `keybind-helpers.nix` — `mkActionBinds`, `mkLockedSpawnShBinds`, `mkWorkspaceBinds`, `mergeMany` for DRY niri keybind definitions
- `obsidian-helpers.nix` — Obsidian vault helpers

These are accessed by path import (e.g., `import ../../../../lib/keybind-helpers.nix`) in modules that need them, not merged into `lib`.

### Home Manager integration

Home Manager runs as a **NixOS module** (not standalone), activated via `home-manager.nixosModules.home-manager` with `useGlobalPkgs = true`. The `users.mayon` import tree covers all `modules/home/`.

## Key patterns

- Every module file is a function (`_: { ... }` or `{ pkgs, lib, ... }: { ... }`)
- Niri keybinds are generated programmatically using `lib/` helpers to reduce repetition (vim arrows + arrow keys, media keys, workspaces 1-9)
- Systemd services for the compositor are defined in `modules/system/desktop/niri.nix` and `modules/system/services/systemd.nix`
- NVIDIA uses PRIME offload (not full-time GPU), configured in `modules/system/hardware/nvidia.nix`
- Shell uses **no framework** — pure Home Manager built-ins (`autosuggestion`, `syntaxHighlighting`, `plugins`) with starship prompt and zoxide; no oh-my-zsh or plugin managers
- Per-project dev environments use **direnv + nix-direnv** (`modules/home/programs/dev/direnv.nix`); add a `.envrc` with `use flake` in any project directory
- Git diffs use **delta** as pager, configured via `programs.git.delta`
- **earlyoom** runs as a system service to prevent OOM freezes (`modules/system/services/oom.nix`)
- Window shadows are configured globally in `modules/home/wm/niri/rules.nix` via the first catch-all window-rule
