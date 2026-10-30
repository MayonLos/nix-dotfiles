_: {
  den.aspects = {
    clash-tui = { user, ... }: {
      homeManager = { pkgs, ... }: { home.packages = [ pkgs.mayonTui.clash ]; };
      nixos.services.mayon-clash.user = user.name;
    };
    network-manager-user.user.extraGroups = [ "networkmanager" ];
    laptop-network.nixos.imports = [
      ./network.nix
      ./clash.nix
      ./native-clash.nix
    ];
  };
}
