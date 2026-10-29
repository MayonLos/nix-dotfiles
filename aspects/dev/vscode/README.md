# Visual Studio Code

Installs the FHS VS Code package, One Dark Pro (`zhuangtongfa.material-theme`)
3.19.0 and the Nix grammar (`bbenoist.nix`) through the locked nixpkgs instance.
The FHS variant supplies libraries used by extension-provided binaries, rather
than maintaining a partial `LD_LIBRARY_PATH` wrapper. Native editor runtime
support is selected through `editing-runtime-host`.

## Appearance and settings ownership

The selected user's `appearance` is required. `settings.nix` derives workbench
colors, token overrides and editor/terminal fonts from that shared palette:
One Dark Pro syntax, Maple Mono NF CN at 15 px, deep editor/terminal surfaces,
neutral status bar (orange only while debugging), a blue active tab top border,
and thin sidebar/panel borders. Minimap, welcome editor and extension
recommendation notifications default to off. The activity bar stays on the
left; the secondary sidebar defaults to hidden. Existing view visibility state
still wins. Completion, diff and the terminal use native VS Code components.

VS Code 1.119 has no supported workbench font-family setting. The interface
keeps its native Linux `system-ui, Ubuntu, "Droid Sans", sans-serif` stack;
Inter is therefore not forced with a CSS-injection extension. Editor and
terminal fonts are configured through their supported settings. Theme roles
use the [official color API](https://code.visualstudio.com/api/references/theme-color).

Home Manager **does not own or symlink `Code/User/settings.json`**. Its
`seedVscodeSettings` activation runs `seed-settings.py` after the write boundary:

- Only missing top-level defaults are inserted. Within existing
  `workbench.colorCustomizations` / `editor.tokenColorCustomizations` objects,
  only missing direct children are inserted. Existing values, theme-scoped
  overrides, custom rules and all unrelated keys win.
- JSONC comments, trailing commas, existing text, UTF-8 BOM and CRLF are
  preserved. Empty/comment-only files are supported. Invalid JSONC and
  duplicate keys fail conservatively without replacing the original.
- Symlinks in the target or any parent are refused. Existing modes are kept;
  a new file is `0600`. A profile with a live `code.lock` PID, an unreadable or
  malformed lock, or any `SingletonLock` is skipped. A dead `code.lock` PID does
  not block a later activation. No locks are deleted. Contents and locks are
  checked again immediately before atomic replacement.
- These are seed defaults, not enforced settings. User changes remain after
  subsequent rebuilds, including a different theme/font or an enabled minimap.
  When Code is open during activation, close it before the next activation to
  receive missing defaults. Existing explicit settings may require the user to
  opt into these defaults; they are never silently reset.

The feature still contributes the `vscode` Noctalia community integration.
The inspected community template renders **only**
`~/.vscode/extensions/noctalia.noctaliatheme-0.0.5/themes/NoctaliaTheme-color-theme.json`
(and separate VSCodium/Antigravity equivalents), with no settings writer,
post-hook or undo-hook. Noctalia owns that extension's theme JSON; the seed owns
only missing user-setting keys; Nix owns the installed One Dark Pro/Nix extension
links. Selecting One Dark Pro leaves NoctaliaTheme unused. Thus no two writers
own the same file. The community template is downloaded/cached at runtime and
is not pinned by `flake.lock`; its target/hook behavior must be rechecked if that
upstream integration changes. Do not add HM `profiles.default.userSettings` or
turn this into an overwrite of the user profile.

## Checks and removal

`default.nix` is the feature entry. `checks.nix` is the public explicit check hook
for the central registry; the remaining Nix/Python files are private. The
`vscode-settings` check verifies the HM ownership boundary, Nix theme installation,
palette/settings invariants, and JSONC preservation, idempotence, locks and
symlink fixtures. The central check registry must explicitly include this hook;
it is not discovered automatically.

Removing the aspect withdraws the package, Nix extension links, Noctalia
contribution and runtime selection when unused elsewhere. Seeded settings,
user-installed extensions, profiles, authentication, workspace state, history,
Noctalia's old theme output and project files are preserved. Reverting seed
values is a user action, not automatic cleanup.

The r41 B verification used a private HOME/XDG/D-Bus and headless sway at
2560×1600, scale 1.5, with three screenshot/review rounds. Fresh profiles verify
the defaults; they do not prove the existing user profile selected the same
settings. Main-host activation and Noctalia apply/undo remain integration checks.
