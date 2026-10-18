{ den, ... }:
{
  den.aspects.file-manager = { host, ... }: {
    homeManager = { pkgs, ... }: {
      imports = [
        ./thunar-actions.nix
        ./thunar-terminal.nix
      ];
      home.packages = [ pkgs.xarchiver ];
    };
    provides.${host.name}.includes = [ den.aspects.file-manager-host-support ];
  };

  den.aspects.file-manager-host-support.nixos.imports = [ ./host.nix ];
}
