# AGENTS.md

Guidance for AI coding agents (Claude Code, Codex, Grok, opencode) working in
this repository. `CLAUDE.md` is a symlink to this file — one source, no drift.

This file is an **index**, kept deliberately short because it is loaded into
every session. The detail lives in `.claude/skills/`; load a skill only when
the table below says it applies. Claude Code discovers those automatically;
other agents should `cat` the path.

## What this is

A NixOS + Home Manager configuration built with **flake-parts**. One host:
`nixos-btw` — Intel + NVIDIA laptop, 2560×1600, mango compositor, user `mayon`.

```
flake.nix          inputs (see the nix-modules skill for the table)
flake/             flake-parts modules (system.nix, dev.nix)
hosts/nixos-btw/   host entry + hardware
lib/               one helper: importDir
modules/system/    NixOS modules   — auto-imported
modules/home/      Home Manager modules for `mayon` — auto-imported
nixvim/            Neovim config (repo root on purpose — see nix-modules skill)
pkgs/              hand-written derivations for what nixpkgs lacks
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
   fast-moving packages only (`claude-code`, `github-copilot-cli`,
   `antigravity-ide-fhs`/`antigravity-cli`, `typora`), plus the single-attribute
   exceptions the nix-modules skill lists.
4. Home Manager runs **as a NixOS module** — `nixos-rebuild` applies both.
5. Never put a secret in a `.nix` file; everything in a module is world-readable
   in `/nix/store`.
6. `mango`, `noctalia-greeter`, `mark-shot`, `wayscrollshot` and `llm-agents`
   are deliberately **not** `follows`-ed. Do not "tidy" those.
7. Comments explain *why*, not *what* — most of the surprising code here is
   load-bearing and already carries the reason. Read the comment before deleting
   a workaround.

## Skill index

Ten skills, one per area. Load the one whose row matches before editing files in
that area — each carries the measurements and the failure modes behind the code.

| Load | When |
|---|---|
| [nix-modules](.claude/skills/nix-modules/SKILL.md) | adding/moving/deleting a module, module not applied, choosing a channel, editing `flake.nix`, `flake/system.nix` or `flake/dev.nix` |
| [sops-secrets](.claude/skills/sops-secrets/SKILL.md) | adding/rotating a secret, empty credential at runtime, editing `secrets/secrets.yaml` or `modules/system/security/sops.nix` |
| [nvim-config](.claude/skills/nvim-config/SKILL.md) | any change under `nixvim/` — adding a plugin, lazy-loading, keymaps, an option that does not apply |
| [dev-toolchain](.claude/skills/dev-toolchain/SKILL.md) | LSP servers, formatters, linters, Emacs, DAP adapters, per-language compilers, nvim closure size |
| [editors-ide](.claude/skills/editors-ide/SKILL.md) | JetBrains, VS Code, Antigravity, the `llm-agents` CLIs (codex/grok/opencode/dsh/zcode) |
| [shell-terminal](.claude/skills/shell-terminal/SKILL.md) | zsh aliases/functions, env vars vs. `session-vars.nix`, foot, tmux, yazi, git/delta/gh |
| [desktop-mango](.claude/skills/desktop-mango/SKILL.md) | mango keybinds/window rules/tags, noctalia, greeter, xdg portals, screenshots, clipboard, fcitx5 DPI |
| [desktop-apps](.claude/skills/desktop-apps/SKILL.md) | GTK/Qt/font theming, default applications, Thunar actions, mpv/zathura/Zen, QQ/WeChat packaging |
| [gaming-stack](.claude/skills/gaming-stack/SKILL.md) | Steam, gamescope, gamemode, MangoHud, PrismLauncher, running a game on the dGPU |
| [host-hardware](.claude/skills/host-hardware/SKILL.md) | NVIDIA/PRIME, Docker, libvirt, earlyoom, sshd/firewall, clash/TUN + nix-daemon proxy, why there is no Flatpak |

## Delegating to another engine

`codex` and `grok` are installed. Use the user-level `delegate-cli` skill
(`~/.claude/skills/delegate-cli/SKILL.md`) before hand-rolling a `codex exec` or
`grok -p` command line — the safe invocation shape is not the default one, and
delegated *writes* must go through a git worktree.
