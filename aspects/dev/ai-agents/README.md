# AI agents

Installs selected command-line AI coding agents and a dedicated DeepSeek Harness desktop launcher. Inputs are the locked third-party package aliases and the user's interactive authentication at first launch; no API keys or login material are stored in Nix configuration.

Outputs include Codex, Claude Code, Grok Build CLI, Grok Bot, and the DeepSeek Harness CLI/window launcher. The Harness desktop profile and runtime are kept under XDG data paths and isolated from legacy `~/.dsh` plugins. This feature does not start agents as services or run them automatically.

Owned files are `default.nix`, `ai-agents.nix`, `claude-code.nix`, `dsh-desktop.nix`, and `grok-bot.nix`; all Nix files are private. Removing the feature removes package and desktop declarations but preserves agent histories, authentication, project files, harness state, and local models/data.
