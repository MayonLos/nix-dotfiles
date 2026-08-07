{ config, pkgs, ... }:
{
  boot = {
    kernelPackages = pkgs.linuxPackages_zen;
    kernelModules = [
      "tun"
      "legion_laptop"
    ];
    extraModulePackages = [ config.boot.kernelPackages.lenovo-legion-module ];
    extraModprobeConfig = ''
      options legion_laptop force=1
    '';
    loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 30;
      };
      efi.canTouchEfiVariables = true;
    };
    supportedFilesystems = [ "ntfs" ];

    tmp.useTmpfs = true;
    kernelParams = [
      "quiet"
      "udev.log_level=3"
      "split_lock_detect=off"
    ];
    consoleLogLevel = 3;
    kernel.sysctl = {
      "vm.max_map_count" = 2147483642;
      "net.core.default_qdisc" = "fq";
      "net.ipv4.tcp_congestion_control" = "bbr";
    };
  };

  # tmpfs /tmp is too small for large nixpkgs builds, so the daemon builds in /var/tmp
  systemd.services.nix-daemon.environment.TMPDIR = "/var/tmp";

  zramSwap = {
    enable = true;
    algorithm = "zstd";
  };
  powerManagement.enable = true;
}
