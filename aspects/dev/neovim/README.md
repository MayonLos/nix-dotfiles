# Neovim

This feature installs a Nix-built Neovim 0.12.6 workspace. Den supplies the appearance and validated `editorLanguages` contributions. Plugins, parsers and executables are pinned; nothing is downloaded by the editor. Home Manager follows the NixOS rebuild and has no separate switch.

`default.nix` is the registration entry; `package.nix` is the public factory taking `pkgs`, `palette`, `contributions`, optional `acpAdapters`, and optional `nixOptions = { flake; host; }`. It returns `normal`, `dev`, and `configDir`. `checks.nix` is the public test hook. `config/`, `plugins.nix` and `parsers.nix` are private. Standalone flake outputs use the same factory through `nix/outputs.nix`. The sole unstable package set remains in `nix/pkgs.nix`: its explicit exceptions provide Neovim 0.12.6 and CodeCompanion 19.27. Stable plugins share the stable LuaJIT package environment; the upstream editor derivation is preserved.

## Workspace

The One Dark surface uses a single quiet editor canvas with small, consistent floating-window borders. The top row combines project and branch selection with rounded, clickable file tabs; file-type icons remain colored, and modified files receive a small orange marker. Overflow tabs collapse into a clickable `+N`; error, modified and read-only states use small dots. Tool buffers never become file tabs. There are no sidebars on startup. `Space e` or Alt-1 opens the 34-column Project tree with a visible filter and no preview. General pickers stay centered. Files, buffers, recent files, All and action selections start compact without preview; grep, LSP locations/symbols, diagnostics and Git pickers show a right-hand preview. Alt-p toggles it. Below 120 columns or 28 rows the preview hides automatically and returns when space permits. Dropbar shows a muted, clickable path/file/symbol breadcrumb with sibling menus.

Tool windows open only when requested: Project, Neogit Commit, Aerial Structure, Trouble Problems, terminal, history and AI. Alt-2 opens Commit, Alt-7 opens Structure, and Alt-F12 opens the bottom terminal. Aerial owns Structure; Neogit and CodeDiff own Git workflows; Trouble owns Problems. Tasks use the bottom terminal and remember the last selected recipe.

Inactive document windows use a 6% darkened background; the cursor line belongs to the active window. Fixed sign slots combine gitsigns' colored `▎` with small severity marks, without a fold column. The statusline uses a small mode-colored dot and muted mode name, followed by the relative document path and Git changes. Separate warning/error counters, LSP progress, the AI completion provider and line:column sit at the right. Git uses green `+N`, yellow `~N` and red `-N`; recording shows `● REC @q`. Search counts stay in the statusline as `[3/14]`. Mode colors use blue/green/purple/red/yellow for Normal/Insert/Visual/Replace/Command.

Color literals use small virtual squares through nvim-highlight-colors; named colors are disabled. Tiny-inline-diagnostic shows one muted yellow, italic `▲ message` at the cursor without a background or brackets; long messages stay on one line. Other locations retain muted underlines. Folding prefers LSP when supported, otherwise Tree-sitter, starts expanded, and displays a highlighted `… N lines` summary. Tiny-glimmer provides short local edit feedback. Scope guides stay static and faint. Smooth scrolling respects `reducedMotion`; macros/recording and bigfile guards suppress expensive effects. Files over 1MB or with very long average lines use the bigfile path.

The dashboard renders recent files with colored icons on its first frame; it discovers the project list just after that frame. Project/session actions use a compact action grid. Project sessions save ordinary file layout and restore from an empty startup; Explorer, AI, terminals and tool buffers are filtered before saving. User histories and unsaved work remain protected. Wayland uses wl-copy/wl-paste; SSH selects OSC 52. Markdown, gitcommit and TeX enable `spelllang=en,cjk`.

Visual selections use blue mixed into the editor background at 14%, with bright text; tests check text contrast. Current search matches use orange with dark text, while other matches stay understated. Pairing brackets are bold and underlined without a filled block; symbol references use faint underlines. Normal/Insert/Replace cursors use block/beam/underline shapes with mode colors. Floating windows have rounded edge borders, centered muted titles and one-cell visual padding; padding geometry is included in sizing. Native completion is borderless with blue kind icons, muted details and a rounded documentation pane. Notifications, hover/signature, input, picker frames, which-key, AI floats and Lazygit share the same subdued One Dark border and deep background; titles remain muted when AI loads. Notifications keep at most three compact upper-right cards for three seconds, including notices excluded from history.

## Keys

Leader is Space; localleader is comma. `Space ?` opens the global which-key view. Existing native Vim navigation remains available.

| Keys | Action |
|---|---|
| `Space Space`, Tab / Shift-Tab | Multi-source picker: All / Files / Symbols / Actions / Text |
| `Space e`, Alt-1 | Project |
| Alt-2, `:Neogit` | Commit |
| Alt-7, `Space co` | Aerial Structure |
| Alt-F12, `Space th` | Bottom terminal |
| `Space tt`, `Space tv` | Floating / vertical terminal |
| `Space ;` | Dropbar keyboard selection |
| `Space pp`, `Space ,`, `Space /` | Projects / buffers / text search |
| `Space rt`, `Space rr`, `Space rs` | Select task / run last task / explicit serial terminal |
| `Space ff`, `Space ss`, `Space sS` | Files / document symbols / workspace symbols |
| `Space sn`, `Space sd`, `Space sk` | Notification history / diagnostics picker / keymaps |
| Alt-p (picker) | Toggle preview; narrow layouts temporarily hide it |
| `Space gg`, `Space gd` | Lazygit / CodeDiff |
| `Space gb` | Toggle current-line Git blame (off by default) |
| `Space xx`, `Space xq`, `Space xl` | Problems / quickfix / location list |
| `Space ca`, `Space cr`, `Space cf` | LSP action / rename / format |
| `gd`, `gi`, `grr`, `K`, `gK` | Definition / implementation / references picker / hover / signature |
| `[d`, `]d`, `Space ch` | Previous/next diagnostic / C/C++ header-source switch |
| `Space dc`, `Space db`, `Space dq` | Debug continue/remote attach / breakpoint / disconnect |
| `Space dn`, `Space di`, `Space do` | Debug step over / into / out |
| `Space dr`, `Space dh` | Debug REPL / value hover |
| `,ll`, `,lv`, `,lc` | TeX build / forward search / clean |
| `:TexlabToggleBuildOnSave` | Optional build on save |
| `Space uz`, `Space uh` | Zen / inlay hints |
| `Space ps`, `Space pl`, `Space pd` | Project session / last session / disable saving |
| Ctrl-h/j/k/l; Alt-h/j/k/l | Move / resize splits, integrated with tmux |

The `f/s/c/g/r/d/a/x` groups consistently mean Files/Search/Code/Git/Run/Debug/AI/Lists. A rounded bottom which-key card exposes their descriptions; `Space ?` opens it immediately. Git hunk and AI completion cycling each have one mapping owner.

Tasks discover justfile recipes, Make targets, package.json scripts and flake apps. Task execution is explicit, opens a bottom terminal and remembers the last selection. Commands are rediscovered and validated before execution.

## Languages

| Language | LSP | Formatting / reading |
|---|---|---|
| Lua | lua_ls + lazydev | Stylua; project `.luarc.json`/`.luarc.jsonc` settings take precedence; `vim` and Snacks types are scoped to the Neovim config |
| Python | basedpyright (standard) + Ruff | Ruff diagnostics/import actions, ruff_format; no duplicate nvim-lint Ruff |
| C/C++/CUDA | clangd | clang-format; background index, clang-tidy, detailed completion, no header insertion/placeholders |
| Nix | nixd | nixfmt; this host's NixOS/HM options only inside the configured flake |
| TeX/BibTeX | texlab | latexindent; Tree-sitter; build and Zathura SyncTeX |
| Markdown | marksman | Tree-sitter injections, render-markdown, formula preview |
| TS/JS, HTML/CSS, JSON, YAML | contributed language servers | Packaged parsers and formatter contributions |
| TOML, Bash, Java, MATLAB | taplo, bashls, jdtls, matlab_ls | Existing language contributions remain enabled |
| Rust / Go | rust-analyzer / gopls only when present in PATH | Parsers always available; use the project's devshell/direnv for LSP |

All packaged parser/query directories are on runtimepath before a file is opened; this does not execute the optional plugin scripts. LaTeX highlighting is enabled. Mermaid image conversion is deliberately disabled, so no mmdc/Chromium dependency is installed. The pinned Snacks health check is patched to report that disabled capability accurately. Zathura receives the current Neovim server socket for inverse search; no global editor daemon or user-session window is launched by configuration setup.

C/C++ projects own `compile_commands.json` (normally at the root or `build/`; use a project `.clangd` `CompileFlags.CompilationDatabase` for other locations). clangd keeps the database's `--target`, `--sysroot` and include flags. The editor adds a constrained `--query-driver` allowlist for available `arm-none-eabi-gcc/g++` PATH aliases and their real paths, plus `~/.local/share/mp157-sdk/sysroots/*/usr/bin/arm-ostl-linux*/arm-ostl-linux*-gcc/g++` when that SDK exists. It neither installs nor rewrites an SDK. Launch Neovim from the SDK/devshell environment when the compiler needs its environment.

`Space dc` lazily loads nvim-dap and asks for a local firmware ELF and `host:port` (default `localhost:3333`). It uses host `gdb --interpreter=dap`, because the packaged ARM GDB lacks Python/DAP; the host must provide GDB with DAP support and the target architecture. Start OpenOCD or gdbserver separately. Cancelled prompts or invalid target ports abort; no target connection starts during editor setup. `Space rs` asks for an existing `/dev/tty*` or `/dev/serial/by-id/*` character device and baud rate, then runs `tio` as argv in a bottom terminal. It never guesses or opens a device automatically. GDB/tio are supplied by the embedded environment rather than duplicated in the editor package.

OpenComputers Lua projects can copy the optional [LuaLS template](templates/opencomputers.luarc.json) into their own root as `.luarc.json`; it declares only OpenComputers runtime globals. The template is documented in [the templates guide](templates/README.md). No project file is installed or edited by this feature. In CodeCompanion, a visible `AGENTS.md` rule reference is rendered as the muted `已加载规则：AGENTS.md` label; the rule context and metadata remain intact for the request pipeline.

## AI and Git

Claude Code uses claudecode.nvim's native IDE protocol and diff splits. Sidekick manages Codex/Grok CLI sessions. CodeCompanion uses `,r` to regenerate a chat reply and DeepSeek HTTP chat by default and optional ACP adapters for Codex/Claude. Provider tabs, model/connection state, chat roles, code blocks, tools and diff highlights share the workspace palette. CLI terminal contents remain owned by the CLI; the container and native review actions are styled without fabricating messages or authentication.

Copilot inline completion uses Tab to accept and Alt-]/Alt-[ to cycle. `Space au` (also `Space ua`) cycles Copilot → DeepSeek Minuet → off. Switching away from Copilot now also disables its LSP client; lazy setup respects an already-selected off state. Inlay hints start disabled. DeepSeek reads `DEEPSEEK_API_KEY`; missing keys/CLI binaries give a concise Chinese message. Copilot signs in with `:LspCopilotSignIn`. ACP paths come from ai-workbench's `NVIM_CODEX_ACP`/`NVIM_CLAUDE_ACP` or explicit standalone store paths. No runtime npx fallback is used. Offline checks verify commands, selections, accept/reject protocols and missing-credential behavior; they do not submit model requests.

| AI keys | Action |
|---|---|
| `Space ac`, `Space as` | Claude panel / send selection |
| `Space ax`, `Space af`, `Space av` | Codex CLI / send file / send selection |
| `Space ad`, `Space ai`, `Space ap`, `Space ah` | DeepSeek chat / inline edit / prompt actions / history |
| `Space au` or `Space ua`; `:AICompletion off` | Cycle completion provider / turn it off |
| Tab, Alt-]/Alt-[ | Accept inline suggestion / next or previous suggestion |
| `,a`, `,r` in Claude diff; `Space aA`, `Space aD` | Accept / reject the proposed file change |
| Ctrl-S, `,r` in CodeCompanion chat | Send / regenerate (buffer-local, separate from Claude diff) |

Review AI changes before accepting: Claude opens its native diff; CodeCompanion inline edits use Mini.diff accept/reject; `Space gd` opens CodeDiff for a project-wide review. Opening a panel does not automatically submit a prompt. Offline fixtures test acceptance, rejection, snippet insertion and stale completion callbacks; live authentication, model behavior and network failure remain separate checks.

Gitsigns owns gutter signs and hunk actions. Mini.diff is reserved for CodeCompanion inline review and draws no gutter signs. CodeDiff handles review/history/conflicts, with packaged native diff support and no online installation. Temporary Git regression repositories use plumbing commands, preserving the checkout's index and history. Neogit provides native staging/commit/push commands when invoked by the user; verification does not invoke those actions.

## Terminal, ownership and checks

Kitty uses four-pixel padding with top-left placement, 108% cell height and Maple Mono NF CN `calt`/`cv01`/dotted-zero features. CJK remains on a two-cell grid; terminal spacing is owned by Kitty, not Neovim `linespace`. Neovim queries the terminal background and synchronizes OSC 11 with Normal on TUI entry and ColorScheme; exit/suspend restores the original background (OSC 111 fallback), and resume reapplies it. Tmux uses escaped DCS passthrough, clipboard and focus events. Headless runs emit no terminal escapes. The wrapper defaults `NVIM_NOTTYFAST=1` to skip the redundant early blocking 0.12 OSC 11/DSR probe; the asynchronous lifecycle remains editor-owned. Kitty's native scrollback pager remains suitable for ANSI terminal output; it is not a second full editor workspace.

Nix builds a palette-specific LuaJIT highlight cache and merges all packaged parser/query resources into one script-free startup runtime directory. lz.n defers new plugins, including DAP. Its one-shot heterogeneous spec registration runs with JIT temporarily paused and restores the previous JIT state; editing keeps JIT enabled. First-frame dashboard work stays small. Feature checks cover startup/parser visibility, workspace lifecycle, file safety, actual LSP samples, Lua diagnostics, native completion, sessions/tasks, AI protocols, CodeDiff asynchronous buffer loading, auxiliary surfaces and OSC restoration. The pinned Snacks LSP finder has a small [coroutine-delivery patch](patches/snacks-lsp-coroutine.patch): main-loop LSP handlers convert responses, then the finder coroutine delivers items. This prevents a mixed-source picker from yielding through Neovim’s callback boundary; keyed request cancellation and late replies are covered by `tests/picker_lsp.lua`. Patch application and runtime regression are build checks; re-evaluate it on a Snacks upgrade. Runtime screenshots and timing evidence are recorded in [round 28](../../../docs/history/nvim-r28-2026-10-25.md), with the [round 25 baseline](../../../docs/history/nvim-minimal-2026-10-25.md) retained separately. Measurements are not hardware activation evidence.

Removing the feature removes its package and managed `nvim/init.lua` link after activation. Projects, histories, login state, CodeCompanion sessions and files outside the managed link are preserved. This task builds outputs and does not activate them.
