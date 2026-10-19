{ den, ... }: {
  imports = [
    ../appearance
    ../workspace-task
  ];
  den.aspects = {
    # Shared support has two real consumers. Each session still owns its
    # compositor, shell, portal routing, tools and lifecycle implementation.
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
    interactive-session = { host, user, ... }: {
      includes = [ den.aspects.graphical-session-support ];
      homeManager =
        {
          noctaliaIntegrations ? [ ],
          lib,
          pkgs,
          ...
        }:
        {
          imports = [
            (import ./mango.nix { palette = user.appearance; })
            (import ./noctalia.nix {
              palette = user.appearance;
              inherit noctaliaIntegrations;
            })
            ./clipboard.nix
            ./screenshot.nix
          ];
          nixDotfiles.graphicalSessionTargets = [ "mango-session.target" ];
          home.sessionVariables.NIXOS_OZONE_WL = "1";
          systemd.user.sessionVariables.NIXOS_OZONE_WL = "1";
          home.packages = with pkgs; [
            wl-clipboard
            grim
            slurp
            libdecor
          ];
          programs.btop.settings.color_theme = lib.mkIf (builtins.elem "btop" noctaliaIntegrations) "noctalia";
        };
      provides.${host.name}.includes = [ den.aspects.interactive-session-host ];
    };
    xorg-session = { host, user, ... }: {
      includes = [ den.aspects.graphical-session-support ];
      homeManager = import ./xorg { palette = user.appearance; };
      provides.${host.name}.includes = [ den.aspects.xorg-session-host ];
    };
    xorg-session-host.nixos.imports = [ ./xorg/host.nix ];
    interactive-session-host.nixos.imports = [
      ./host/mango.nix
      ./host/portal.nix
    ];
    login-screen = { host, ... }: { nixos = import ./greeter.nix { palette = host.appearance; }; };
  };
}
