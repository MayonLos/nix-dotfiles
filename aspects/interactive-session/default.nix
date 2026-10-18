{ den, ... }: {
  den.schema.host.imports = [ ../appearance/contract.nix ];
  den.aspects = {
    interactive-session = { host, user, ... }: {
      homeManager =
        {
          noctaliaIntegrations ? [ ],
          ...
        }:
        {
          imports = [
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
          systemd.user.targets.mango-session.Unit.Wants = [
            "pipewire.socket"
            "pipewire-pulse.socket"
          ];
          programs.btop.settings.color_theme = "noctalia";
        };
      user.extraGroups = [ "input" ];
      provides.${host.name}.includes = [ den.aspects.interactive-session-host ];
    };
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
