{ inputs, pkgs, ... }:
let
  pi = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi;
in
{
  # Pi keeps provider login separate from Codex: use /login and ~/.pi/agent/auth.json.
  # Compatible local endpoints can be declared in ~/.pi/agent/models.json.
  home.packages = [ pi ];
}
