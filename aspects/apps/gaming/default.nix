{ den, ... }: {
  den.aspects = {
    gaming = { host, user, ... }: {
      homeManager.imports = [
        ./mangohud.nix
        ./mcsrv.nix
        (import ./prismlauncher.nix { palette = user.appearance; })
      ];
      user.extraGroups = [
        "gamemode"
        "mcsrv-firewall"
      ];
      provides.${host.name}.includes = [ den.aspects.gaming-host ];
    };
    gaming-host.nixos.imports = [
      ./host/gamemode.nix
      ./host/gamescope.nix
      ./host/mcsrv-firewall.nix
      ./host/steam.nix
    ];
  };
}
