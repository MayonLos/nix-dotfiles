_: {
  den.aspects = {
    clash-tui.homeManager = { pkgs, ... }: {
      home.packages = [ pkgs.mayonTui.clash ];
    };
    network-manager-user.user.extraGroups = [ "networkmanager" ];
    laptop-network.nixos.imports = [
      ./network.nix
      ./clash.nix
    ];
  };
}
