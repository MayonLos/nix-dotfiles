{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./system/default.nix
    ./system/program/default.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = [ "ntfs" ];
  virtualisation.docker.enable = true;

  networking.hostName = "nixos-btw";

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

  systemd.services.nix-daemon.environment = {
  https_proxy = "http://127.0.0.1:7890";
  http_proxy = "http://127.0.0.1:7890";
};

  # services.flatpak.enable = true;

  # systemd.services.flatpak-repo = {
  #   wantedBy = [ "multi-user.target" ];
  #   path = [ pkgs.flatpak ];
  #   script = ''
  #           flatpak remote-add --if-not-exists flathub \
  #     https://flathub.org/repo/flathub.flatpakrepo
  #   '';
  # };

  networking.networkmanager.enable = true;

  zramSwap.enable = true;

  hardware.graphics.enable = true;

  services.xserver.videoDrivers = [
    "nvidia"
  ];

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = false;
    powerManagement.finegrained = false;
    open = false;
    nvidiaSettings = true;
    forceFullCompositionPipeline = true;

    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Experimental = true;
        FastConnectable = true;
      };
      Policy = {
        AutoEnable = true;
      };
    };
  };

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

  services.xserver = {
    enable = true;
    autoRepeatDelay = 200;
    autoRepeatInterval = 35;
    dpi = 144;
  };

  services.xserver.desktopManager.runXdgAutostartIfNone = true;
  services.xserver.exportConfiguration = true;
  services.xserver.displayManager.startx.enable = true;

  services.greetd = {
    enable = true;
    useTextGreeter = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --xsession-wrapper '${pkgs.xorg.xinit}/bin/startx ${pkgs.coreutils}/bin/env' --sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions --xsessions ${config.services.displayManager.sessionData.desktops}/share/xsessions";
      };
    };
  };

  services.xserver.windowManager.dwm = {
    enable = true;
    package = pkgs.dwm.overrideAttrs (old: {
      src = ./home/dwm;

      buildInputs =
        (old.buildInputs or [ ])
        ++ (with pkgs.xorg; [
          libXcursor
        ]);
    });
  };

  users.users.mayon = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "gamemode"
      "input"
    ];
    shell = pkgs.zsh;
    packages = with pkgs; [
      tree
    ];
  };

  programs.niri.enable = true;
  programs.niri.package = pkgs.niri.overrideAttrs (old: {
    postFixup = (old.postFixup or "") + ''
      substituteInPlace "$out/bin/niri-session" \
        --replace-fail \
        "systemctl --user import-environment" \
        "import_vars=\"\"; for v in WAYLAND_DISPLAY DISPLAY XDG_SESSION_TYPE XDG_CURRENT_DESKTOP NIRI_SOCKET XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS; do if printenv \"\$v\" >/dev/null 2>&1; then import_vars=\"\$import_vars \$v\"; fi; done; [ -n \"\$import_vars\" ] && systemctl --user import-environment \$import_vars"
    '';
  });
  programs.gamemode.enable = true;
  programs.thunar.enable = true;
  programs.xfconf.enable = true;
  programs.dconf.enable = true;
  services.dbus.enable = true;

  programs.thunar.plugins = with pkgs.xfce; [
    thunar-archive-plugin
    thunar-volman
  ];

  services.gvfs.enable = true;
  services.tumbler.enable = true;
  services.udisks2.enable = true;
  services.openssh.enable = true;

  services.pipewire = {
    enable = true;
    alsa = {
      enable = true;
      support32Bit = true;
    };
    pulse.enable = true;
    wireplumber.enable = true;
    jack.enable = true;
  };

  security.rtkit.enable = true;

  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    lshw
    btop
  ];

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };

  fonts = {
    packages = with pkgs; [
      nerd-fonts.jetbrains-mono
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      noto-fonts-color-emoji
      wqy_zenhei
    ];
    fontconfig = {
      antialias = true;
      hinting.enable = true;
      defaultFonts = {
        emoji = [ "Noto Color Emoji" ];
        monospace = [ "JetBrains Mono Nerd Font" ];
        sansSerif = [ "Noto Sans CJK SC" ];
        serif = [ "Noto Serif CJK SC" ];
      };
    };
  };

  system.stateVersion = "25.11";
}
