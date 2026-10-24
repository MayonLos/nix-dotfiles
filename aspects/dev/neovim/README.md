# Neovim

This feature installs the repository's Neovim build and generates its runtime data from an explicit palette and validated `editorLanguages` contributions. Language contributions are consumed only when this editor aspect is selected.

`package.nix` is the public parameterized package factory. Callers provide `pkgs`, `palette`, and `contributions`; the factory returns `normal`, `dev`, and `configDir`. `pkgs.unstable.codecompanion-nvim` supplies CodeCompanion 19.27.0 while its Plenary runtime dependency remains stable. Optional `acpAdapters` supplies absolute paths for `codex-acp` and `claude-agent-acp`. The factory does not accept a separate unstable package-set argument.

`default.nix` is the public registration entry. `checks.nix` is the public feature test hook, with the explicit inputs declared by its function. `config/` is private and may be used only by this feature's package and checks; `plugins.nix` and `parsers.nix` are also private. The thin standalone flake outputs and their ACP paths are assembled in `nix/outputs.nix`; feature checks are registered through `nix/checks.nix`.

Nix fixes plugin and tool versions, Den supplies language contributions and the palette, and lz.n manages loading. Plugins are not downloaded at runtime. Copilot credentials are managed by `:LspCopilotSignIn`; DeepSeek reads only `DEEPSEEK_API_KEY` from the environment. ACP adapters use the public `NVIM_CODEX_ACP` and `NVIM_CLAUDE_ACP` session variables supplied by ai-workbench for Home Manager sessions, and absolute store paths for the standalone package. Missing paths produce an error; Neovim does not use npx or download a fallback.

Claude Code uses claudecode.nvim for its IDE protocol and terminal. Sidekick manages Codex/Grok TUI sessions and NES; CodeCompanion provides DeepSeek HTTP chat/inline editing and optional Codex/Claude ACP. Copilot is the primary inline completion source, with manually selected Minuet DeepSeek FIM as fallback. AI suggestions remain separate from the native LSP completion menu. Git review uses stable codediff 2.45.0 and its packaged `libvscode_diff.so`; online installation is disabled. CodeCompanion 19.27's inline review compatibility helper is covered by feature checks.

The feature checks run in isolated HOME/XDG directories. They cover file safety, LSP and UI behavior, AI loading, ACP executable paths, completion switching, MiniDiff review, Claude protocol accept/reject, codediff and native Neovim features, and key mappings. Model requests, real tmux navigation, narrow-screen appearance, GUI input, and actual IME behavior require runtime verification.

The Snacks explorer owns a single 30-column left sidebar. A muted uppercase winbar names its
Git root (or cwd) once; there is no repeated root row or tree connector. Blue disclosure
arrows and folder icons accompany indented foreground text. The selected row uses selection
and a blue rail; Git letters align right, diagnostics do not occupy filename space, and
truncated filenames retain their extension. `i` opens project-scoped search in the shared
centered picker while navigation remains in its sidebar. Edgy owns only
AI, diagnostics, quickfix, and terminal panels. Explorer styles persist across layout changes.

Editing and dashboard surfaces use `bg`; the sidebar, tabline, statusline and popups use `deep`.
Active tabs use the editor background and a blue underline attribute, with an orange unsaved
marker. Terminal cells cannot draw the preview's pixel-height top border; no floating overline
character is inserted. Tab close buttons, file counts and devicons are omitted. Absolute line
numbers keep source references stable; `<leader>un` can still toggle relative numbering.
Folding remains available through `zc`/`zo`, without fold-column arrows. Inlay hints start off
and toggle with `<leader>uh`. Satellite's right rail and automatic sticky context are disabled.

The dashboard has a one-line `mayon.nvim` identity and project/branch context, a palette rule,
eight actions in a two-column grid, recent files and projects, and a bottom runtime footer.
Keys `h`/`l` select a grid column, `j`/`k` move between actionable rows, and Enter activates the
selected cell. Single-letter action keys work directly; `q` appears only in the bottom hint.
Keycaps use surface/muted, selection uses a blue left rail, and CJK labels have no inserted
spacing. Missing file icons are blank rather than type-name fallbacks. Histories come from
Neovim/Snacks; isolated validation seeds only temporary histories and does not read user state.
The plugin count is the packaged plugin/parser closure, and the timer is config initialization,
not first frame or process wall time. The Copilot footer identifies the configured executable;
it does not claim a signed-in network session.

The statusline shows mode on selection, a purple branch, colored Git counts, the basename,
diagnostics, one primary language server (excluding Copilot), `AI · Copilot`/`AI · DeepSeek`,
and a surface position block. Active native progress and CodeCompanion requests remain
visible. Modified/readonly safety states use compact `[+]`/`RO` labels. Dashboard status is
only `NORMAL  dashboard` and `q 退出`. Native completion uses purple kind icons and muted
type metadata; floats, pickers, which-key and AI panels share deep surfaces and a thin edge
color derived from the palette border.
Claude Code's terminal title is supplied through the pinned plugin's `snacks_win_opts.title`, and Edgy styles its panel title area with palette colors. Review uses the plugin's native vertical diff split, a custom accept/reject winbar, and palette-based `DiffAdd`/`DiffDelete` highlights. The pinned plugin exposes a diff split rather than a separate card layout, so a boxed diff card with inline action buttons is not represented in Neovim's TUI.

Removing the aspect removes the package and managed `nvim/init.lua` link after activation. It preserves user projects, editor histories, plugin state, CodeCompanion history, and files outside the managed link; no project files or user data are rewritten.

Theme data comes from `generated.palette`: editing uses bg/brightFg, floats and native menus use deep,
selection uses selection, and pending AI text uses muted italic. The immutable package compiles the pinned
One Dark adapter into a LuaJIT highlight cache at build time; development overrides use the live adapter.
LSP starts on the first FileType; explorer safety hooks are installed by its source configuration before actions.
The dashboard draws its small native statusline on the first frame; Heirline starts
on the next scheduled turn or synchronously at a document's FileType. URL parsing
and sessions load at their first relevant entry point.
The file icon table waits for the first file; Snacks scroll/input/scope/picker setup runs at the
existing scheduled VeryLazy event after the first frame. Dashboard rendering stays synchronous.

The panel adapter keeps Snacks files/grep/symbols/buffers/recent/help/keymaps/diagnostics
on one centered layout. Grep uses real file-header rows (Enter opens the first match),
not virtual rows that would invalidate native list scrolling. Each rg run is collected
before grouping; cancellation and requests remain Snacks' native asynchronous workflow.
Explorer search uses that same layout and preserves the navigation sidebar. Notifications use a native custom renderer at the
upper right, with a severity rail and no large icon. LSP and native completion docs
share the float style; completion selection and resolution remain Neovim-owned.

Trouble and native quickfix/location lists use bottom panels with error/warning counts,
file groups and positions aligned right. Which-key uses a borderless bottom strip with
four columns at the 200-column validation size. AI panels occupy about 38% of a wide
editor; provider/model/status headers, chat role/tool/code decoration and native send
hints share the palette. A loaded HTTP adapter is ready, not proof of network authentication.
Claude/Sidekick terminal content remains CLI-owned; only the Neovim container is styled.
Snacks lazygit auto-theming is disabled so the CLI feature retains color ownership.
Edgy leaves ordinary floating terminals and lazygit in their bordered floating layout.
Claude review colors apply only while the window is in diff mode; `:diffoff` restores
the original window highlights, including when the review buffer remains open.
Oil, grug-far, help, health and native ui2 buffers receive window-local deep surfaces.
The visual checks use isolated local fixtures and never submit model requests.
