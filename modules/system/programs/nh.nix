_:
let
  desktop = import ../../../lib/desktop.nix;
in
{
  programs.nh = {
    enable = true;
    flake = desktop.repoPath;
    clean = {
      enable = true;
      extraArgs = "--keep 5 --keep-since 14d";
    };
  };
}
