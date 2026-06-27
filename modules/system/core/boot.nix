{ config, pkgs, ... }:
{
  boot.kernelPackages = pkgs.linuxPackages_zen;
  boot.kernelModules = [
    "tun"
    "legion_laptop"
  ];
  boot.extraModulePackages = [ config.boot.kernelPackages.lenovo-legion-module ];
  boot.extraModprobeConfig = ''
    options legion_laptop force=1
  '';
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 30;
  };
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = [ "ntfs" ];

  # Wipe /tmp on every boot. It lives on the ext4 root, so without this it would
  # persist across reboots and accumulate junk. Kept on disk (not tmpfs) so large
  # nix/compiler builds don't eat into RAM.
  boot.tmp.cleanOnBoot = true;
  boot.kernelParams = [
    "quiet"
    "udev.log_level=3"
    "split_lock_detect=off"
  ];
  boot.consoleLogLevel = 3;
  boot.kernel.sysctl = {
    "vm.max_map_count" = 2147483642;
    "net.core.default_qdisc" = "fq";
    "net.ipv4.tcp_congestion_control" = "bbr";
  };

  zramSwap = {
    enable = true;
    algorithm = "zstd";
  };
  powerManagement.enable = true;
}
