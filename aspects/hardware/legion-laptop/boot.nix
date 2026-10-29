{
  config,
  lib,
  pkgs,
  ...
}:
{
  assertions = [
    {
      assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
      message = "legion-laptop requires the verified x86_64-linux platform";
    }
  ];
  boot = {
    # Keep the LTS kernel and NVIDIA driver on stable's matching package set,
    # without a cross-channel driver recipe. sched_ext is available since 6.12;
    # scx provides the interactive scheduling policy instead of linux-zen.
    kernelPackages = pkgs.linuxPackages;
    kernelModules = [
      "tun"
      "legion_laptop"
    ];
    extraModulePackages = [ config.boot.kernelPackages.lenovo-legion-module ];
    extraModprobeConfig = ''
      options legion_laptop force=1
    '';
    loader = {
      timeout = 1;
      systemd-boot = {
        enable = true;
        configurationLimit = 30;
        consoleMode = "max";
        editor = false;
      };
      efi.canTouchEfiVariables = true;
    };
    supportedFilesystems = [ "ntfs" ];
    initrd = {
      systemd.enable = true;
      verbose = false;
      # Early KMS on the panel's iGPU; keep the offload-only NVIDIA in stage 2.
      kernelModules = [ "i915" ];
    };
    plymouth = {
      enable = true;
      theme = "bgrt";
    };

    tmp.useTmpfs = true;
    kernelParams = [
      "quiet"
      # udev.log_level applies in both stages. PID 1 likewise reads the
      # unprefixed show_status in initrd; rd.systemd.show_status is unsupported.
      "udev.log_level=3"
      "systemd.show_status=auto"
      "split_lock_detect=off"
    ];
    consoleLogLevel = 3;
    kernel.sysctl = {
      "vm.max_map_count" = 2147483642;
      "net.core.default_qdisc" = "fq";
      "net.ipv4.tcp_congestion_control" = "bbr";
    };
  };

  console = {
    earlySetup = true;
    # 16x32 cells give a readable 160x50 TTY on the 2560x1600 internal panel.
    font = "ter-v32n";
    packages = [ pkgs.terminus_font ];
  };

  # tmpfs /tmp is too small for large nixpkgs builds, so the daemon builds in /var/tmp
  systemd.services.nix-daemon.environment.TMPDIR = "/var/tmp";

  # Avoid access-time writes for source trees and store reads. Keep filesystem
  # identity in inventory's scan; only this laptop's ext4 policy belongs here.
  fileSystems."/".options = lib.mkIf (config.fileSystems."/".fsType == "ext4") [ "noatime" ];
  powerManagement.enable = true;
}
