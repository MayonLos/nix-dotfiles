{ den, ... }: {
  imports = [ ../appearance ];
  den.aspects = {
    interactive-session = { host, user, ... }: {
      homeManager =
        {
          noctaliaIntegrations ? [ ],
          lib,
          ...
        }:
        {
          imports = [
            ./session-targets.nix
            (import ./mango.nix { palette = user.appearance; })
            (import ./noctalia.nix {
              palette = user.appearance;
              inherit noctaliaIntegrations;
            })
            (import ./input-method.nix { palette = user.appearance; })
            (import ./gtk.nix { palette = user.appearance; })
            (import ./qt.nix { palette = user.appearance; })
            ./xresources.nix
            ./environment.nix
            ./clipboard.nix
            ./screenshot.nix
            ./tools.nix
          ];
          nixDotfiles.graphicalSessionTargets = [ "mango-session.target" ];
          programs.btop.settings.color_theme = lib.mkIf (builtins.elem "btop" noctaliaIntegrations) "noctalia";
        };
      user.extraGroups = [ "input" ];
      provides.${host.name}.includes = [ den.aspects.interactive-session-host ];
    };
    xorg-session = { host, user, ... }: {
      includes = [ den.aspects.interactive-session ];
      homeManager = import ./xorg.nix { palette = user.appearance; };
      provides.${host.name}.includes = [ den.aspects.xorg-session-host ];
    };
    xorg-session-host.nixos.imports = [ ./host/xorg.nix ];
    interactive-session-host = { host, ... }: {
      nixos.imports = [
        ./host/mango.nix
        ./host/portal.nix
        ./host/audio.nix
        ./host/polkit.nix
        (import ./host/fonts.nix { palette = host.appearance; })
      ];
    };
    login-screen = { host, ... }: { nixos = import ./greeter.nix { palette = host.appearance; }; };
  };
}
