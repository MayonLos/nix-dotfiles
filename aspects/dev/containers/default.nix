{ den, ... }:
{
  den.aspects = {
    container-client = {
      includes = [ den.aspects.mayon-tools ];
      homeManager = { pkgs, ... }: { home.packages = [ pkgs.docker ]; };
    };

    local-containers = { host, ... }: {
      includes = [ den.aspects.container-client ];

      homeManager = {
        home.sessionVariables.DOCKER_HOST = "unix://$XDG_RUNTIME_DIR/docker.sock";
        systemd.user.sessionVariables.DOCKER_HOST = "unix://$XDG_RUNTIME_DIR/docker.sock";
        imports = [ ./home.nix ];
      };

      provides.${host.name}.includes = [ den.aspects.local-containers-host ];
    };

    # Host support enables the official rootless daemon only on hosts where at
    # least one account selects local-containers.
    local-containers-host.nixos.imports = [ ./host.nix ];
  };
}
