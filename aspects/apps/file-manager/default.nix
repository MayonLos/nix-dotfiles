{ den, ... }:
{
  den.aspects.file-manager = { host, ... }: {
    homeManager =
      { pkgs, ... }:
      {
        imports = [
          ./thunar-actions.nix
          ./thunar-terminal.nix
          ./templates.nix
          ./preferences.nix
        ];
        home.packages = [
          pkgs.file-roller
        ];
      };
    provides.${host.name}.includes = [ den.aspects.file-manager-host-support ];
  };

  den.aspects.file-manager-host-support.nixos.imports = [ ./host.nix ];
}
