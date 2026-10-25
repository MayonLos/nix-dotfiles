# Neovim

This feature installs a Nix-built Neovim 0.12.6 workspace. Den supplies the appearance and validated `editorLanguages` contributions. Plugins, parsers and executables are pinned; nothing is downloaded by the editor. Home Manager follows the NixOS rebuild and has no separate switch.

`default.nix` is the registration entry; `package.nix` is the public factory taking `pkgs`, `palette`, `contributions`, optional `acpAdapters`, and optional `nixOptions = { flake; host; }`. It returns `normal`, `dev`, and `configDir`. `checks.nix` is the public test hook. `config/`, `plugins.nix` and `parsers.nix` are private. Standalone flake outputs use the same factory through `nix/outputs.nix`. The sole unstable package set remains in `nix/pkgs.nix`: its explicit exceptions provide Neovim 0.12.6 and CodeCompanion 19.27. Stable plugins share the stable LuaJIT package environment; the upstream editor derivation is preserved.

## Workspace

The One Dark palette separates `bg` islands from a derived frame (`deep × 0.36`, currently `#090a0c`). Frame/bg contrast is approximately 1.30:1; this is a decorative seam, not a text contrast target. Floating windows use `deep`, a muted edge and rounded borders. Native ui2 command/message windows retain their layout rather than receiving a second winbar.

The top toolbar contains project switching, branch selection and ahead/behind counts, Search Everywhere, the last Run task, AI and settings. Native one-line splits hold colored file tabs inside the editor, including close buttons and orange modified indicators. Dropbar supplies clickable path/file/symbol breadcrumbs and sibling menus. Left/right three-column tool rails open Project, Commit, Structure, Bookmarks, Terminal, Problems, History, AI and notifications. The Project tree keeps two-column indentation, colored file icons and extension-preserving middle truncation only when needed. Aerial owns Structure; Neogit and CodeDiff own Git workflows; Trouble owns Problems. Bottom terminal tasks use Snacks/Edgy.

Mini.map opens on wide workspaces (at least 160 columns) and can be toggled. Side islands collapse below 140 columns. Inactive document windows are subtly darker; the cursor line belongs to the active window. Fixed sign slots combine gitsigns' colored `▎` with small severity marks, without a fold column. The statusline shows the document path, diagnostics, LSP, AI completion provider, position, line endings, encoding, indentation, branch and notifications. Search counts stay in the statusline. Mode colors use blue/green/purple/red/yellow for Normal/Insert/Visual/Replace/Command.

Color literals use small virtual squares through nvim-highlight-colors; named colors are disabled. Tiny-inline-diagnostic shows the complete message on the cursor line with a low-contrast capsule. Other lines retain underlines. Folding prefers LSP when supported, otherwise Tree-sitter, starts expanded, and displays a highlighted `… N lines` summary. Tiny-glimmer provides short local edit feedback. Scrolling and scope animations respect `reducedMotion`; macros/recording and bigfile guards suppress expensive effects. Files over 1MB or with very long average lines use the bigfile path.

The dashboard renders recent files with colored icons on its first frame; it discovers the project list just after that frame. Project/session actions use a compact action grid. Project sessions save ordinary file layout and restore from an empty startup; Explorer, AI, terminals and tool buffers are filtered before saving. User histories and unsaved work remain protected. Wayland uses wl-copy/wl-paste; SSH selects OSC 52. Markdown, gitcommit and TeX enable `spelllang=en,cjk`.

## Keys

Leader is Space; localleader is comma. `Space ?` opens the global which-key view. Existing native Vim navigation remains available.

| Keys | Action |
|---|---|
| `Space Space`, Tab / Shift-Tab | Search Everywhere: All / Files / Symbols / Actions / Text |
| `Space e`, Alt-1 | Project |
| Alt-2, `:Neogit` | Commit |
| Alt-7, `Space co` | Aerial Structure |
| Alt-F12, `Space th` | Bottom terminal |
| `Space tt`, `Space tv` | Floating / vertical terminal |
| `Space ;` | Dropbar keyboard selection |
| `Space pp`, `Space ,`, `Space /` | Projects / buffers / text search |
| `Space rt`, `Space rr` | Select task / run last task |
| `Space gg`, `Space gd` | Lazygit / CodeDiff |
| `Space gb` | Toggle current-line Git blame (off by default) |
| `Space xx`, `Space xq`, `Space xl` | Problems / quickfix / location list |
| `Space ca`, `Space cr`, `Space cf` | LSP action / rename / format |
| `Space ch` | C/C++ header-source switch |
| `,ll`, `,lv`, `,lc` | TeX build / forward search / clean |
| `:TexlabToggleBuildOnSave` | Optional build on save |
| `Space uz`, `Space um`, `Space uh` | Zen / mini.map / inlay hints |
| `Space ps`, `Space pl`, `Space pd` | Project session / last session / disable saving |
| Ctrl-h/j/k/l; Alt-h/j/k/l | Move / resize splits, integrated with tmux |

Tasks discover justfile recipes, Make targets, package.json scripts and flake apps. Task execution is explicit, opens a bottom terminal and remembers the last selection. The toolbar reads a memory cache; it never evaluates the flake during redraw. Commands are rediscovered and validated before execution.

## Languages

| Language | LSP | Formatting / reading |
|---|---|---|
| Lua | lua_ls + lazydev | Stylua; runtime/plugin libraries scoped to the Neovim config |
| Python | basedpyright (standard) + Ruff | Ruff diagnostics/import actions, ruff_format; no duplicate nvim-lint Ruff |
| C/C++/CUDA | clangd | clang-format; background index, clang-tidy, detailed completion, no header insertion/placeholders |
| Nix | nixd | nixfmt; this host's NixOS/HM options only inside the configured flake |
| TeX/BibTeX | texlab | latexindent; Tree-sitter; build and Zathura SyncTeX |
| Markdown | marksman | Tree-sitter injections, render-markdown, formula preview |
| TS/JS, HTML/CSS, JSON, YAML | contributed language servers | Packaged parsers and formatter contributions |
| TOML, Bash, Java, MATLAB | taplo, bashls, jdtls, matlab_ls | Existing language contributions remain enabled |
| Rust / Go | rust-analyzer / gopls only when present in PATH | Parsers always available; use the project's devshell/direnv for LSP |

All packaged parser/query directories are on runtimepath before a file is opened; this does not execute the optional plugin scripts. LaTeX highlighting is enabled. Mermaid image conversion is deliberately disabled, so no mmdc/Chromium dependency is installed. The pinned Snacks health check is patched to report that disabled capability accurately. Zathura receives the current Neovim server socket for inverse search; no global editor daemon or user-session window is launched by configuration setup.

## AI and Git

Claude Code uses claudecode.nvim's native IDE protocol and diff splits. Sidekick manages Codex/Grok CLI sessions. CodeCompanion uses `,r` to regenerate a chat reply and DeepSeek HTTP chat by default and optional ACP adapters for Codex/Claude. Provider tabs, model/connection state, chat roles, code blocks, tools and diff highlights share the workspace palette. CLI terminal contents remain owned by the CLI; the container and native review actions are styled without fabricating messages or authentication.

Copilot inline completion uses Tab to accept and Alt-]/Alt-[ to cycle. `Space au` (also `Space ua`) cycles Copilot → DeepSeek Minuet → off. Inlay hints start disabled. DeepSeek reads `DEEPSEEK_API_KEY`; missing keys/CLI binaries give a concise Chinese message. Copilot signs in with `:LspCopilotSignIn`. ACP paths come from ai-workbench's `NVIM_CODEX_ACP`/`NVIM_CLAUDE_ACP` or explicit standalone store paths. No runtime npx fallback is used. Offline checks verify commands, selections, accept/reject protocols and missing-credential behavior; they do not submit model requests.

Gitsigns owns gutter signs and hunk actions. Mini.diff is reserved for CodeCompanion inline review and draws no gutter signs. CodeDiff handles review/history/conflicts, with packaged native diff support and no online installation. Temporary Git regression repositories use plumbing commands, preserving the checkout's index and history. Neogit provides native staging/commit/push commands when invoked by the user; verification does not invoke those actions.

## Terminal, ownership and checks

Kitty uses four-pixel padding with top-left placement. Neovim queries the terminal background and synchronizes OSC 11 with Normal on TUI entry and ColorScheme; exit/suspend restores the original background (OSC 111 fallback), and resume reapplies it. Tmux uses escaped DCS passthrough, clipboard and focus events. Headless runs emit no terminal escapes. The wrapper defaults `NVIM_NOTTYFAST=1` to skip the redundant early blocking 0.12 OSC 11/DSR probe; the asynchronous lifecycle remains editor-owned. Kitty's native scrollback pager remains suitable for ANSI terminal output; it is not a second full editor workspace.

Nix builds a palette-specific LuaJIT highlight cache and merges all packaged parser/query resources into one script-free startup runtime directory. lz.n defers new plugins; first-frame dashboard work stays small. Feature checks cover startup/parser visibility, workspace lifecycle, file safety, actual LSP samples, Lua diagnostics, native completion, sessions/tasks, AI protocols, CodeDiff asynchronous buffer loading, auxiliary surfaces and OSC restoration. Runtime screenshots, health and timing results are recorded separately in [the overhaul report](../../../docs/history/nvim-overhaul-2026-10-25.md), including limits.

Removing the feature removes its package and managed `nvim/init.lua` link after activation. Projects, histories, login state, CodeCompanion sessions and files outside the managed link are preserved. This task builds outputs and does not activate them.
