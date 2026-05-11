{ config, ... }: {
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
  ];
  boot.consoleLogLevel = 3;
  boot.initrd.systemd.enable = true;

  virtualisation.docker.enable = true;

  zramSwap = { enable = true; algorithm = "zstd"; };
  powerManagement.enable = true;
}
