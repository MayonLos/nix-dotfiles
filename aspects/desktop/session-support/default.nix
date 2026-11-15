{ den, ... }: {
  imports = [
    ../../appearance/appearance
    ../../workspace/workspace-task
  ];
  den.aspects = {
    graphical-session-support = { host, user, ... }: {
      includes = [ den.aspects.workspace-task ];
      homeManager.imports = [
        ./session-targets.nix
        (import ./input-method.nix { palette = user.appearance; })
        (import ./gtk.nix { palette = user.appearance; })
        (import ./qt.nix { palette = user.appearance; })
        ./xresources.nix
        ./environment.nix
        ./tools.nix
      ];
      user.extraGroups = [ "input" ];
      provides.${host.name}.includes = [ den.aspects.graphical-session-support-host ];
    };
    graphical-session-support-host = { host, ... }: {
      nixos.imports = [
        ./host/portal-common.nix
        ./host/audio.nix
        ./host/polkit.nix
        (import ./host/fonts.nix { palette = host.appearance; })
      ];
    };
  };
}
