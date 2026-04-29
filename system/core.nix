{ ... }:
{
  # Boot
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

  # Virtualisation
  virtualisation.docker.enable = true;

  # Networking
  networking.hostName = "nixos-btw";
  networking.networkmanager.enable = true;
  networking.firewall = {
    trustedInterfaces = [ "Mihomo" ];
    extraReversePathFilterRules = ''
      iifname { "Mihomo" } accept comment "clash tun trusted"
    '';
  };
  networking.enableIPv6 = true;

  # Nix
  nix = {
    settings = {
      trusted-users = [ "root" "mayon" ];
      substituters = [
        "https://nix-community.cachix.org"
        "https://mirror.sjtu.edu.cn/nix-channels/store"
        "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
        "https://mirrors.ustc.edu.cn/nix-channels/store"
      ];
      trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };

  # Hardware & power
  zramSwap.enable = true;
  powerManagement.enable = true;
  services.thermald.enable = true;
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;

  # System
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