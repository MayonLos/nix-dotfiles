{ inputs, pkgs, ... }:
{
  # Grok Bot's desktop client is separate from the Grok Build CLI in ai-agents.
  home.packages = [ inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.grok-bot ];
  xdg.mimeApps.defaultApplications = {
    "x-scheme-handler/grokbot" = "grok-bot.desktop";
    "x-scheme-handler/sand" = "grok-bot.desktop";
  };
}
