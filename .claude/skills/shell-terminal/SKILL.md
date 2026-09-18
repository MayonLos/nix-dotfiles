---
name: shell-terminal
description: The interactive shell stack on this host — zsh (no framework), starship, zoxide, foot, tmux, yazi, git/delta/gh and the nix-index+comma pair. Use when adding an alias, a shell function or an environment variable, when deciding between zsh.nix and session-vars.nix for something, when a variable is set in a terminal but empty in a systemd unit or a launcher, when touching foot/tmux/yazi config, when the terminal's colours do not follow the noctalia theme, or when image preview or true colour breaks inside tmux.
---

# Shell and terminal

| Concern | File |
|---|---|
| zsh, starship, zoxide | `modules/home/shell/zsh.nix` |
| env vars, PATH, JAVA*_HOME | `modules/home/base/session-vars.nix` |
| terminal emulator | `modules/home/programs/terminal/foot.nix` |
| multiplexer | `modules/home/programs/terminal/tmux.nix` |
| file manager (TUI) | `modules/home/programs/apps/yazi.nix` |
| git, delta, gh | `modules/home/programs/dev/git.nix` |
| `nix-locate` / `,` | `modules/home/programs/dev/nix-index.nix` |

## zsh has no framework, on purpose

Home Manager built-ins only: `autosuggestion`, `syntaxHighlighting`,
`enableCompletion`, plus `zsh-fzf-tab` as the single plugin. No oh-my-zsh, no
prezto. Prompt is starship, `cd` is zoxide, ↑/↓ is the built-in
`up-line-or-beginning-search` (prefix search, not plain history).

Everything imperative lives in one `let zshInit = ''…''` binding so the module
body stays a single `programs = { … }` attrset. Add to that string rather than
introducing a second `initContent` path.

Aliases worth knowing before adding a duplicate: `nr` (`nh os switch`), `nc`
(`nh clean all`), `lg` (lazygit), `y` (yazi's own wrapper, from
`shellWrapperName`), `ls`/`ll`/`la`/`lt` → eza, `cat` → bat.

### Shell functions that exist

- `use-java8/17/21/25/26` — swap `JAVA_HOME` and rewrite `path`, removing the
  other JDK bin dirs. They read `JAVA*_HOME`, which `session-vars.nix` sets; the
  `java8`…`java26` wrapper binaries in `dev/java.nix` are the other, one-shot
  way to reach a specific JDK.
- `use-luarocks` — sets `LUA_PATH`/`LUA_CPATH` from `luarocks path`. Deliberately
  on demand: neovim honours those variables too, and its LuaJIT must not pick up
  Lua 5.4 rocks.

## zsh.nix vs session-vars.nix

The zsh init only reaches processes started from an **interactive shell**.
Systemd user units, `.desktop` entries and anything the compositor spawns
inherit the systemd user environment instead.

`session-vars.nix` therefore exports one shared set through **both**
`systemd.user.sessionVariables` and `home.sessionVariables`
(`NIXOS_OZONE_WL`, `_JAVA_AWT_WM_NONREPARENTING`, the `JAVA*_HOME` set), and adds
the interactive-only extras (`XMODIFIERS`, `EDITOR`/`VISUAL` = nvim,
`BAT_THEME`) to the `home` side only.

If a variable must be visible to a launcher-started app, it belongs in the
shared set — not in the zsh init. Secrets are the special case: never in either
file, see the `sops-secrets` skill (the export loop at the top of `zshInit` is
the interactive half of that story).

`Xft.dpi` is **not** here — it is an X resource, delivered by
`modules/home/base/xresources.nix`; see the `desktop-mango` skill.

The system half of zsh is `modules/system/programs/zsh.nix`: it enables the
shell system-wide and sets `programs.command-not-found.enable = false` so
nix-index's hook is the one that answers an unknown command.

## foot follows the noctalia palette by `include`

foot.ini is a read-only HM symlink that `include`s
`$XDG_CONFIG_HOME/foot/themes/noctalia`, which noctalia's template rewrites on
every theme change.

Declaring the `include` in the module (rather than letting noctalia's `apply.sh`
sed it into foot.ini) is what keeps foot.ini declarative: apply.sh greps for the
include, finds it, and skips its own rewrite. **foot refuses to start when an
`include` target is missing**, so an activation script seeds an empty file when
noctalia has not rendered one yet. That seeded file is mutable and unmanaged —
do not convert it to `home.file`.

`term` is set to `xterm-256color` rather than `foot`. Keep it that way unless you
have a reason: remote hosts and older tools that do not ship foot's terminfo
entry fall back badly, and tmux already sets its own `tmux-256color` inside.

## tmux

Prefix `C-a`, vi keys, `baseIndex = 1`, `detach-on-destroy off`. resurrect +
continuum restore sessions automatically (10-minute save interval, pane contents
captured, nvim sessions restored).

Two settings in `extraConfig` are load-bearing and easy to delete by accident:

- `allow-passthrough on` — sixel/kitty graphics passthrough. Without it yazi's
  image preview is blank inside tmux.
- the `Tc` / `Smulx` / `Setulc` `terminal-overrides` — true colour and undercurl.
  Diagnostics underlines in nvim degrade to a flat colour without them.

## yazi

`programs.yazi` with `enableZshIntegration` (`y` changes the shell's directory on
exit). Previewers are wired through `prepend_previewers`: duckdb for
csv/tsv/json/parquet/arrow, glow for markdown, ouch for archives — and each needs
its binary in `extraPackages`, which is where `poppler-utils`,
`ffmpegthumbnailer`, `mediainfo` and `exiftool` come from too. `edit` opens nvim
blocking.

Plugins come from `pkgs.yaziPlugins` (`inherit` list), configured in `initLua`,
bound in `keymap.mgr.prepend_keymap`. A plugin added to one of those three places
and not the others does nothing.

## git

Identity, aliases (`lg`, `st`, `co`, `undo`), `pull.rebase`, `merge.conflictstyle
= diff3`. Diffs page through delta (side-by-side, navigate, line numbers).

`programs.gh` writes only `~/.config/gh/config.yml`; the auth token lives in
`hosts.yml`, which Home Manager does not touch — enabling or changing this module
never disturbs an existing `gh auth login`. The GitHub token that *nix* uses is a
separate thing entirely (sops → `nix.extraOptions`), see `sops-secrets`.

## nix-index

`nix-index-database` provides a weekly prebuilt index, so **never run `nix-index`
by hand** — it takes hours and the result is thrown away on the next rebuild.
`command-not-found`, `nix-locate` and `,` (comma, run a program without
installing it) all read that database.
