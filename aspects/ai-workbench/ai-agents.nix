{
  pkgs,
  inputs,
  ...
}:

# AI coding agents that come from the llm-agents.nix flake input rather than
# nixpkgs. The base packages are prebuilt on cache.numtide.com (configured in
# aspects/system/maintenance/nix.nix); the command and desktop launchers below
# reuse those packages.
let
  agents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};

  # The pinned llm-agents recipe now applies the Node frame-pointer workaround
  # from NixOS/nixpkgs#565667 and llm-agents.nix#9994 to both app-boot entry
  # points (index.js and worker/profile-resolution-bootstrap.js), using plain
  # require() with --expose-internals. Reapplying our old replacement fails
  # because upstream has already removed the native-addon expression.
  dshCli = agents.dsh;

  dshDesktop = pkgs.callPackage ./dsh-desktop.nix { dsh = dshCli; };

  # Use the desktop's Harness home by default instead of reactivating legacy
  # ~/.dsh plugins. Explicit DSH_HOME still supports isolated scripts and CI.
  dshCommand = pkgs.writeShellScriptBin "dsh" ''
    dsh_home="''${DSH_HOME:-}"
    if [[ "$dsh_home" =~ ^[[:space:]]*$ ]]; then
      dsh_home="''${XDG_DATA_HOME:-$HOME/.local/share}/dsh-desktop/harness"
    fi
    export DSH_HOME="$dsh_home"
    exec ${pkgs.lib.getExe dshCli} "$@"
  '';

in
{
  home.packages = [
    # Upstream has no Linux Electron release yet. Keep its official Web UI in
    # a dedicated desktop window; the command uses the same patched runtime.
    # Runtime state lives in $XDG_DATA_HOME/dsh-desktop/harness (defaulting to
    # ~/.local/share), isolated from the removed CLI's ~/.dsh plugins.
    dshDesktop
    dshCommand

    # OpenAI's CLI agent, authenticated through the user's ChatGPT account.
    # Its ~/.codex/config.toml remains user-managed, outside Nix.
    #
    # llm-agents provides the complete package layout and a daemon patch using
    # the immutable store package. Verified with an isolated 0.162.1 cold start;
    # the former --no-daemon wrapper is no longer needed.
    agents.codex
    agents.codex-acp
    agents.claude-agent-acp

    # Claude Code's Nix-managed CLI; authentication and history stay user-owned.
    agents.claude-code

    # xAI's official Grok Build coding agent. Provides both `grok` for
    # interactive sessions and `agent` for automation. Authentication is via
    # browser OAuth on first launch or XAI_API_KEY for non-browser use.
    agents.grok
  ];

  # Public runtime hand-off to editor consumers; only executable paths, no credentials.
  # The standalone Neovim factory also accepts these as explicit build inputs.
  home.sessionVariables = {
    NVIM_CODEX_ACP = "${agents.codex-acp}/bin/codex-acp";
    NVIM_CLAUDE_ACP = "${agents.claude-agent-acp}/bin/claude-agent-acp";
  };

  # NOT here: `agents.zcode` (Z.ai's Electron IDE). Removed 2026-09-19 at the
  # user's instruction after it was observed pushing to a user repository
  # without being asked. Do not add it back.
}
