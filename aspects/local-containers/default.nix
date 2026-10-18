{ den, ... }:
{
  den.aspects.container-client.homeManager = { pkgs, ... }: {
    home.packages = [ pkgs.docker ];
  };

  den.aspects.local-containers = { host, ... }: {
    includes = [ den.aspects.container-client ];

    homeManager = {
      home.sessionVariables.DOCKER_HOST = "unix://$XDG_RUNTIME_DIR/docker.sock";
      systemd.user.sessionVariables.DOCKER_HOST = "unix://$XDG_RUNTIME_DIR/docker.sock";
    };
    homeManager.imports = [ ./home.nix ];

    provides.${host.name}.includes = [ den.aspects.local-containers-host-support ];
  };

  # Host support enables the official rootless daemon only on hosts where at
  # least one account selects local-containers.
  den.aspects.local-containers-host-support.nixos.imports = [ ./host.nix ];
}
