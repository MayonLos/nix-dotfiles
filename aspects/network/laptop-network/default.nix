_: {
  den.aspects = {
    network-manager-user.user.extraGroups = [ "networkmanager" ];
    laptop-network.nixos.imports = [
      ./network.nix
      ./clash.nix
    ];
  };
}
