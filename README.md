# nix-dotfiles

NixOS & Home Manager configuration — "NixOS from Scratch."

## Structure

```
├── flake.nix              # Flake entry — inputs, flake-parts orchestration
├── flake.lock             # Pinned dependency lockfile
├── hosts/                 # Machine-specific configs
│   └── nixos-btw/         #   Primary NixOS host
│       ├── default.nix    #     Entry — recursively imports modules/system/*
│       └── hardware.nix   #     Auto-generated hardware config (filesystems, CPU)
├── modules/
│   ├── home/              # Home Manager modules (user-level programs & services)
│   │   ├── base/          #   Core user identity: username, GTK, input-method, XDG, session vars
│   │   ├── wm/niri/       #   Niri compositor: autostart, keybinds, window rules, animations, shadows
│   │   ├── programs/      #   User applications
│   │   │   ├── apps/      #     firefox, mpv, obsidian, obs-studio, screenshot, yazi, zathura...
│   │   │   ├── dev/       #     git (delta), direnv, latex, llvm, python, vscode
│   │   │   ├── games/     #     prismlauncher
│   │   │   └── terminal/  #     foot, tmux
│   │   ├── shell/         #   Zsh — HM native, starship prompt, zoxide, fzf-tab
│   │   ├── services/      #   clipboard, cliphist
│   │   └── packages.nix   #   User packages incl. bat, eza, ripgrep, delta, lazygit, nh, nom
│   └── system/            # NixOS modules (system-wide config)
│       ├── core/          #   boot (systemd-boot, docker, zram/zstd), locale, network, nix settings
│       ├── desktop/       #   niri compositor, gamemode, xdg portal
│       ├── hardware/      #   audio (pipewire + echo cancel), bluetooth, firmware, nvidia (prime offload)
│       ├── programs/      #   clash, gamescope, libreoffice, nix-ld, thunar, system zsh
│       ├── security/      #   polkit
│       ├── services/      #   earlyoom, openssh, systemd user services
│       └── user/          #   mayon user, fonts, environment vars
├── lib/                   # Helper libraries
│   ├── default.nix        #   Combinator — merges sub-libs
│   ├── keybind-helpers.nix
│   └── obsidian-helpers.nix
└── flake/
    ├── system.nix         # NixOS + Home Manager wiring (auto-imports modules)
    └── dev.nix            # Dev shells (default, cuda), treefmt config
```

## Key Dependencies

| Input | Purpose |
|-------|---------|
| `nixpkgs` (25.11) | Stable package set |
| `nixpkgs-unstable` | Unstable channel (claude-code, QQ, go-musicfox, copilot-cli, codex, gemini-cli) |
| `home-manager` (25.11) | User-environment management |
| `niri-flake` | Niri Wayland compositor |
| `MyNixvim` | Custom Neovim distribution |
| `noctalia-shell` | Bar, launcher, lock screen, clipboard, session menu |
| `claude-code-nix` | Claude Code CLI package |

## Hosts

- **nixos-btw** — Intel + NVIDIA laptop, 2560×1600@165Hz, NixOS 25.11 with niri compositor

## Quick Reference

```sh
nr          # rebuild system  (nh os switch ~/nix-dotfiles)
nc          # clean old gens  (nh clean all)
nix fmt     # format all .nix files
```

Shell aliases: `ls/ll/la/lt` → eza · `cat` → bat · `lg` → lazygit · `z` → zoxide
