{
  inputs,
  pkgs,
  host,
}:
let
  evaluate =
    system: leak:
    (inputs.flake-parts.lib.mkFlake { inherit inputs; } (
      { den, ... }: {
        imports = [
          inputs.den.flakeModule
          ../../aspects
        ];
        den = {
          systems = [ system ];
          hosts.${system}.headless-fixture = { };
          aspects.headless-fixture = {
            includes = [
              den.aspects.system-maintenance
            ]
            ++ inputs.nixpkgs.lib.optional leak den.aspects.laptop-network;
            nixos = {
              system.stateVersion = "26.05";
              boot.loader.grub.enable = false;
              fileSystems."/" = {
                device = "none";
                fsType = "tmpfs";
              };
            };
          };
        };
      }
    )).nixosConfigurations.headless-fixture.config;
  inspect =
    system: leak:
    let
      c = evaluate system leak;
    in
    {
      maintenanceSelected = !c.nix.channel.enable;
      boundedStoreRetention =
        !c.nix.settings.keep-outputs
        && c.nix.optimise.automatic
        && !c.nix.settings.auto-optimise-store
        && c.programs.nh.clean.extraArgs == "--keep 5 --keep-since 14d"
        &&
          builtins.length (
            builtins.filter (
              key: pkgs.lib.hasPrefix "cache.nixos.org-1:" key
            ) c.nix.settings.trusted-public-keys
          ) == 1;
      sudoRsPolicy =
        c.security.sudo-rs.enable
        && !c.security.sudo.enable
        && c.security.sudo-rs.wheelNeedsPassword
        && !c.security.sudo-rs.execWheelOnly
        && c.security.sudo-rs.defaultOptions == [ "SETENV" ]
        && c.security.wrappers.sudo.source == "${c.security.sudo-rs.package}/bin/sudo";
      platform = c.nixpkgs.hostPlatform.system == system;
      noDesktop =
        !(c.programs ? mango)
        && !c.services.greetd.enable
        && !c.services.displayManager.gdm.enable
        && !c.services.xserver.enable;
      noGpu =
        !(builtins.elem "nvidia" c.services.xserver.videoDrivers)
        && !c.hardware.nvidia.prime.offload.enable
        && !c.hardware.nvidia.nvidiaPersistenced;
      noGraphics = !c.hardware.graphics.enable && c.hardware.graphics.extraPackages == [ ];
      noPersonalAccount = !(c.users.users ? mayon);
      noLaptopPower = !c.services.thermald.enable && !c.services.upower.enable && !c.services.scx.enable;
      noConservationGrant = !(c.users.groups ? legion-conservation);
      noProxy = !(c.systemd.services.nix-daemon.environment ? https_proxy);
      noTunTrust = builtins.all (i: !(builtins.elem i c.networking.firewall.trustedInterfaces)) [
        "Meta"
        "Mihomo"
      ];
      noPersonalTrust = !(builtins.elem "mayon" c.nix.settings.trusted-users);
      noSecrets = !(c ? sops);
      noInboundSsh = !c.services.openssh.enable && c.networking.firewall.allowedTCPPorts == [ ];
    };
  results = {
    x86 = inspect "x86_64-linux" false;
    arm = inspect "aarch64-linux" false;
    laptop = {
      clashServiceOwnsTun =
        host.programs.clash-verge.serviceMode
        && !host.programs.clash-verge.autoStart
        && !host.programs.clash-verge.tunMode
        && !(host.security.wrappers ? clash-verge)
        && host.systemd.services.clash-verge.enable;
      stableDefaultKernel = host.boot.kernelPackages.kernel.drvPath == pkgs.linuxPackages.kernel.drvPath;
      matchingStableNvidia =
        host.hardware.nvidia.package.drvPath == host.boot.kernelPackages.nvidiaPackages.stable.drvPath;
      lavdWithoutAutopower =
        host.services.scx.enable
        && host.services.scx.scheduler == "scx_lavd"
        && builtins.all (arg: !(pkgs.lib.hasInfix "--autopower" arg)) host.services.scx.extraArgs;
      singleOomPolicy =
        host.services.earlyoom.enable
        && !host.systemd.oomd.enable
        && host.services.earlyoom.freeMemThreshold == 5
        && host.services.earlyoom.freeSwapThreshold == 10;
      zramReclaim =
        host.zramSwap.enable
        && host.zramSwap.algorithm == "zstd"
        && host.zramSwap.memoryPercent == 50
        && host.boot.kernel.sysctl."vm.swappiness" == 100
        && host.boot.kernel.sysctl."vm.page-cluster" == 0;
      buildConcurrency = host.nix.settings.max-jobs == 2 && host.nix.settings.cores == 8;
      ext4ReadPolicy =
        host.fileSystems."/".fsType == "ext4"
        && builtins.elem "noatime" host.fileSystems."/".options
        && host.services.fstrim.enable;
      localSshOnly =
        host.services.openssh.enable
        && host.services.openssh.startWhenNeeded
        && !host.services.openssh.openFirewall
        &&
          map (address: address.addr) host.services.openssh.listenAddresses == [
            "127.0.0.1"
            "[::1]"
          ]
        &&
          host.systemd.sockets.sshd.socketConfig.ListenStream == [
            "127.0.0.1:22"
            "[::1]:22"
          ];
    };
  };
  rejectsLaptopNetwork = !(builtins.all (v: v) (builtins.attrValues (inspect "x86_64-linux" true)));
  passed =
    rejectsLaptopNetwork
    && builtins.all (r: builtins.all (v: v) (builtins.attrValues r)) (builtins.attrValues results);
in
assert passed;
pkgs.writeText "den-system-boundaries.json" (
  builtins.toJSON (results // { inherit rejectsLaptopNetwork; })
)
