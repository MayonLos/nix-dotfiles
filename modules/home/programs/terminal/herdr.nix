{ inputs, pkgs, ... }:
{
  home.packages = [ inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.herdr ];

  # Agent integrations live in their mutable user configuration, outside Nix.
  # Install/refresh with `herdr integration install codex` or `opencode`;
  # the upstream installer merges its hooks without managing authentication.

  xdg.configFile."herdr/config.toml".text = ''
    # Skip the first-run wizard; Home Manager owns this configuration.
    onboarding = false

    # Match tmux's prefix and vi-style pane/copy navigation.
    [keys]
    prefix = "ctrl+a"

    # Follow kitty's live ANSI palette, including Noctalia's theme changes.
    [theme]
    name = "terminal"

    # Do not persist pane output, which can contain prompts, tokens, or secrets.
    [experimental]
    pane_history = false
  '';
}
