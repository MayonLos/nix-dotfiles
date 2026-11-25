{ den, ... }:
{
  imports = [
    ../../appearance/appearance
    ../../workspace/workspace-task
  ];
  den.aspects = {
    # Experimental third session: Hyprland compositor + Noctalia shell.
    # It is additive: the Mango and Umbriel session aspects stay untouched, so
    # the greeter offers all three sessions and any one can be selected.
    hyprland-session =
      { host, user, ... }:
      {
        includes = [ den.aspects.graphical-session-support ];
        user.extraGroups = [ "video" ];
        homeManager =
          { pkgs, ... }:
          {
            imports = [
              (import ./hyprland.nix {
                palette = user.appearance;
                display = host.facts.display;
              })
              # The shell contract (bar, palette, launcher, lock, OSD, system
              # monitor) is compositor-independent, so it is shared verbatim
              # with the Umbriel session instead of being forked.
              (import ../umbriel-session/noctalia.nix {
                palette = user.appearance;
              })
              ../umbriel-session/luciole.nix
            ];
            # Session-support services (input method, GTK/Qt, X resources)
            # follow every target listed here, so they start in any session.
            nixDotfiles.graphicalSessionTargets = [ "hyprland-session.target" ];
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
        provides.${host.name}.includes = [ den.aspects.hyprland-session-host ];
      };
    hyprland-session-host = { host, ... }: {
      nixos.imports = [
        (import ./host.nix { palette = host.appearance; })
      ];
    };
  };
}
