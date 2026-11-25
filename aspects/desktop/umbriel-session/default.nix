{ den, ... }:
{
  imports = [
    ../../appearance/appearance
    ../../workspace/workspace-task
  ];
  den.aspects = {
    # Experimental second session: Umbriel compositor + Noctalia shell.
    # It is additive: the Mango session aspect stays untouched, so the greeter
    # offers both sessions and either one can be selected at login.
    umbriel-session = { host, user, ... }: {
      includes = [
        den.aspects.graphical-session-support
        den.aspects.noctalia-shell
        den.aspects.noctalia-benchmark
      ];
      user.extraGroups = [ "video" ];
      homeManager =
        {
          pkgs,
          ...
        }:
        {
          imports = [
            (import ./umbriel.nix {
              palette = user.appearance;
              display = host.facts.display;
            })
            ./luciole.nix
          ];
          # Session-support services (input method, GTK/Qt, X resources) follow
          # every target listed here, so they start in either session.
          nixDotfiles.graphicalSessionTargets = [ "umbriel-session.target" ];
          home.sessionVariables.NIXOS_OZONE_WL = "1";
          systemd.user.sessionVariables.NIXOS_OZONE_WL = "1";
          home.packages = with pkgs; [
            libnotify
            wl-clipboard
            grim
            slurp
            libdecor
            brightnessctl
            playerctl
          ];
        };
      provides.${host.name}.includes = [ den.aspects.umbriel-session-host ];
    };
    umbriel-session-host = { host, ... }: {
      nixos.imports = [
        (import ./host.nix { palette = host.appearance; })
      ];
    };
  };
}
