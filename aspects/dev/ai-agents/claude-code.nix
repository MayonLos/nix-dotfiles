{ pkgs, ... }:

# Claude Code's status line. The CLI itself comes from ai-agents.nix;
# ~/.claude/settings.json, credentials and history stay user-owned because
# Claude Code rewrites settings at runtime. Only the script the user-owned
# `statusLine.command` runs (`bash ~/.claude/statusline-command.sh`) is
# managed here, with jq and git pinned instead of taken from PATH.
let
  statusline = pkgs.writeShellApplication {
    name = "claude-statusline";
    runtimeInputs = with pkgs; [
      coreutils
      git
      hostname
      jq
    ];
    text = builtins.readFile ./claude-statusline.sh;
  };
in
{
  home.packages = [ statusline ];
  home.file.".claude/statusline-command.sh".source = pkgs.lib.getExe statusline;
}
