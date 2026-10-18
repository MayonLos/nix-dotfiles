{ inputs, pkgs }:
let
  inherit (pkgs) lib;
  evaluate =
    system:
    (inputs.flake-parts.lib.mkFlake { inherit inputs; } (
      { den, ... }: {
        imports = [
          inputs.den.flakeModule
          ../../aspects
          ../../bundles
        ];
        den.systems = [ system ];
        den.schema.user.classes = [ "homeManager" ];
        den.hosts.${system}.fixture.users.alice.appearance =
          import ../../aspects/appearance/onedark-darker.nix;
        den.aspects.fixture = {
          includes = [ den.aspects.system-maintenance ];
          nixos = {
            system.stateVersion = "26.05";
            boot.loader.grub.enable = false;
            fileSystems."/" = {
              device = "none";
              fsType = "tmpfs";
            };
            home-manager.useGlobalPkgs = true;
            home-manager.extraSpecialArgs = { inherit inputs; };
          };
        };
        den.aspects."alice@fixture" = {
          includes = [ den.aspects.remote-workspace ];
          user.isNormalUser = true;
          homeManager.home = {
            username = "alice";
            homeDirectory = "/home/alice";
            stateVersion = "26.05";
          };
        };
      }
    )).nixosConfigurations.fixture.config;
  inspect =
    system:
    let
      host = evaluate system;
      home = host.home-manager.users.alice;
      names = map (p: p.pname or (lib.getName p)) home.home.packages;
    in
    {
      platform = host.nixpkgs.hostPlatform.system == system;
      cliAndEditor =
        home.programs.zsh.enable && builtins.elem "neovim" names && home.xdg.configFile ? "nvim/init.lua";
      noDesktop =
        !host.services.xserver.enable
        && !host.services.greetd.enable
        && !(host.programs.mango.enable or false)
        && !host.services.pipewire.enable
        && !(home.programs.noctalia.enable or false)
        && !home.i18n.inputMethod.enable
        && !(home.xdg.configFile ? "kitty/kitty.conf");
      noLocalDaemons =
        !host.virtualisation.docker.rootless.enable
        && !host.virtualisation.libvirtd.enable
        && !(home.systemd.user.services ? docker)
        && !(home.home.sessionVariables ? DOCKER_HOST);
      noLaptopOrPersonalAuthorization =
        !(host.hardware.nvidia.prime.offload.enable or false)
        && !host.services.power-profiles-daemon.enable
        && !host.services.tlp.enable
        && host.users.users.alice.extraGroups == [ ]
        && !(builtins.elem "mayon" host.nix.settings.trusted-users)
        && !(host ? sops)
        && !(host.systemd.services.nix-daemon.environment ? https_proxy)
        && !(lib.hasInfix "/run/secrets" home.programs.zsh.initContent)
        && !(home.programs.java.enable or false);
    };
  results = lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] inspect;
  passed = lib.all (r: lib.all (v: v) (builtins.attrValues r)) (builtins.attrValues results);
in
assert lib.assertMsg passed "Remote workspace boundary failure: ${builtins.toJSON results}";
pkgs.writeText "remote-workspace-composition.json" (builtins.toJSON results)
