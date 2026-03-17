{
  pkgs,
  ...
}:

{
  boot.kernelPackages = pkgs.linuxPackages_zen;

  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 30;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = [ "ntfs" ];
  boot.initrd.verbose = false;
  boot.consoleLogLevel = 3;
  boot.kernelParams = [
    "quiet"
    "udev.log_level=3"
  ];

  virtualisation.docker = {
    enable = true;
  };

  networking.hostName = "nixos-btw";
  networking.networkmanager.enable = true;

  nix.settings = {
    trusted-users = [
      "root"
      "mayon"
    ];
    # Prefer widely used community builds first; official cache remains as fallback.
    substituters = [
      "https://nix-community.cachix.org"
      "https://mirror.sjtu.edu.cn/nix-channels/store"
      "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
      "https://mirrors.ustc.edu.cn/nix-channels/store"
    ];
    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  zramSwap.enable = true;

  powerManagement.enable = true;
  services.thermald.enable = true;

  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;

  time.timeZone = "Asia/Shanghai";

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  system.stateVersion = "25.11";
}
