---
name: gaming-stack
description: 修改或排查 Steam、gamescope、gamemode、MangoHud、PrismLauncher，含游戏 GPU 选择、运行库与 Minecraft JDK。
---

# Gaming stack

| Component | Configuration |
|---|---|
| Steam and gamescope session | `modules/system/programs/steam.nix` |
| gamescope | `modules/system/programs/gamescope.nix` |
| gamemode | `modules/system/desktop/gamemode.nix` |
| NVIDIA PRIME | `modules/system/hardware/nvidia.nix` |
| MangoHud | `modules/home/programs/games/mangohud.nix` |
| PrismLauncher | `modules/home/programs/games/prismlauncher.nix` |

Steam, gamescope, and gamemode are system-level settings; MangoHud and PrismLauncher are per-user. Keep a setting at the level its NixOS or Home Manager module expects.

## GPU selection

The current NVIDIA module enables PRIME offload and `enableOffloadCmd`. Games may use Intel unless explicitly launched on the NVIDIA GPU. For a Steam title, try `nvidia-offload %command%`; for other launchers, use the offload environment expected by the driver. Check the current module and available wrapper before changing launch syntax.

Use MangoHud's GPU statistics and Vulkan driver fields to confirm which GPU is active. A high frame time alone does not establish a PRIME configuration problem.

The host's NVIDIA power-management and persistence settings have documented driver/shutdown interactions in `modules/system/hardware/nvidia.nix`. Read those comments before changing PRIME mode or power management, and consult the relevant host hardware guidance if available.

## GameMode and Steam

Gamemode currently requests NVIDIA performance settings and sends desktop notifications from its start/end hooks. If notifications do not appear, verify that the game actually requests GameMode (for example, `gamemoderun %command%` in Steam) before changing the service configuration.

Steam enables its gamescope session and includes MangoHud in the Steam environment. Its firewall options are explicit; review the port impact before enabling additional game-server or networking options.

For a missing shared library, first identify whether the game runs inside Steam's FHS environment or outside it. The system also configures `nix-ld`; check that module or `steam-run` for a non-Steam binary before attempting ad hoc binary patching.

## PrismLauncher and JDKs

PrismLauncher pins no JDKs: `jdks = [ ]` in `modules/home/programs/games/prismlauncher.nix` keeps nixpkgs' default OpenJDK set out of the launcher closure. The module also filters the resulting empty `PRISMLAUNCHER_JAVA_PATHS` prefix out of `qtWrapperArgs`, because wrapQtAppsHook word-splits it and the wrapper build fails otherwise. Prism detects the `java` on PATH (Temurin, via `session-vars.nix`) by itself; add an older JDK manually in Settings when an instance needs one. The installed Temurin set is single-sourced in `lib/java.nix`; Java 26 still comes from `pkgs-unstable`, so recheck channel availability when updating the package set.

Minecraft instances, worlds, and user data live under `~/.local/share/PrismLauncher`; the Nix module configures the application package rather than managing that mutable data.

## Verification

After a change, format and evaluate the flake. Reproduce the game launch path in question, then check MangoHud for GPU, Vulkan driver, and GameMode status. Avoid inferring successful offload solely from the presence of an NVIDIA driver or from an enabled overlay.
