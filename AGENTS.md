# AGENTS.md

Guidance for AI coding agents (Claude Code, Codex, Grok, opencode) working in
this repository. `CLAUDE.md` is a symlink to this file — one source, no drift.

This file is an **index**, kept deliberately short because it is loaded into
every session. The detail lives in `.claude/skills/`; load a skill only when
the table below says it applies. Claude Code discovers those automatically;
other agents should `cat` the path.

## What this is

A NixOS + Home Manager configuration built with **flake-parts**. One host:
`nixos-btw` — Intel + NVIDIA laptop, 2560×1600, niri compositor, user `mayon`.

```
flake.nix          inputs (see the nix-modules skill for the table)
flake/             flake-parts modules (system.nix, dev.nix)
hosts/nixos-btw/   host entry + hardware
lib/               one helper: importDir
modules/system/    NixOS modules   — auto-imported
modules/home/      Home Manager modules for `mayon` — auto-imported
nixvim/            Neovim config (repo root on purpose — see nix-modules skill)
secrets/           age-encrypted secrets.yaml
```

## Commands

```sh
sudo nixos-rebuild switch --flake .#nixos-btw   # or: nr   (nh os switch)
nix fmt              # nixfmt + deadnix + statix via treefmt — run before committing
nix flake check
nc                   # nh clean all (also runs weekly)
nix develop          # git, gnumake, clang-tools, sops tooling
nix develop .#cuda   # cudatoolkit, cudnn, nvcc
```

## Rules that apply everywhere

1. **`importDir` loads every `.nix` file under `modules/`, with no skip
   mechanism.** Never put a non-module `.nix` file there.
2. Every module file is a function: `_: { … }` or `{ pkgs, lib, ... }: { … }`.
   `inputs` and `pkgs-unstable` are available via `specialArgs`.
3. `pkgs` is **stable nixos-26.05** and is the default. `pkgs-unstable` is for
   fast-moving packages only (`claude-code`, `github-copilot-cli`, `antigravity`).
4. Home Manager runs **as a NixOS module** — `nixos-rebuild` applies both.
5. Never put a secret in a `.nix` file; everything in a module is world-readable
   in `/nix/store`.
6. `noctalia-greeter`, `mark-shot`, `wayscrollshot` and `llm-agents` are
   deliberately **not** `follows`-ed. Do not "tidy" those.
7. Comments explain *why*, not *what* — most of the surprising code here is
   load-bearing and already carries the reason. Read the comment before deleting
   a workaround.

## Skill index

| Load | When |
|---|---|
| [nix-modules](.claude/skills/nix-modules/SKILL.md) | adding/moving/deleting a module, module not applied, choosing a channel, editing `flake.nix` or `flake/system.nix` |
| [sops-secrets](.claude/skills/sops-secrets/SKILL.md) | adding/rotating a secret, empty credential at runtime, editing `secrets/secrets.yaml` or `modules/system/security/sops.nix` |
| [dev-toolchain](.claude/skills/dev-toolchain/SKILL.md) | LSP servers, formatters, linters, nvim/nixvim, Emacs, DAP adapters, nvim closure size |
| [editors-ide](.claude/skills/editors-ide/SKILL.md) | JetBrains, VS Code, Antigravity, the `llm-agents` CLIs (codex/grok/opencode/dsh/zcode) |
| [desktop-niri](.claude/skills/desktop-niri/SKILL.md) | niri keybinds/window rules, noctalia, xdg portals, screenshots, fcitx5 DPI, clipboard |
| [host-hardware](.claude/skills/host-hardware/SKILL.md) | NVIDIA/PRIME, Docker, libvirt, earlyoom, sshd/firewall, clash/TUN, why there is no Flatpak |

## Delegating to another engine

`codex` and `grok` are installed. Use the user-level `delegate-cli` skill
(`~/.claude/skills/delegate-cli/SKILL.md`) before hand-rolling a `codex exec` or
`grok -p` command line — the safe invocation shape is not the default one, and
delegated *writes* must go through a git worktree.
