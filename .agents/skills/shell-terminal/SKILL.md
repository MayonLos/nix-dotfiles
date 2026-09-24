---
name: shell-terminal
description: 修改 zsh、会话环境、kitty、tmux、yazi、Git 或 nix-index；排查终端与桌面启动程序的环境差异。
---

# Shell and terminal

The configuration is split across these Home Manager modules:

| Area | File |
|---|---|
| zsh, aliases, interactive functions, fzf | `modules/home/shell/zsh.nix` |
| launcher and shell environment | `modules/home/base/session-vars.nix` |
| kitty | `modules/home/programs/terminal/kitty.nix` |
| tmux | `modules/home/programs/terminal/tmux.nix` |
| yazi | `modules/home/programs/apps/yazi.nix` |
| Git, gh, lazygit, delta | `modules/home/programs/dev/git.nix` |
| nix-index and comma | `modules/home/programs/dev/nix-index.nix` |

## Shell and environment

- zsh has no framework. Keep imperative startup code in the existing `zshInit` binding and add aliases only after checking the existing alias set.
- `nr` switches with nh, `nc` runs nh cleanup, `lg` opens lazygit; `y` comes from yazi's shell integration. The JDK selectors are `use-java8/17/21/25/26`; one-shot `javaNN` and `javacNN` wrappers live in `modules/home/programs/dev/java.nix`.
- Interactive zsh initialization does not supply environment variables to systemd user units, desktop launchers, or compositor-spawned applications. Put nonsecret shared variables in both `systemd.user.sessionVariables` and `home.sessionVariables` in `session-vars.nix`; keep interactive-only variables on the Home Manager side.
- Secret delivery is handled separately. Never embed credential values in session variables or shell startup code; the existing export loop reads runtime files provided by sops-nix. Read [sops-secrets](../sops-secrets/SKILL.md) when changing secret delivery.
- The `JAVA*_HOME` values in `session-vars.nix`, Java wrappers, and PrismLauncher JDK choices are a coordinated set. Update all three when adding a JDK.
- Keep `use-luarocks` opt-in: exporting Lua 5.4 paths globally can contaminate Neovim's LuaJIT environment.
- Terminal UI colors use ANSI indexes so they follow Noctalia at runtime. Consult [desktop-apps](../desktop-apps/SKILL.md) before adding fixed theme colors.

## Kitty and tmux

`kitty.nix` intentionally does not use `programs.kitty.settings`. Noctalia's kitty theme hook modifies `kitty.conf`, so a Home Manager store symlink there would prevent the hook from completing. Home Manager owns read-only `kitty/mayon.conf`; an activation script seeds mutable `kitty/kitty.conf` with includes for `mayon.conf` and `themes/noctalia.conf`. Noctalia owns the generated palette. Preserve this split and the activation repair for a missing include.

The default `TERM=xterm-kitty` supports remote sessions because `kitten ssh` can provide kitty terminfo. Avoid changing it without checking graphics and remote-terminal behavior.

In tmux, `allow-passthrough on` is needed for yazi's terminal image previews. Keep the `Tc`, `Smulx`, and `Setulc` terminal overrides for true color and undercurl. When investigating a blank image preview or degraded diagnostic underline, check these settings and the terminal outside tmux.

## Yazi, Git, and verification

- Yazi previewers depend on their commands in `extraPackages`. A plugin generally needs a package entry, any required `initLua` setup, and a key binding; inspect all relevant sections before changing one.
- Git's configured identity and aliases are in `git.nix`. `programs.gh` manages its config, while authentication remains in gh's user data; avoid replacing authentication state when adjusting CLI preferences.
- Delta integration is enabled through Home Manager's Git integration. The nix-index database module supplies prebuilt lookup data and comma; do not rebuild that database as a routine fix. The system's command-not-found handler is disabled so the nix-index hook takes precedence.
- After editing, run `nix fmt` and evaluate/build the affected flake configuration when appropriate. For a runtime issue, inspect the generated Home Manager configuration and test from the process type that exhibited it (interactive shell, launcher, or systemd unit).
