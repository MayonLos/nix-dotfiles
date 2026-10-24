# Neovim

This feature installs the repository's Neovim build and generates its runtime data from an explicit palette and validated `editorLanguages` contributions. Language contributions are consumed only when this editor aspect is selected.

`package.nix` is the public parameterized package factory. Callers provide `pkgs`, `palette`, and `contributions`; the factory returns `normal`, `dev`, and `configDir`. `pkgs.unstable.codecompanion-nvim` supplies CodeCompanion 19.27.0 while its Plenary runtime dependency remains stable. Optional `acpAdapters` supplies absolute paths for `codex-acp` and `claude-agent-acp`. The factory does not accept a separate unstable package-set argument.

`default.nix` is the public registration entry. `checks.nix` is the public feature test hook, with the explicit inputs declared by its function. `config/` is private and may be used only by this feature's package and checks; `plugins.nix` and `parsers.nix` are also private. The thin standalone flake outputs and their ACP paths are assembled in `nix/outputs.nix`; feature checks are registered through `nix/checks.nix`.

Nix fixes plugin and tool versions, Den supplies language contributions and the palette, and lz.n manages loading. Plugins are not downloaded at runtime. Copilot credentials are managed by `:LspCopilotSignIn`; DeepSeek reads only `DEEPSEEK_API_KEY` from the environment. ACP adapters use the public `NVIM_CODEX_ACP` and `NVIM_CLAUDE_ACP` session variables supplied by ai-workbench for Home Manager sessions, and absolute store paths for the standalone package. Missing paths produce an error; Neovim does not use npx or download a fallback.

Claude Code uses claudecode.nvim for its IDE protocol and terminal. Sidekick manages Codex/Grok TUI sessions and NES; CodeCompanion provides DeepSeek HTTP chat/inline editing and optional Codex/Claude ACP. Copilot is the primary inline completion source, with manually selected Minuet DeepSeek FIM as fallback. AI suggestions remain separate from the native LSP completion menu. Git review uses stable codediff 2.45.0 and its packaged `libvscode_diff.so`; online installation is disabled. CodeCompanion 19.27's inline review compatibility helper is covered by feature checks.

The feature checks run in isolated HOME/XDG directories. They cover file safety, LSP and UI behavior, AI loading, ACP executable paths, completion switching, MiniDiff review, Claude protocol accept/reject, codediff and native Neovim features, and key mappings. Model requests, real tmux navigation, narrow-screen appearance, GUI input, and actual IME behavior require runtime verification.

Removing the aspect removes the package and managed `nvim/init.lua` link after activation. It preserves user projects, editor histories, plugin state, CodeCompanion history, and files outside the managed link; no project files or user data are rewritten.

Theme data comes from `generated.palette`: editing uses deep/brightFg, floats and native menus use bg,
selection uses selection, and pending AI text uses muted italic. The immutable package compiles the pinned
One Dark adapter into a LuaJIT highlight cache at build time; development overrides use the live adapter.
LSP starts on the first FileType; explorer safety hooks are installed by its source configuration before actions.
Heirline starts on UIEnter/FileType, while URL parsing and sessions load at their first relevant entry point.
