{
  pkgs,
  lib,
  config,
  ...
}:
{
  home.packages = with pkgs; [
    eza
    ripgrep
    duf
    nix-output-monitor
    fd
    jq
    hexyl
    dust
    tealdeer
    sops
    p7zip
    libqalculate
  ];

  programs.bat = {
    enable = true;
    config = {
      theme = "base16";
      style = "numbers,changes,header";
    };
  };

  # Home Manager 26.05 rebuilds the bat cache on every activation even when
  # no custom themes or syntaxes are configured. The selected base16 theme is
  # built into bat, so suppress that unnecessary activation step while
  # retaining Home Manager's cache builder if custom assets are added later.
  home.activation =
    lib.mkIf (config.programs.bat.themes == { } && config.programs.bat.syntaxes == { })
      {
        batCache = lib.mkForce (lib.hm.dag.entryAnywhere "");
      };
}
