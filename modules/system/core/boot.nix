{ ... }:
{
  boot.kernelModules = [ "tun" ];
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 30;
  };
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = [ "ntfs" ];
  boot.kernelParams = [ "quiet" "udev.log_level=3" ];
  boot.consoleLogLevel = 3;
  boot.initrd.systemd.enable = true;

  virtualisation.docker.enable = true;

  zramSwap.enable = true;
  powerManagement.enable = true;
}
