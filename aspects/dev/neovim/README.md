# Neovim

This feature installs a Nix-built Neovim 0.12.6 workspace. Den supplies the appearance and validated `editorLanguages` contributions. Plugins, parsers and executables are pinned; nothing is downloaded by the editor. Home Manager follows the NixOS rebuild and has no separate switch.

`default.nix` is the registration entry; `package.nix` is the public factory taking `pkgs`, `palette`, `contributions`, optional `acpAdapters`, and optional `nixOptions = { flake; host; }`. It returns `normal`, `dev`, and `configDir`. `checks.nix` is the public test hook. `config/`, `plugins.nix` and `parsers.nix` are private. Standalone flake outputs use the same factory through `nix/outputs.nix`. The sole unstable package set remains in `nix/pkgs.nix`: its explicit exceptions provide Neovim 0.12.6 and CodeCompanion 20.0.1. Stable plugins share the stable LuaJIT package environment; the upstream editor derivation is preserved.

## Workspace

The editor uses a quiet One Dark document workbench. A restrained top row shows the project, current document and Git branch; the current file is brightest, and the active document remains stable while a picker or tool pane has focus. There is no breadcrumb winbar. Files and text are reached through `Space Space`, `Space ff`, `Space /` and `Space ,`; `Space 1`–`9` still select document buffers. `-` or `Space fe` opens Oil in the current editing window, using the existing guarded rename/copy/trash operations. `Space e` or Alt-1 opens the optional Project tree (28 columns wide, 24 when narrow). The tree starts with its filter input hidden; press `/` to reveal its one-line filter, and Escape clears the filter and returns to the list with the input hidden.

The right-side Aerial outline opens automatically for supported source buffers when the editor area is at least 120 columns wide. It follows the cursor, marks the current symbol with a subtle background and blue rail, and closes automatically when the layout becomes narrower. `Space o` toggles the outline; a manual close is remembered for that tab until toggled open again. Plain text, terminals and dashboards suppress the outline. Tool buffers never become symbol sources; focusing the Project tree or a picker preserves the visible source document’s outline. The outline and Project tree share the available width when both are open. `Space ;` opens the document symbol picker.

General pickers use a bottom workbench at about 42% of the editor height. In wide windows, results and preview sit side by side; narrow windows stack preview below results or hide it when there is not enough room. Files, recent files and text search show a preview by default when wide; buffers, symbols and other compact sources stay list-only. Alt-p toggles the preview. The fine single-line frame, input row and selection rail use the editor background, with the frame alone defining the edge.

CodeCompanion chat opens as a focused float at both widths; its width is resolved at each open and capped at 100 columns so resizing after plugin load cannot leave a cramped chat split. Other tool windows open on request: Project, Neogit Commit, Trouble Problems, terminal, history and AI. `Space o` controls the responsive Aerial outline; Alt-F12 opens the bottom terminal. Aerial owns symbols; Neogit and CodeDiff own Git workflows; Trouble owns Problems. Tasks use the bottom terminal and remember the last selected recipe. Their contextual controls remain available when those tools are open.

Inactive documents share the editor background with muted text; only the focused window has a cursor line. Native UI2 owns commands and messages with `cmdheight=0`; it opens command input on demand. The single bottom statusline shows a compact mode marker, relative path, diagnostic counts, AI provider/activity, encoding and line:column/percentage. It uses color for meaning without mode-colored blocks. Macro recording, running debug sessions and active search counts remain visible. `Space ui` / `:EditorStatus` reports attached LSP clients, the selected AI provider and Git branch. Normal uses blue, Insert green, Visual yellow, Replace red and Command cyan.

Color literals use small virtual squares through nvim-highlight-colors; named colors are disabled. Tiny-inline-diagnostic shows one muted yellow, italic `▲ message` at the cursor without a background or brackets; long messages stay on one line. Other locations retain muted underlines. Folding prefers LSP when supported, otherwise Tree-sitter, starts expanded, and displays a highlighted `… N lines` summary. Tiny-glimmer provides short local edit feedback. Scope guides stay static and faint. Smooth scrolling respects `reducedMotion`; macros/recording and bigfile guards suppress expensive effects. Files over 1MB or with very long average lines use the bigfile path.

The dashboard is a horizontally and vertically centered 60-column block with a muted Neovim/project heading. Recent Projects, Recent Files and Actions share fixed icon, text and shortcut columns. Open (`f`), Search (`g`), New (`n`), Config (`c`) and Quit (`q`) are visible; file paths are relative and muted. The selected row uses a bounded soft background and blue left rail. Resizing preserves the selected item, including at 80 columns. Project discovery remains deferred until after the first frame. It has no logo, branch header, startup timer, plugin count or action grid. Native Snacks navigation handles j/k/Enter; project/history rows are real history, never seeded into the user's state. The `r`, `s`, `p`, `a` shortcuts remain available for recent files, session restore, projects and Claude Code. Project sessions still save ordinary file layout and restore from an empty startup; Explorer, AI, terminals and tool buffers are filtered before saving. Histories and unsaved work remain protected. Wayland uses wl-copy/wl-paste; SSH selects OSC 52. Markdown, gitcommit and TeX enable `spelllang=en,cjk`.

Visual selections use blue mixed into the editor background at 10%, with bright text; tests check text contrast. Current search matches use orange with dark text, while other matches stay understated. Pairing brackets are bold and underlined without a filled block; symbol references use faint underlines. Normal/Insert/Replace cursors use block/beam/underline shapes with mode colors. Diagnostic floats use bright foreground prose for all four severities and color only their numbered severity markers; signs, inline diagnostics and undercurls retain their existing roles. UI accents and Oil sockets use blue/cyan; code syntax and comment annotations retain One Dark semantic colors. Floating windows have single thin borders, centered muted titles and one-cell visual padding; padding geometry is included in sizing. Native completion uses a single-border menu whose background exactly matches the editor, with aligned names and types, colored kind icons, muted details, matched-text accents and a matching documentation pane. It retains native completion and LSP resolution, without blink.cmp. Notifications, hover/signature, input, which-key, AI floats and Lazygit share the same subdued One Dark border and editor background; titles remain muted when AI loads. Notifications keep at most three compact upper-right cards for three seconds, including notices excluded from history. Messages longer than three lines or 160 display cells go into native `:messages`, with a short corner notice; full content remains available without covering the document.

## Round 44 migration

| Previous interface / key | Current behavior |
|---|---|
| Round 43 hidden top row | Quiet project / current file / branch header |
| Round 43 optional Aerial Structure (`Alt-7`, `Space co`) | Automatic right outline in supported source files at 120+ columns; `Space o` toggles it and remembers manual close per tab |
| Breadcrumb toggle (`Space ub`, `:BreadcrumbsToggle`) | Removed; no document winbar |
| Centered pickers, top results shelf | Bottom picker with a right preview when wide and stacked or hidden preview when narrow; Alt-p toggles it |
| Project tree's always-visible filter | Hidden by default; `/` reveals one-line filter and Escape clears and hides it |
| Dashboard two-column action grid | Centered single column with Projects / Files / Actions; f/g/n/c/q visible, all old letter shortcuts retained |
| Idle LSP / AI names | Compact statusline shows selected AI provider/activity; `Space ui` gives details |
| Save, files, text, LSP jumps, Git and AI keys | Retained (`Space w`, `Space ff`, `Space /`, `gd`/`grr`, `Space g…`, `Space a…`) |
| Tab / Enter completion contract | Retained: Tab accepts a native menu item or AI/snippet, Enter inserts newline |

## Keys

Leader is Space; localleader is comma. `Space ?` opens the global which-key view. Existing native Vim navigation remains available.

| Keys | Action |
|---|---|
| `Space Space`, Tab / Shift-Tab | Multi-source picker: All / Files / Symbols / Actions / Text |
| `Space e`, Alt-1 | Project |
| Alt-2, `:Neogit` | Commit |
| `Space o` (Alt-7 / `Space co` aliases) | Toggle the responsive Aerial symbol outline; manual close is remembered per tab |
| Alt-F12, `Space th` | Bottom terminal |
| `Space tt`, `Space tv` | Floating / vertical terminal |
| `Space ;` | Pick document symbols |
| `/` in Project, Escape | Show the one-line filter; Escape clears the filter and hides the input |
| `-`, `Space fe` | Browse directory with Oil |
| `Space ui`, `:EditorStatus` | Show LSP / AI / Git status |
| `Space pp`, `Space ,`, `Space /` | Projects / buffers / text search |
| `Space rt`, `Space rr`, `Space rs` | Select task / run last task / explicit serial terminal |
| `Space ff`, `Space ss`, `Space sS` | Files / document symbols / workspace symbols |
| `Space sn`, `Space sd`, `Space sk` | Notification history / diagnostics picker / keymaps |
| Alt-p (picker) | Toggle preview; right when wide, stacked or hidden when narrow |
| `Space gg`, `Space gd` | Lazygit / CodeDiff |
| `Space gb` | Toggle current-line Git blame (off by default) |
| `Space xx`, `Space xq`, `Space xl` | Problems / quickfix / location list |
| `Space ca`, `Space cr`, `Space cf` | LSP action / rename / format |
| `gd`, `gi`, `grr`, `K`, `gK` | Definition / implementation / references picker / hover / signature |
| `[d`, `]d`, `Space ch` | Previous/next diagnostic / C/C++ header-source switch |
| `Space ds` | Select a launch, attach, or Java test configuration |
| `Space dc`, `Space db`, `Space dq` | Continue / toggle breakpoint / disconnect |
| `Space dn`, `Space di`, `Space do` | Debug step over / into / out |
| `Space du`, `Space dr`, `Space dh`, `Space de` | Toggle panel / open REPL / inspect value / add watch |
| `,ll`, `,lv`, `,lc` | TeX build / forward search / clean |
| `:TexlabToggleBuildOnSave` | Optional build on save |
| `Space uz`, `Space uh` | Zen / inlay hints |
| `Space ps`, `Space pl`, `Space pd` | Project session / last session / disable saving |
| Ctrl-h/j/k/l; Alt-h/j/k/l | Move / resize splits, integrated with tmux |

The top row remains intentionally restrained; search remains available through its existing keys. Which-key uses English groups for Search, Git, LSP, Debug, AI, Terminal, UI, Files, Project, Run, List, Multicursor, Code, Buffers, Quit and Notes. Its compact, horizontally centered bottom card adapts to available width, shows `+N` for the number of mappings inside a collapsed group, and derives its title from the active prefix. Normal prompts wait 200 ms; plugin prompts show immediately. `Space ?` opens the global map list. Native operator/motion hints, `g`/`z`, bracket, window, mark/register and `@` hints are enabled; undescribed mappings are hidden. Git hunk and AI completion cycling each have one mapping owner.

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

`Space rs` asks for an existing `/dev/tty*` or `/dev/serial/by-id/*` character device and baud rate, then runs `tio` as argv in a bottom terminal. It never guesses or opens a device automatically. tio is supplied by the embedded environment; the editor package pins GDB itself.

The macro prefix `@` has a dedicated dynamic hint: nonempty letter registers and `@@`; native marks/registers presets cover `'`, `"`, and `<C-r>`. The macro hint does not execute or replace a macro until a register is chosen.

## Debugging

nvim-dap is lazy-loaded on the first Debug action. The editor package injects tool paths from [debug-tools.nix](debug-tools.nix): host GDB with Python/DAP support, codelldb, Python with debugpy, the JDK and jdtls, and the Microsoft Java debug/test bundles. A checked GDB data-directory patch makes remote DAP disconnect detach without asking GDB to kill the target. This does not install or alter system SDKs. Versions and exact executable paths are exposed through the generated config metadata.

Select a configuration with `Space ds`; the list is selected by the current filetype.

| Language | Launch | Attach / test |
|---|---|---|
| C/C++ | Host GDB DAP asks for an executable or firmware ELF | Local process picker, or the STM32/MP157 remote entries below |
| Rust | codelldb asks for the executable | codelldb process picker |
| Python | Runs the current file with project `.venv`/`venv`, then `$VIRTUAL_ENV`, then packaged Python | Attach asks for a debugpy port (default `5678`); start debugpy yourself |
| Lua | Runs the current script in a separate headless Neovim with temporary `osv` | Attach to `127.0.0.1:8086`; `:DebugLuaListen` explicitly starts `osv` in the current editor |
| Java | Selects jdtls-provided main-class configs after DAP is loaded | `Space dj` runs the nearest Java test; `Space dJ` runs the test class |

The C/C++ remote configurations ask for an ELF and a host:port, defaulting to `127.0.0.1:3333` for STM32/OpenOCD and `192.168.7.1:2345` for MP157 gdbserver. Start OpenOCD or gdbserver yourself, then select and confirm the attach configuration. Neovim does not start a target server, connect during startup, or flash firmware automatically.

For MP157 shared-library symbols, use the GDB REPL (`Space dr`) with `set sysroot <existing target sysroot>` and, when source paths differ, `set substitute-path <build prefix> <local source>`. The SDK path depends on the installed SDK; inspect its target sysroot instead of assuming the SDK root is a sysroot. These are native GDB commands, not cppdbg `setupCommands`; the GDB DAP adapter does not consume that cppdbg field.

Opening a Java project starts jdtls with the packaged, filtered Microsoft debug/test JAR bundles. Each jdtls project gets its own hashed workspace under Neovim's cache directory; opening Java alone does not load the DAP feature or nvim-jdtls DAP integration.

The DAP view has seven sections: Variables/scopes, Watches, Breakpoints, Stack, Threads, REPL and Console. It auto-toggles with a debug session and can be toggled explicitly with `Space du`; `Space dr` opens its REPL and `Space de` adds a watch expression. Stack rows show frame, source and line; press Enter to focus a frame. Virtual text is compact, end-of-line, muted by default, and highlights changed values. The workspace statusline shows `Running` or `Stopped` while a session is active.

| Debug key | Action |
|---|---|
| `Space dc`, F5 | Continue debugging |
| `Space db`, F9 | Toggle breakpoint |
| `Space dn`, F10 | Step over |
| `Space di`, F11 | Step into |
| `Space do`, Shift-F11 | Step out |
| `Space dq` | Disconnect debugger |
| `Space dt`, Shift-F5 | Terminate debugging |
| `Space dC` | Run to cursor |
| `Space dR` | Restart debugging |
| `Space dl` | Run last configuration |
| `Space dX` | Clear breakpoints |
| `Space dp` | Pause debugging |
| `Space dB`, `Space dL` | Set conditional breakpoint / logpoint |
| `Space ds` | Select configuration |
| `Space du`, `Space dr` | Toggle debug panel / open debug REPL |
| `Space dh`, `Space de` | Inspect value / add watch expression |
| `Space dj`, `Space dJ` | Debug nearest Java test / test class |

All which-key labels and F-key descriptions are English action phrases. The same mappings are discoverable under the Debug group.

OpenComputers Lua projects can copy the optional [LuaLS template](templates/opencomputers.luarc.json) into their own root as `.luarc.json`; it declares only OpenComputers runtime globals. The template is documented in [the templates guide](templates/README.md). No project file is installed or edited by this feature. In CodeCompanion, a visible `AGENTS.md` rule reference is rendered as the muted `已加载规则：AGENTS.md` label; the rule context and metadata remain intact for the request pipeline.

## AI and Git

Claude Code uses claudecode.nvim's native IDE protocol and diff splits. Sidekick manages Codex/Grok CLI sessions. CodeCompanion uses `,r` to regenerate a chat reply and DeepSeek HTTP chat by default and optional ACP adapters for Codex/Claude. Provider tabs, model/connection state, chat roles, code blocks, tools and diff highlights share the workspace palette. CLI terminal contents remain owned by the CLI; the container and native review actions are styled without fabricating messages or authentication.

Native LSP completion also opens after a short pause while typing an identifier of at least two characters. It skips comments and large-file buffers; Ctrl-Space requests completion explicitly. Ctrl-n/Ctrl-p select items; Enter accepts an explicitly selected item and otherwise inserts a newline. Tab accepts the selected candidate, or the first candidate when none is selected. Escape closes an open menu while staying in Insert mode. With the menu closed, Tab first advances an active snippet, then accepts a Copilot inline suggestion, and otherwise indents; Alt-]/Alt-[ cycle AI suggestions. Ctrl-f/Ctrl-b scroll visible completion documentation. Native completion status messages such as “match 1 of 2” stay hidden. `Space au` (also `Space ua`) cycles Copilot → DeepSeek Minuet → off. Switching away from Copilot now also disables its LSP client; lazy setup respects an already-selected off state. Inlay hints start disabled. DeepSeek reads `DEEPSEEK_API_KEY`; missing keys/CLI binaries give a concise Chinese message. Copilot signs in with `:LspCopilotSignIn`. ACP paths come from ai-workbench's `NVIM_CODEX_ACP`/`NVIM_CLAUDE_ACP` or explicit standalone store paths. No runtime npx fallback is used. Offline checks verify commands, selections, accept/reject protocols and missing-credential behavior; they do not submit model requests.

| AI keys | Action |
|---|---|
| `Space ac`, `Space as` | Claude panel / send selection |
| `Space ax`, `Space af`, `Space av` | Codex CLI / send file / send selection |
| `Space ad`, `Space ai`, `Space ap`, `Space ah` | DeepSeek chat / inline edit / prompt actions / history |
| `Space au` or `Space ua`; `:AICompletion off` | Cycle completion provider / turn it off |
| Tab (menu closed, no active snippet), Alt-]/Alt-[ | Accept inline suggestion / next or previous suggestion |
| `,a`, `,r` in Claude diff; `Space aA`, `Space aD` | Accept / reject the proposed file change |
| Ctrl-S, `,r` in CodeCompanion chat | Send / regenerate (buffer-local, separate from Claude diff) |

Review AI changes before accepting: Claude opens its native diff; CodeCompanion inline edits use Mini.diff accept/reject; `Space gd` opens CodeDiff for a project-wide review. Opening a panel does not automatically submit a prompt. Offline fixtures test acceptance, rejection, snippet insertion and stale completion callbacks; live authentication, model behavior and network failure remain separate checks.

Gitsigns owns gutter signs and hunk actions. Mini.diff is reserved for CodeCompanion inline review and draws no gutter signs. CodeDiff handles review/history/conflicts, with packaged native diff support and no online installation. Temporary Git regression repositories use plumbing commands, preserving the checkout's index and history. Neogit provides native staging/commit/push commands when invoked by the user; verification does not invoke those actions.

## Terminal, ownership and checks

Kitty owns padding, cell geometry and Maple Mono NF CN font features; this feature does not overwrite terminal preferences. CJK remains on a two-cell grid; terminal spacing is owned by Kitty, not Neovim `linespace`. Neovim queries the terminal background and synchronizes OSC 11 with Normal on TUI entry and ColorScheme; exit/suspend restores the original background (OSC 111 fallback), and resume reapplies it. Tmux uses escaped DCS passthrough, clipboard and focus events. Headless runs emit no terminal escapes. The wrapper defaults `NVIM_NOTTYFAST=1` to skip the redundant early blocking 0.12 OSC 11/DSR probe; the asynchronous lifecycle remains editor-owned. Kitty's native scrollback pager remains suitable for ANSI terminal output; it is not a second full editor workspace.

Nix builds a palette-specific LuaJIT highlight cache and merges all packaged parser/query resources into one script-free startup runtime directory. lz.n defers new plugins, including DAP. Its one-shot heterogeneous spec registration runs with JIT temporarily paused and restores the previous JIT state; editing keeps JIT enabled. First-frame dashboard work stays small. Feature checks cover startup/parser visibility, workspace lifecycle, file safety, actual LSP samples, Lua diagnostics, native completion, sessions/tasks, AI protocols, CodeDiff asynchronous buffer loading, auxiliary surfaces and OSC restoration. The pinned Snacks LSP finder has a small [coroutine-delivery patch](patches/snacks-lsp-coroutine.patch): main-loop LSP handlers convert responses, then the finder coroutine delivers items. This prevents a mixed-source picker from yielding through Neovim’s callback boundary; keyed request cancellation and late replies are covered by `tests/picker_lsp.lua`. Patch application and runtime regression are build checks; re-evaluate it on a Snacks upgrade. The native completion menu, documentation and keyboard refinement is recorded in [round 30](../../../docs/history/nvim-r30-native-completion-2026-10-25.md). The unified floating surfaces, compact which-key and automatic native completion are recorded in [round 29](../../../docs/history/nvim-r29-2026-10-25.md). Earlier runtime screenshots and timing evidence are recorded in [round 28](../../../docs/history/nvim-r28-2026-10-25.md), with the [round 25 baseline](../../../docs/history/nvim-minimal-2026-10-25.md) retained separately. Measurements are not hardware activation evidence.

Removing the feature removes its package and managed `nvim/init.lua` link after activation. Projects, histories, login state, CodeCompanion sessions and files outside the managed link are preserved. Activation follows the normal NixOS rebuild workflow; existing editor processes must be restarted to load a new configuration.

Round 37 reviews CodeCompanion 20's tool-based inline flow and ACP adapter overrides against the locked source. Existing `interactions`, DeepSeek tool support, and ACP executable/auth options remain compatible. The Mini.diff bridge now implements v20’s `remove_inline_marks()` and original/proposed line snapshots; a fixture invokes real `Inline:review()` accept/reject callbacks without making model requests. The offline integration test gates major upgrades and compares the loaded plugin version to Nix-generated metadata instead of hard-coding an old minor version twice. History, review accept/reject, and chat context fixtures still run against the real plugin; live model/ACP authentication remains a separate runtime check.
