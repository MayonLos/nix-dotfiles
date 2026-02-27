{
  pkgs,
  ...
}:

{
  boot.kernelPackages = pkgs.linuxPackages_zen;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = [ "ntfs" ];

  virtualisation.docker.enable = true;

  networking.hostName = "nixos-btw";
  networking.networkmanager.enable = true;

  nix.settings = {
    trusted-users = [
      "root"
      "mayon"
    ];
    substituters = [
      "https://mirrors.ustc.edu.cn/nix-channels/store"
      "https://cache.nixos.org"
    ];
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  zramSwap.enable = true;

  powerManagement.enable = true;
  services.thermald.enable = true;

  services.auto-cpufreq.enable = true;
  services.auto-cpufreq.settings = {
    charger = {
      governor = "performance";
      turbo = "auto";
    };
    battery = {
      governor = "powersave";
      turbo = "never";
    };
  };

  time.timeZone = "Asia/Shanghai";

  services.openssh.enable = true;

  system.stateVersion = "25.11";
}
