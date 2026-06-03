{ config, pkgs, ... }: {
  boot.kernelPackages = pkgs.linuxPackages_zen;
  boot.kernelModules = [ "tun" "legion_laptop" ];
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
  boot.kernelParams = [
    "quiet"
    "udev.log_level=3"
    "split_lock_detect=off" # 减少某些游戏因原子操作导致的性能损耗
  ];
  boot.consoleLogLevel = 3;
  boot.initrd.systemd.enable = true;

  boot.kernel.sysctl = {
    "vm.max_map_count" = 2147483642; # 适配某些需要大量内存映射的游戏
  };

  virtualisation.docker.enable = true;

  zramSwap = { enable = true; algorithm = "zstd"; };
  powerManagement.enable = true;
}
