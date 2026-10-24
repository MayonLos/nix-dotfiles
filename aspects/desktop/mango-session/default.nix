{ den, ... }: {
  imports = [
    ../../appearance/appearance
    ../../workspace/workspace-task
  ];
  den.quirks.noctaliaIntegrations.description = "Selected applications requesting Noctalia palette integration";
  den.aspects = {
    interactive-session = { host, user, ... }: {
      includes = [ den.aspects.graphical-session-support ];
      homeManager =
        {
          noctaliaIntegrations ? [ ],
          lib,
          pkgs,
          ...
        }:
        let
          integrations = (import ./contract.nix { inherit lib; }).collect noctaliaIntegrations;
        in
        {
          imports = [
            (import ./mango.nix { palette = user.appearance; })
            (import ./noctalia.nix {
              palette = user.appearance;
              avatar = if builtins.elem "avatar" integrations.ids then user.avatar else null;
              noctaliaIntegrations = integrations.ids;
              integrationTemplates = integrations.entries;
              hostName = host.name;
              flakePath = user.flakePath or host.flakePath;
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
        };
      provides.${host.name}.includes = [ den.aspects.interactive-session-host ];
    };
    interactive-session-host.nixos.imports = [
      ./host/mango.nix
      ./host/portal.nix
    ];
  };
}
