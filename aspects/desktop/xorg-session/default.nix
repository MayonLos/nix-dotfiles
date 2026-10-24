{ den, ... }: {
  imports = [
    ../../appearance/appearance
    ../../workspace/workspace-task
  ];
  den.aspects = {
    xorg-session = { host, user, ... }: {
      includes = [ den.aspects.graphical-session-support ];
      homeManager = import ./home.nix { palette = user.appearance; };
      provides.${host.name}.includes = [ den.aspects.xorg-session-host ];
    };
    xorg-session-host.nixos.imports = [ ./host.nix ];
  };
}
