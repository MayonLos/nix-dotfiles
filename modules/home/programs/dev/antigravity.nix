{
  pkgs,
  pkgs-unstable,
  inputs,
  ...
}:

# Google Antigravity, re-added 2026-10-01 at the user's request (it had been
# removed 2026-09-20 as unused). Two packages, two sources:
#
# - The IDE has no counterpart in llm-agents.nix, and stable 26.05 does not
#   even carry `antigravity-ide-fhs` (the attribute is absent), so it comes
#   from unstable. The FHS variant is required: the IDE pulls prebuilt
#   binaries for extensions and language servers, which need a normal
#   filesystem layout to load (same reasoning as vscode-fhs -- see
#   ./vscode.nix).
#
# - The CLI is an agent CLI, so it comes from llm-agents.nix like codex, grok,
#   opencode and dsh: updated daily against cache.numtide.com, and newer than
#   nixpkgs-unstable (1.2.12 vs 1.2.9 there). The binary is `agy`.
let
  agents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  programs = {
    antigravity = {
      enable = true;
      package = pkgs-unstable.antigravity-ide-fhs;
    };

    antigravity-cli = {
      enable = true;
      package = agents.antigravity-cli;
    };
  };
}
