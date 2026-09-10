---
name: gaming-stack
description: Steam, gamescope, gamemode, MangoHud and PrismLauncher on this laptop, and how they interact with PRIME offload and the JDK set. Use when a game will not launch or runs on the wrong GPU, when adding or tuning gamemode/MangoHud settings, when changing the JDKs PrismLauncher offers to Minecraft instances, when a game needs a library NixOS does not have, or when deciding where a gaming-related package belongs.
---

# Gaming

| Piece | File | Level |
|---|---|---|
| Steam (+ gamescope session) | `modules/system/programs/steam.nix` | NixOS |
| gamescope | `modules/system/programs/gamescope.nix` | NixOS |
| gamemode | `modules/system/desktop/gamemode.nix` | NixOS |
| MangoHud | `modules/home/programs/games/mangohud.nix` | Home Manager |
| PrismLauncher | `modules/home/programs/games/prismlauncher.nix` | Home Manager |

The split is not arbitrary: Steam, gamescope and gamemode all need setuid
helpers, firewall holes or a system dbus service, so they cannot be Home Manager
options. MangoHud and PrismLauncher are per-user config and packages.

## This is a PRIME offload laptop

`modules/system/hardware/nvidia.nix` runs **offload**, so nothing uses the
dGPU unless it is asked to. A game launched from Steam with no launch options
runs on Intel and will look inexplicably slow.

Put `nvidia-offload %command%` (the wrapper `prime.offload.enableOffloadCmd`
installs) in the game's Steam launch options, or set `__NV_PRIME_RENDER_OFFLOAD=1
__GLX_VENDOR_LIBRARY_NAME=nvidia` for a non-Steam launch. MangoHud's `gpu_stats`
row is the quickest confirmation of which GPU actually got the work.

Do not "fix" a slow game by switching `nvidia.nix` to sync/reverse-sync PRIME —
the shutdown-oops settings there are tuned for offload; the `host-hardware` skill
explains why `finegrained` and `nvidiaPersistenced` must stay as they are.

## gamemode talks to the NVIDIA driver directly

`apply_gpu_optimisations = "accept-responsibility"` with `gpu_device = 0` and
`nv_powermizer_mode = 1` (prefer maximum performance while a game holds the
gamemode lock). `gpu_device = 0` is the NVIDIA device index as
`nvidia-settings` numbers GPUs, not a DRM card number — it does not need to
change if the Intel card is present.

The `custom.start`/`custom.end` hooks fire `notify-send`, which is how you tell
whether a game actually entered gamemode. If those notifications never appear,
the game is not requesting it (Steam launch option `gamemoderun %command%`).

## Steam

`gamescopeSession.enable` gives the Steam Deck-style session at the greeter;
MangoHud is in `extraPackages` so the overlay is inside Steam's FHS environment,
where a profile-level install would not be visible. Remote Play, dedicated server
and LAN transfer firewall holes are all open.

A game missing a shared library is an FHS problem, not a packaging one: Steam
already runs inside its own FHS env, and outside it the answer is `nix-ld`
(`modules/system/programs/nix-ld.nix`) or `steam-run`. Do not start patchelfing.
Flatpak is not an option here — see `host-hardware`.

## PrismLauncher and the JDK set

Overridden with `additionalPrograms` (ffmpeg, mangohud, gamescope),
`gamemodeSupport = true`, and an explicit `jdks` list: temurin 8, 17, 21, 25 from
stable plus **26 from `pkgs-unstable`**, because stable 26.05 does not carry it.

That JDK list mirrors `modules/home/programs/dev/java.nix` and the `JAVA*_HOME`
set in `session-vars.nix`. Adding a Java version means touching all three, or the
version you can select in Prism will not be the one `use-java` gives you in a
shell — the `shell-terminal` skill covers that side.

Minecraft instances, mods and worlds are mutable state under
`~/.local/share/PrismLauncher`; nothing here manages them.

## MangoHud

`programs.mangohud` settings only. The overlay toggles with `Shift_R+F12`. It
reports gamemode status and the Vulkan driver in use, which makes it the fastest
way to check that offload and gamemode both took effect before blaming the game.
