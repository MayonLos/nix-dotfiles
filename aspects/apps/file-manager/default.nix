{ den, ... }:
{
  den.aspects.file-manager = { host, ... }: {
    homeManager =
      { pkgs, ... }:
      let
        fileManager = import ./packages.nix { inherit pkgs; };
      in
      {
        imports = [
          ./thunar-actions.nix
          ./thunar-terminal.nix
          ./templates.nix
        ];
        home.packages = [
          fileManager.thunarWithPlugins
          pkgs.file-roller
        ];
        xdg.dataFile."dbus-1/services/org.freedesktop.FileManager1.service".text = ''
          [D-BUS Service]
          Name=org.freedesktop.FileManager1
          Exec=${fileManager.thunarWithPlugins}/bin/Thunar --gapplication-service
          SystemdService=thunar.service
        '';
      };
    provides.${host.name}.includes = [ den.aspects.file-manager-host-support ];
  };

  den.aspects.file-manager-host-support.nixos.imports = [ ./host.nix ];
}
