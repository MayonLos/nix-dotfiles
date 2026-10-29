{ inputs, pkgs }:
let
  lib = inputs.nixpkgs.lib;
  system = "x86_64-linux";

  evaluate =
    selected:
    (inputs.flake-parts.lib.mkFlake { inherit inputs; } (
      { den, ... }:
      {
        imports = [
          inputs.den.flakeModule
          ../../aspects/dev/containers
          ../../aspects/dev/virtual-machines
          ../../aspects/dev/embedded
        ];

        den = {
          systems = [ system ];
          schema.user.classes = [ "homeManager" ];

          hosts.${system} = {
            # Reuse the registered package set, including local public packages.
            hostA.instantiate = args: inputs.nixpkgs.lib.nixosSystem (args // { inherit pkgs; });
            hostB.instantiate = args: inputs.nixpkgs.lib.nixosSystem (args // { inherit pkgs; });
            hostA.users = {
              alice = { };
              bob = { };
            };
            hostB.users = {
              alice = { };
              bob = { };
            };
          };

          default = {
            nixos = {
              system.stateVersion = "26.05";
              boot.loader.grub.enable = false;
              fileSystems."/" = {
                device = "none";
                fsType = "tmpfs";
              };
              home-manager.useGlobalPkgs = true;
              home-manager.extraSpecialArgs.inputs = inputs;
            };
            homeManager = {
              home.stateVersion = "26.05";
            };
          };

          aspects =
            lib.genAttrs
              [
                "alice@hostA"
                "bob@hostA"
                "alice@hostB"
                "bob@hostB"
              ]
              (
                binding:
                let
                  username = builtins.head (lib.splitString "@" binding);
                  selectedForUser = selected.${binding} or [ ];
                in
                {
                  user.isNormalUser = true;
                  homeManager.home = {
                    inherit username;
                    homeDirectory = "/home/${username}";
                  };
                  includes =
                    lib.optionals (lib.elem "container-client" selectedForUser) [
                      den.aspects.container-client
                    ]
                    ++ lib.optionals (lib.elem "virtual-machine-client" selectedForUser) [
                      den.aspects.virtual-machine-client
                    ]
                    ++ lib.optionals (lib.elem "local-containers" selectedForUser) [
                      den.aspects.local-containers
                    ]
                    ++ lib.optionals (lib.elem "local-virtual-machines" selectedForUser) [
                      den.aspects.local-virtual-machines
                    ]
                    ++ lib.optionals (lib.elem "embedded-workbench" selectedForUser) [
                      den.aspects.embedded-workbench
                    ];
                }
              );
        };
      }
    )).nixosConfigurations;

  clientsOnly = evaluate {
    "alice@hostB" = [ "container-client" ];
    "bob@hostB" = [ "virtual-machine-client" ];
  };
  localOnly = evaluate {
    "alice@hostA" = [
      "local-containers"
      "local-virtual-machines"
      "embedded-workbench"
    ];
  };
  sharedHost = evaluate {
    "alice@hostA" = [
      "local-containers"
      "local-virtual-machines"
      "embedded-workbench"
    ];
    "bob@hostA" = [
      "local-containers"
      "local-virtual-machines"
      "embedded-workbench"
    ];
  };
  afterLastLocalConsumerRemoved = clientsOnly;

  host = configs: name: configs.${name}.config;
  home =
    configs: hostName: userName:
    (host configs hostName).home-manager.users.${userName};
  hasPackage =
    profile: package:
    builtins.elem package.outPath (map (installed: installed.outPath) profile.home.packages);

  clientsHostB = host clientsOnly "hostB";
  localHostA = host localOnly "hostA";
  localHostB = host localOnly "hostB";
  sharedHostA = host sharedHost "hostA";
  postRemovalHostA = host afterLastLocalConsumerRemoved "hostA";
  selectedAlice = home localOnly "hostA" "alice";
  sharedAlice = home sharedHost "hostA" "alice";
  sharedBob = home sharedHost "hostA" "bob";
  embeddedRules = [
    pkgs.openocd
    (import ../../aspects/dev/embedded/contract.nix { inherit pkgs; }).seatRules
  ];
  rulePaths = config: map toString config.services.udev.packages;
  hasAllRules =
    config: builtins.all (package: lib.elem (toString package) (rulePaths config)) embeddedRules;
  noEmbeddedRules =
    config: builtins.all (package: !(lib.elem (toString package) (rulePaths config))) embeddedRules;
  groups = config: user: lib.sort builtins.lessThan config.users.users.${user}.extraGroups;
  selectedContainerHome =
    profile:
    profile.systemd.user.services ? docker
    && profile.systemd.user.services ? docker-proxy
    && profile.systemd.user.sockets ? docker
    && profile.systemd.user.services ? docker-prune
    && profile.systemd.user.timers ? docker-prune;
  noContainerHome =
    profile:
    !(profile.systemd.user.services ? docker)
    && !(profile.systemd.user.services ? docker-proxy)
    && !(profile.systemd.user.sockets ? docker)
    && !(profile.systemd.user.services ? docker-prune)
    && !(profile.systemd.user.timers ? docker-prune);
  results = {
    clientsDoNotStartLocalDaemonsOrGrantGroups =
      hasPackage (home clientsOnly "hostB" "alice") pkgs.docker
      && hasPackage (home clientsOnly "hostB" "alice") pkgs.mayonTui.docker
      && hasPackage (home clientsOnly "hostB" "bob") pkgs.virt-manager
      && !clientsHostB.virtualisation.docker.rootless.enable
      && !clientsHostB.virtualisation.libvirtd.enable
      && noContainerHome (home clientsOnly "hostB" "alice")
      && noContainerHome (home clientsOnly "hostB" "bob")
      && !((home clientsOnly "hostB" "alice").home.sessionVariables ? DOCKER_HOST)
      && !((home clientsOnly "hostB" "bob").home.sessionVariables ? DOCKER_HOST)
      && groups clientsHostB "alice" == [ ]
      && groups clientsHostB "bob" == [ ]
      && noEmbeddedRules clientsHostB;

    selectedBindingOwnsDockerAndVMServices =
      localHostA.virtualisation.docker.rootless.enable
      && !localHostA.virtualisation.docker.rootless.setSocketVariable
      && localHostA.systemd.user.services.docker.wantedBy == [ ]
      && localHostA.virtualisation.libvirtd.enable
      && localHostA.systemd.services.libvirtd.wantedBy == [ ]
      && localHostA.systemd.sockets.libvirtd.wantedBy == [ "sockets.target" ]
      && !localHostA.systemd.services.libvirt-guests.enable
      &&
        groups localHostA "alice" == [
          "dialout"
          "kvm"
          "libvirtd"
        ]
      && groups localHostA "bob" == [ ]
      && noContainerHome (home localOnly "hostA" "bob")
      && !((home localOnly "hostA" "bob").home.sessionVariables ? DOCKER_HOST)
      && !localHostB.virtualisation.docker.rootless.enable
      && !localHostB.virtualisation.libvirtd.enable
      && groups localHostB "alice" == [ ]
      && selectedContainerHome selectedAlice
      && selectedAlice.systemd.user.sockets.docker.Install.WantedBy == [ "sockets.target" ]
      && selectedAlice.systemd.user.services.docker-proxy.Unit.Requires == [ "docker.service" ]
      && selectedAlice.home.sessionVariables.DOCKER_HOST == "unix://$XDG_RUNTIME_DIR/docker.sock"
      && selectedAlice.systemd.user.services.docker.Install.WantedBy == [ ]
      &&
        selectedAlice.systemd.user.services.docker-prune.Service.ExecStart
        == [ "${pkgs.docker}/bin/docker --host unix://%t/docker.sock builder prune -f --filter until=168h" ]
      && selectedAlice.systemd.user.services.docker-prune.Service.Type == "oneshot"
      && selectedAlice.systemd.user.timers.docker-prune.Timer.Persistent
      && selectedAlice.systemd.user.timers.docker-prune.Install.WantedBy == [ "timers.target" ];

    sharedHostSupportIsDeduplicatedAndBound =
      sharedHostA.virtualisation.docker.rootless.enable
      && sharedHostA.systemd.user.services.docker.wantedBy == [ ]
      && sharedHostA.virtualisation.libvirtd.enable
      && sharedHostA.systemd.services.libvirtd.wantedBy == [ ]
      && sharedHostA.systemd.sockets.libvirtd.wantedBy == [ "sockets.target" ]
      && sharedHostA.systemd.services.libvirt-guests.enable == false
      && sharedHostA.services.udev.packages == localHostA.services.udev.packages
      && hasAllRules sharedHostA
      &&
        groups sharedHostA "alice" == [
          "dialout"
          "kvm"
          "libvirtd"
        ]
      &&
        groups sharedHostA "bob" == [
          "dialout"
          "kvm"
          "libvirtd"
        ]
      && selectedContainerHome sharedAlice
      && selectedContainerHome sharedBob
      && sharedAlice.systemd.user.services.docker.Install.WantedBy == [ ]
      && sharedBob.systemd.user.services.docker.Install.WantedBy == [ ]
      && sharedAlice.systemd.user.timers.docker-prune.Install.WantedBy == [ "timers.target" ]
      && sharedBob.systemd.user.timers.docker-prune.Install.WantedBy == [ "timers.target" ]
      && !hasAllRules (host sharedHost "hostB");

    removingFinalConsumerRemovesHostDaemonsButKeepsClients =
      !postRemovalHostA.virtualisation.docker.rootless.enable
      && !postRemovalHostA.virtualisation.libvirtd.enable
      && noEmbeddedRules postRemovalHostA
      && groups postRemovalHostA "alice" == [ ]
      && groups postRemovalHostA "bob" == [ ]
      && hasPackage (home afterLastLocalConsumerRemoved "hostB" "alice") pkgs.docker
      && hasPackage (home afterLastLocalConsumerRemoved "hostB" "bob") pkgs.virt-manager;
  };
  passed = lib.all (value: value) (builtins.attrValues results);
  report = pkgs.writeText "den-local-services-composition.json" (builtins.toJSON results);
in
assert lib.assertMsg passed
  "Local service composition failures: ${
    builtins.toJSON (lib.filterAttrs (_: value: !value) results)
  }";
pkgs.runCommand "den-local-services-composition" { } ''
  mkdir -p "$out"
  cp ${report} "$out/results.json"
''
