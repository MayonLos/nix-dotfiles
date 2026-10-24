{ inputs, pkgs, ... }:
{
  # Grok Bot's desktop client is separate from the Grok Build CLI in ai-agents.
  home.packages = [ pkgs.local.grok-bot ];
  xdg.mimeApps.enable = true;
  xdg.mimeApps.defaultApplications = {
    "x-scheme-handler/grokbot" = "grok-bot.desktop";
    "x-scheme-handler/sand" = "grok-bot.desktop";
  };
}
