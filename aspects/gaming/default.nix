{ den, ... }: {
  den.aspects = {
    gaming = { host, ... }: {
      homeManager.imports = [
        ./mangohud.nix
        ./prismlauncher.nix
      ];
      user.extraGroups = [ "gamemode" ];
      provides.${host.name}.includes = [ den.aspects.gaming-host-support ];
    };
    gaming-host-support.nixos.imports = [
      ./host/gamemode.nix
      ./host/gamescope.nix
      ./host/steam.nix
    ];
  };
}
