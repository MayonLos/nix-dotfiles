# Nix Dotfiles 目录结构重构 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将现有 nix-dotfiles 迁移到 flake-parts 标准化目录结构，引入 `flake-parts` + `home-manager.flakeModules.home-manager` + `treefmt-nix` 三个新依赖，重组所有文件到 `flake/`、`hosts/`、`modules/`、`lib/`、`flakeModules/` 五层架构。

**Architecture:** flake-parts 模块系统拆分 flake.nix → `flake/{system,home,dev}.nix`，`withSystem` 桥接 perSystem pkgs 到 nixosSystem，旧 `host/`/`home/`/`system/` 按 NixOS/HM 边界重组到 `modules/{system,home}/`，`dev/cuda/` 合并到 `perSystem.devShells`，`_assets/` 前缀防 glob 导入壁纸等静态资源。

**Tech Stack:** Nix flakes, flake-parts, home-manager (release-25.11), treefmt-nix, nixpkgs 25.11

**Spec:** `docs/superpowers/specs/2026-04-29-nix-config-restructure-design.md`

---

### Task 1: Create new directory structure

**Files:**
- Create: all directories (no files yet)

- [ ] **Step 1: Create all directories at once**

```bash
mkdir -p /home/mayon/nix-dotfiles/{flake,hosts/nixos-btw}
mkdir -p /home/mayon/nix-dotfiles/modules/system/{core,desktop,hardware,programs,security,services,users}
mkdir -p /home/mayon/nix-dotfiles/modules/home/{users/mayon,base,packages.nix,wm/niri,programs/{apps,dev,terminal},shell,services,_assets/wallpaper}
mkdir -p /home/mayon/nix-dotfiles/{lib,flakeModules}
```

Wait, `packages.nix` is a file not a directory. Let me fix:

```bash
mkdir -p /home/mayon/nix-dotfiles/{flake,hosts/nixos-btw}
mkdir -p /home/mayon/nix-dotfiles/modules/system/{core,desktop,hardware,programs,security,services,users}
mkdir -p /home/mayon/nix-dotfiles/modules/home/{users/mayon,base,wm/niri,programs/{apps,dev,terminal},shell,services,_assets/wallpaper}
mkdir -p /home/mayon/nix-dotfiles/{lib,flakeModules}
```

- [ ] **Step 2: Verify directories exist**

```bash
find /home/mayon/nix-dotfiles/{flake,hosts,modules,lib,flakeModules} -type d | sort
```

- [ ] **Step 3: Commit**

```bash
git add flake/ hosts/ modules/ lib/ flakeModules/
git commit -m "$(cat <<'EOF'
feat: scaffold new flake-parts directory structure

Create flake/, hosts/nixos-btw/, modules/{system,home}/, lib/, flakeModules/
directories for the flake-parts restructure.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Rewrite flake.nix with flake-parts

**Files:**
- Modify: `flake.nix`

- [ ] **Step 1: Write the new flake.nix**

Replace the current `flake.nix` with:

```nix
{
  description = "NixOS from Scratch";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    MyNixvim = {
      url = "github:MayonLos/nixvim";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    niri.url = "github:sodiboo/niri-flake";

    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
      inputs.noctalia-qs.follows = "noctalia-qs";
    };

    noctalia-qs = {
      url = "github:noctalia-dev/noctalia-qs";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    claude-code.url = "github:sadjow/claude-code-nix/v2";

    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];
      imports = [
        ./flake/system.nix
        ./flake/home.nix
        ./flake/dev.nix
        inputs.home-manager.flakeModules.home-manager
        inputs.treefmt-nix.flakeModule
      ];
    };
}
```

- [ ] **Step 2: Verify syntax**

```bash
nix eval --file flake.nix
```

- [ ] **Step 3: Commit**

```bash
git add flake.nix
git commit -m "$(cat <<'EOF'
feat: rewrite flake.nix with flake-parts + treefmt-nix

Replace raw nixosSystem outputs with flake-parts mkFlake, adding
home-manager flakeModules and treefmt-nix flakeModule.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Create flake/system.nix (nixosConfigurations)

**Files:**
- Create: `flake/system.nix`

- [ ] **Step 1: Write flake/system.nix**

```nix
{ withSystem, inputs, ... }:
let
  pkgs-unstable-for = system:
    import inputs.nixpkgs-unstable {
      inherit system;
      config.allowUnfree = true;
      overlays = [ inputs.claude-code.overlays.default ];
    };
in
{
  flake.nixosConfigurations.nixos-btw = withSystem "x86_64-linux" (
    { pkgs, ... }:
    inputs.nixpkgs.lib.nixosSystem {
      inherit pkgs;
      specialArgs = {
        inherit inputs;
        pkgs-unstable = pkgs-unstable-for "x86_64-linux";
      };
      modules = [
        inputs.niri.nixosModules.niri
        ./hosts/nixos-btw
        inputs.home-manager.nixosModules.home-manager
        {
          nixpkgs.config.allowUnfree = true;
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = {
              inherit inputs;
              pkgs-unstable = pkgs-unstable-for "x86_64-linux";
            };
            users.mayon = import ./modules/home/users/mayon;
            backupFileExtension = "backup";
          };
        }
      ];
    }
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add flake/system.nix
git commit -m "$(cat <<'EOF'
feat: add flake/system.nix with nixosConfigurations via withSystem

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Create flake/home.nix and flake/dev.nix

**Files:**
- Create: `flake/home.nix`
- Create: `flake/dev.nix`

- [ ] **Step 1: Write flake/home.nix (placeholder)**

```nix
{ ... }:
{
  flake.homeConfigurations = { };
}
```

- [ ] **Step 2: Write flake/dev.nix (devShells + treefmt)**

```nix
{ ... }:
{
  perSystem = { pkgs, ... }: {
    devShells = {
      cuda = pkgs.mkShell {
        name = "cuda-dev";
        packages = with pkgs; [
          cudaPackages.cudatoolkit
          cudaPackages.cudnn
          linuxKernel.packages.linux_zen.nvidia_x11
        ];
        shellHook = ''
          export CUDA_PATH=${pkgs.cudaPackages.cudatoolkit}
        '';
      };
      default = pkgs.mkShell {
        name = "default-dev";
        packages = with pkgs; [
          git
          gnumake
          clang-tools
        ];
      };
    };

    treefmt = {
      projectRootFile = "flake.nix";
      programs = {
        nixfmt.enable = true;
        deadnix.enable = true;
        statix.enable = true;
      };
    };
  };
}
```

- [ ] **Step 3: Commit**

```bash
git add flake/home.nix flake/dev.nix
git commit -m "$(cat <<'EOF'
feat: add flake/home.nix placeholder and flake/dev.nix with devShells + treefmt

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Create hosts layer

**Files:**
- Create: `hosts/nixos-btw/default.nix`
- Create: `hosts/nixos-btw/hardware.nix`

- [ ] **Step 1: Write hosts/nixos-btw/default.nix (host assembly)**

```nix
{
  ...
}:

{
  imports = [
    ./hardware.nix
    ../../modules/system/core
    ../../modules/system/desktop
    ../../modules/system/hardware
    ../../modules/system/programs
    ../../modules/system/security
    ../../modules/system/services
    ../../modules/system/users
  ];
}
```

- [ ] **Step 2: Write hosts/nixos-btw/hardware.nix**

Copy from `hardware-configuration.nix`:

```nix
# Do not modify this file!  It was generated by 'nixos-generate-config'
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "/dev/disk/by-uuid/de6a3148-3a4b-4ea4-9c4e-3e7a74fa769b";
      fsType = "ext4";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/BA85-C8C4";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
```

- [ ] **Step 3: Commit**

```bash
git add hosts/
git commit -m "$(cat <<'EOF'
feat: add hosts layer (nixos-btw assembly + hardware config)

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Migrate modules/system/core (from system/)

**Files:**
- Create: `modules/system/core/default.nix`
- Create: `modules/system/core/boot.nix`
- Create: `modules/system/core/network.nix`
- Create: `modules/system/core/nix.nix`
- Create: `modules/system/core/locale.nix`

- [ ] **Step 1: Write modules/system/core/default.nix**

```nix
{
  ...
}:

{
  imports = [
    ./boot.nix
    ./network.nix
    ./nix.nix
    ./locale.nix
  ];
}
```

- [ ] **Step 2: Write modules/system/core/boot.nix**

Extracted from `system/core.nix` (boot + zram + virtualisation):

```nix
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
```

- [ ] **Step 3: Write modules/system/core/network.nix**

Extracted from `system/core.nix` (networking section):

```nix
{ ... }:
{
  networking.hostName = "nixos-btw";
  networking.networkmanager.enable = true;
  networking.firewall = {
    trustedInterfaces = [ "Mihomo" ];
    extraReversePathFilterRules = ''
      iifname { "Mihomo" } accept comment "clash tun trusted"
    '';
  };
  networking.enableIPv6 = true;
}
```

- [ ] **Step 4: Write modules/system/core/nix.nix**

Extracted from `system/core.nix` (nix section):

```nix
{ ... }:
{
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
}
```

- [ ] **Step 5: Write modules/system/core/locale.nix**

Extracted from `system/core.nix` (time + stateVersion):

```nix
{ ... }:
{
  time.timeZone = "Asia/Shanghai";
  system.stateVersion = "25.11";
}
```

- [ ] **Step 6: Commit**

```bash
git add modules/system/core/
git commit -m "$(cat <<'EOF'
feat: migrate system/core config into modules/system/core/

Split the old system/core.nix monolith into boot/network/nix/locale modules.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Migrate modules/system/desktop (from system/)

**Files:**
- Create: `modules/system/desktop/default.nix`
- Create: `modules/system/desktop/niri.nix`
- Create: `modules/system/desktop/gamemode.nix`
- Create: `modules/system/desktop/xdg.nix`

- [ ] **Step 1: Write modules/system/desktop/default.nix**

```nix
{
  ...
}:

{
  imports = [
    ./niri.nix
    ./gamemode.nix
    ./xdg.nix
  ];
}
```

- [ ] **Step 2: Write modules/system/desktop/niri.nix**

From `system/desktop-session.nix` (niri section only):

```nix
{
  config,
  pkgs,
  ...
}:

{
  programs.niri.enable = true;
  programs.niri.package = pkgs.niri.overrideAttrs (old: {
    postFixup = (old.postFixup or "") + ''
      substituteInPlace "$out/bin/niri-session" \
        --replace-fail \
        "systemctl --user import-environment" \
        "import_vars=\"\"; for v in WAYLAND_DISPLAY DISPLAY XDG_SESSION_TYPE XDG_CURRENT_DESKTOP NIRI_SOCKET XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS; do if printenv \"\$v\" >/dev/null 2>&1; then import_vars=\"\$import_vars \$v\"; fi; done; [ -n \"\$import_vars\" ] && systemctl --user import-environment \$import_vars"
    '';
  });
}
```

- [ ] **Step 3: Write modules/system/desktop/gamemode.nix**

From `system/desktop-session.nix` (gamemode section only):

```nix
{ ... }:

{
  programs.gamemode.enable = true;
}
```

- [ ] **Step 4: Write modules/system/desktop/xdg.nix**

From `system/xdg.nix`:

```nix
{ pkgs, ... }:
{
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gnome
      xdg-desktop-portal-gtk
    ];
    config = {
      niri = {
        default = [
          "gnome"
          "gtk"
        ];
        "org.freedesktop.impl.portal.FileChooser" = "gtk";
        "org.freedesktop.impl.portal.ScreenCast" = "gnome";
        "org.freedesktop.impl.portal.Screenshot" = "gnome";
        "org.freedesktop.impl.portal.Settings" = "gnome";
        "org.freedesktop.impl.portal.Inhibit" = "gnome";
      };
      common.default = "gnome";
    };
  };
}
```

- [ ] **Step 5: Commit**

```bash
git add modules/system/desktop/
git commit -m "$(cat <<'EOF'
feat: migrate desktop config into modules/system/desktop/

Split desktop-session.nix into niri/gamemode, move system/xdg.nix into desktop/xdg.nix.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Migrate modules/system/hardware (from system/)

**Files:**
- Create: `modules/system/hardware/default.nix`
- Create: `modules/system/hardware/gpu.nix`
- Create: `modules/system/hardware/bluetooth.nix`
- Create: `modules/system/hardware/audio.nix`
- Create: `modules/system/hardware/cuda.nix`
- Create: `modules/system/hardware/firmware.nix`

- [ ] **Step 1: Write modules/system/hardware/default.nix**

```nix
{
  ...
}:

{
  imports = [
    ./gpu.nix
    ./bluetooth.nix
    ./audio.nix
    ./cuda.nix
    ./firmware.nix
  ];
}
```

- [ ] **Step 2: Write modules/system/hardware/gpu.nix**

From `system/hardware.nix` (nvidia section):

```nix
{ ... }:

{
  hardware.graphics.enable = true;

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
}
```

- [ ] **Step 3: Write modules/system/hardware/bluetooth.nix**

From `system/hardware.nix` (bluetooth section):

```nix
{ ... }:

{
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
}
```

- [ ] **Step 4: Write modules/system/hardware/audio.nix**

From `system/audio.nix`:

```nix
{ ... }:

{
  services.pipewire = {
    enable = true;
    alsa = {
      enable = true;
      support32Bit = true;
    };
    pulse.enable = true;
    wireplumber.enable = true;
    jack.enable = true;
    extraConfig = {
      pipewire."90-echo-cancel" = {
        "context.modules" = [
          {
            name = "libpipewire-module-echo-cancel";
            args = {
              "library.name" = "aec/libspa-aec-webrtc";
              "source.props" = {
                "node.name" = "echo_cancelled_source";
                "node.description" = "Echo Cancelled Source";
              };
              "sink.props" = {
                "node.name" = "echo_cancelled_sink";
                "node.description" = "Echo Cancelled Sink";
              };
            };
          }
        ];
      };

      pipewire-pulse."91-qq-wechat-compat" = {
        "pulse.rules" = [
          {
            matches = [
              { "application.process.binary" = "qq"; }
              { "application.process.binary" = "~wechat.*"; }
            ];
            actions = {
              quirks = [ "force-s16-info" ];
            };
          }
        ];
      };
    };
  };

  security.rtkit.enable = true;
}
```

- [ ] **Step 5: Write modules/system/hardware/cuda.nix**

From `system/cuda.nix`:

```nix
{
  lib,
  ...
}:

{
  nix.settings = {
    substituters = lib.mkAfter [
      "https://cache.nixos-cuda.org"
    ];
    trusted-public-keys = lib.mkAfter [
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    ];
  };

  nixpkgs.config.cudaSupport = lib.mkDefault false;
}
```

- [ ] **Step 6: Write modules/system/hardware/firmware.nix**

CPU microcode placeholder (referenced by `hosts/nixos-btw/hardware.nix`):

```nix
{ ... }:
{
  hardware.enableRedistributableFirmware = true;
}
```

- [ ] **Step 7: Commit**

```bash
git add modules/system/hardware/
git commit -m "$(cat <<'EOF'
feat: migrate hardware config into modules/system/hardware/

Split into gpu/bluetooth/audio/cuda/firmware modules.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Migrate modules/system/programs (from system/program/)

**Files:**
- Create: `modules/system/programs/default.nix`
- Create: `modules/system/programs/libreoffice.nix`
- Create: `modules/system/programs/thunar.nix`
- Create: `modules/system/programs/gamescope.nix`
- Create: `modules/system/programs/zsh.nix`
- Create: `modules/system/programs/clash.nix`

- [ ] **Step 1: Write modules/system/programs/default.nix**

```nix
{
  ...
}:

{
  imports = [
    ./libreoffice.nix
    ./thunar.nix
    ./gamescope.nix
    ./zsh.nix
    ./clash.nix
  ];
}
```

- [ ] **Step 2: Write modules/system/programs/libreoffice.nix**

Same content as `system/program/desktop/libreoffice.nix`:

```nix
{
  pkgs,
  ...
}:

{
  environment.systemPackages = with pkgs; [
    libreoffice-qt
    hunspell
    hunspellDicts.en_US
    hyphenDicts.en_US
  ];
}
```

- [ ] **Step 3: Write modules/system/programs/thunar.nix**

Same content as `system/program/desktop/thunar.nix`:

```nix
{
  pkgs,
  ...
}:

{
  programs.thunar = {
    enable = true;
    plugins = with pkgs.xfce; [
      thunar-archive-plugin
      thunar-volman
    ];
  };

  programs.xfconf.enable = true;
  programs.dconf.enable = true;
  services.dbus.enable = true;

  services.gvfs.enable = true;
  services.tumbler.enable = true;
  services.udisks2.enable = true;
}
```

- [ ] **Step 4: Write modules/system/programs/gamescope.nix**

Same content as `system/program/gaming/gamescope.nix`:

```nix
{
  pkgs,
  ...
}:

{
  programs.gamescope = {
    enable = true;
    package = pkgs.gamescope;
  };
}
```

- [ ] **Step 5: Write modules/system/programs/zsh.nix**

Same content as `system/program/shell/zsh.nix`:

```nix
{ ... }:

{
  programs.zsh.enable = true;
}
```

- [ ] **Step 6: Write modules/system/programs/clash.nix**

Same content as `system/program/tools/clash.nix`:

```nix
{ pkgs, ... }:
{
  programs.clash-verge = {
    enable      = true;
    serviceMode = true;
    tunMode     = true;
  };

  services.resolved = {
    enable      = true;
    extraConfig = ''
      DNSStubListener=no
    '';
  };
}
```

- [ ] **Step 7: Commit**

```bash
git add modules/system/programs/
git commit -m "$(cat <<'EOF'
feat: migrate system-level programs into modules/system/programs/

Flatten desktop/gaming/shell/tools subdirectories into flat programs/ directory.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: Migrate modules/system/security and services

**Files:**
- Create: `modules/system/security/default.nix`
- Create: `modules/system/services/default.nix`

- [ ] **Step 1: Write modules/system/security/default.nix**

Extracted from `system/core.nix` (openssh section) plus polkit:

```nix
{ ... }:

{
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  security.polkit.enable = true;
}
```

- [ ] **Step 2: Write modules/system/services/default.nix**

Extracted from `system/core.nix` (thermald, upower, power-profiles):

```nix
{ ... }:

{
  services.thermald.enable = true;
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;
}
```

- [ ] **Step 3: Commit**

```bash
git add modules/system/security/ modules/system/services/
git commit -m "$(cat <<'EOF'
feat: add modules/system/security and services layers

Extract sshd + polkit to security, thermald + upower to services.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: Migrate modules/system/users

**Files:**
- Create: `modules/system/users/default.nix`

- [ ] **Step 1: Write modules/system/users/default.nix**

From `system/user.nix` (user definition) + `system/environment.nix` (systemPackages + fonts):

```nix
{
  pkgs,
  ...
}:

{
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

  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    lshw
    btop
  ];

  fonts = {
    packages = with pkgs; [
      lmodern
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
}
```

- [ ] **Step 2: Commit**

```bash
git add modules/system/users/
git commit -m "$(cat <<'EOF'
feat: add modules/system/users with user + env + fonts config

Merge system/user.nix and system/environment.nix into users/default.nix.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: Migrate modules/home/users/mayon (HM entry point)

**Files:**
- Create: `modules/home/users/mayon/default.nix`

- [ ] **Step 1: Write modules/home/users/mayon/default.nix**

Adapted from `host/home.nix` with updated import paths:

```nix
{
  ...
}:

{
  imports = [
    ../../wm/niri
    ../../services
    ../../programs
    ../../shell
    ../../base
    ../../packages.nix
  ];
}
```

- [ ] **Step 2: Commit**

```bash
git add modules/home/users/
git commit -m "$(cat <<'EOF'
feat: add modules/home/users/mayon HM entry point

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 13: Migrate modules/home/base (from host/home/)

**Files:**
- Create: `modules/home/base/default.nix`
- Create: `modules/home/base/user.nix`
- Create: `modules/home/base/session-vars.nix`
- Create: `modules/home/base/input-method.nix`
- Create: `modules/home/base/ui.nix`
- Create: `modules/home/base/xdg.nix`

- [ ] **Step 1: Write modules/home/base/default.nix**

```nix
{
  ...
}:

{
  imports = [
    ./user.nix
    ./session-vars.nix
    ./input-method.nix
    ./ui.nix
    ./xdg.nix
  ];
}
```

- [ ] **Step 2: Write modules/home/base/user.nix**

From `host/home/base.nix`:

```nix
{ ... }:

{
  home.username = "mayon";
  home.homeDirectory = "/home/mayon";
  home.stateVersion = "25.11";
}
```

- [ ] **Step 3: Write modules/home/base/session-vars.nix**

Extracted from `host/home/base.nix` (sessionVariables):

```nix
{ ... }:

{
  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };
}
```

- [ ] **Step 4: Write modules/home/base/input-method.nix**

From `host/home/input-method.nix` (with updated Rime path — `home.file` stays same since it's in HM context):

```nix
{
  pkgs,
  ...
}:

{
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.waylandFrontend = true;
    fcitx5.addons = with pkgs; [
      (fcitx5-rime.override {
        rimeDataPkgs = [
          pkgs.rime-ice
        ];
      })
      fcitx5-nord
      fcitx5-gtk
      libsForQt5.fcitx5-qt
      qt6Packages.fcitx5-configtool
    ];

    fcitx5.settings.inputMethod = {
      "Groups/0" = {
        Name = "Default";
        "Default Layout" = "us";
        DefaultIM = "rime";
      };
      "Groups/0/Items/0".Name = "keyboard-us";
      "Groups/0/Items/1".Name = "rime";
    };

    fcitx5.settings.addons.classicui.globalSection = {
      Theme = "Nord-Dark";
      DarkTheme = "Nord-Dark";
    };
  };

  home.file.".local/share/fcitx5/rime/default.custom.yaml".text = ''
    patch:
      __include: rime_ice_suggestion:/

      schema_list:
        - schema: rime_ice

      menu/page_size: 9

      key_binder/bindings/+:
        - { when: paging, accept: comma, send: Page_Up }
        - { when: has_menu, accept: period, send: Page_Down }

      ascii_composer/good_old_caps_lock: true
  '';

  home.sessionVariables = {
    GLFW_IM_MODULE = "ibus";
  };
}
```

- [ ] **Step 5: Write modules/home/base/ui.nix**

From `host/home/ui.nix`:

```nix
{
  pkgs,
  ...
}:

{
  home.pointerCursor = {
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Ice";
    size = 16;
    x11.defaultCursor = "Bibata-Modern-Ice";
    gtk.enable = true;
    x11.enable = true;
  };

  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
  };

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
  };
}
```

- [ ] **Step 6: Write modules/home/base/xdg.nix**

From `host/home/xdg.nix`:

```nix
{ ... }:
{
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "inode/directory" = [ "thunar.desktop" ];
      "application/pdf" = [ "org.pwmt.zathura-pdf-mupdf.desktop" ];
      "text/plain" = [ "code.desktop" ];
      "text/markdown" = [ "code.desktop" ];
      "application/x-shellscript" = [ "code.desktop" ];
      "video/mp4" = [ "mpv.desktop" ];
      "video/x-matroska" = [ "mpv.desktop" ];
      "video/webm" = [ "mpv.desktop" ];
      "video/quicktime" = [ "mpv.desktop" ];
      "text/html" = [ "firefox.desktop" ];
      "x-scheme-handler/http" = [ "firefox.desktop" ];
      "x-scheme-handler/https" = [ "firefox.desktop" ];
      "x-scheme-handler/about" = [ "firefox.desktop" ];
      "x-scheme-handler/unknown" = [ "firefox.desktop" ];
    };
  };
}
```

- [ ] **Step 7: Commit**

```bash
git add modules/home/base/
git commit -m "$(cat <<'EOF'
feat: migrate home base config into modules/home/base/

Split host/home/* into user/session-vars/input-method/ui/xdg modules.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 14: Migrate modules/home/packages.nix

**Files:**
- Create: `modules/home/packages.nix`

- [ ] **Step 1: Write modules/home/packages.nix**

From `host/packages.nix` (content unchanged, only path changes):

```nix
{
  pkgs,
  pkgs-unstable,
  inputs,
  ...
}:

{
  home.packages = with pkgs; [
    fzf
    ripgrep
    imagemagick
    nodejs
    clang
    clang-tools
    lld
    (python312.withPackages (
      ps: with ps; [
        pip
      ]
    ))
    python312Packages.uv
    gnumake
    unzip
    fastfetch
    pkgs-unstable.github-copilot-cli
    pkgs-unstable.codex
    pkgs-unstable.claude-code

    inputs.MyNixvim.packages.${pkgs.stdenv.hostPlatform.system}.default

    xwayland-satellite
    libnotify
    swww
    mission-center
    bibata-cursors

    wl-clipboard
    cliphist
    xclip

    brightnessctl
    pamixer
    pavucontrol
    playerctl
    obs-studio
    mangohud

    cherry-studio
    wechat
    pkgs-unstable.qq
    pkgs-unstable.go-musicfox

    (prismlauncher.override {
      additionalPrograms = [ ffmpeg ];
      jdks = [
        javaPackages.compiler.temurin-bin.jdk-25
      ];
      gamemodeSupport = true;
    })
  ];
}
```

- [ ] **Step 2: Commit**

```bash
git add modules/home/packages.nix
git commit -m "$(cat <<'EOF'
feat: migrate host/packages.nix to modules/home/packages.nix

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 15: Migrate modules/home/wm/niri (from home/niri/)

**Files:**
- Create: `modules/home/wm/niri/default.nix`
- Create: `modules/home/wm/niri/autostart.nix`
- Create: `modules/home/wm/niri/keybinds.nix`
- Create: `modules/home/wm/niri/rules.nix`
- Create: `modules/home/wm/niri/settings.nix`

All files are content-preserving moves from `home/niri/`. No import path changes needed since they only import from each other within the same directory.

- [ ] **Step 1: Write modules/home/wm/niri/default.nix**

Same as `home/niri/default.nix`:

```nix
{
  ...
}:

{
  imports = [
    ./autostart.nix
    ./keybinds.nix
    ./rules.nix
    ./settings.nix
  ];
}
```

- [ ] **Step 2: Write modules/home/wm/niri/autostart.nix**

Same as `home/niri/autostart.nix`:

```nix
{
  config,
  lib,
  pkgs,
  ...
}:

{
  programs.niri.settings = {
    xwayland-satellite = {
      enable = true;
      path = "${pkgs.xwayland-satellite}/bin/xwayland-satellite";
    };

    spawn-at-startup = [
      {
        command = [
          "dbus-update-activation-environment"
          "--systemd"
          "WAYLAND_DISPLAY"
          "XDG_CURRENT_DESKTOP"
          "XDG_SESSION_TYPE"
          "DISPLAY"
        ];
      }
      {
        command = [ "noctalia-shell" ];
      }
    ];
  };
}
```

- [ ] **Step 3: Write modules/home/wm/niri/keybinds.nix**

Same as `home/niri/keybinds.nix` (227 lines, pure content move).

- [ ] **Step 4: Write modules/home/wm/niri/rules.nix**

Same as `home/niri/rules.nix` (32 lines, pure content move):

```nix
{ config, lib, ... }:

{
  programs.niri.settings = {
    window-rules = [
      {
        geometry-corner-radius = {
          top-left = 18.0;
          top-right = 18.0;
          bottom-left = 18.0;
          bottom-right = 18.0;
        };
        clip-to-geometry = true;
        draw-border-with-background = false;
      }
      {
        matches = [{ app-id = "foot"; }];
        opacity = 0.8;
      }
    ];

    layer-rules = [
      {
        matches = [
          { namespace = "^noctalia-overview*"; }
        ];
        place-within-backdrop = true;
      }
    ];
  };
}
```

- [ ] **Step 5: Write modules/home/wm/niri/settings.nix**

Same as `home/niri/settings.nix` (182 lines, pure content move).

Since settings.nix is large, use `cp` for the large files:

```bash
cp /home/mayon/nix-dotfiles/home/niri/keybinds.nix /home/mayon/nix-dotfiles/modules/home/wm/niri/keybinds.nix
cp /home/mayon/nix-dotfiles/home/niri/settings.nix /home/mayon/nix-dotfiles/modules/home/wm/niri/settings.nix
```

- [ ] **Step 6: Commit**

```bash
git add modules/home/wm/
git commit -m "$(cat <<'EOF'
feat: migrate niri WM config into modules/home/wm/niri/

Pure content move from home/niri/ with no import path changes needed.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 16: Migrate modules/home/programs (from home/program/)

**Files:**
- Create: `modules/home/programs/apps/firefox.nix`
- Create: `modules/home/programs/apps/mpv.nix`
- Create: `modules/home/programs/apps/noctalia.nix`
- Create: `modules/home/programs/apps/obsidian.nix`
- Create: `modules/home/programs/apps/thunar-terminal.nix`
- Create: `modules/home/programs/apps/yazi.nix`
- Create: `modules/home/programs/apps/zathura.nix`
- Create: `modules/home/programs/dev/git.nix`
- Create: `modules/home/programs/dev/latex.nix`
- Create: `modules/home/programs/dev/vscode.nix`
- Create: `modules/home/programs/terminal/foot.nix`
- Create: `modules/home/programs/terminal/tmux.nix`

Most are pure content moves. The only file with path-dependent changes is `noctalia.nix` — its wallpaper paths change from `../../wallpaper` to `../../_assets/wallpaper`.

- [ ] **Step 1: Copy all pure-move files from home/program/**

```bash
# apps (excluding noctalia which needs path changes)
cp /home/mayon/nix-dotfiles/home/program/apps/firefox.nix /home/mayon/nix-dotfiles/modules/home/programs/apps/firefox.nix
cp /home/mayon/nix-dotfiles/home/program/apps/mpv.nix /home/mayon/nix-dotfiles/modules/home/programs/apps/mpv.nix
cp /home/mayon/nix-dotfiles/home/program/apps/obsidian.nix /home/mayon/nix-dotfiles/modules/home/programs/apps/obsidian.nix
cp /home/mayon/nix-dotfiles/home/program/apps/yazi.nix /home/mayon/nix-dotfiles/modules/home/programs/apps/yazi.nix
cp /home/mayon/nix-dotfiles/home/program/apps/zathura.nix /home/mayon/nix-dotfiles/modules/home/programs/apps/zathura.nix

# desktop → apps (noctalia handled below, thunar-terminal handled below)
cp /home/mayon/nix-dotfiles/home/program/desktop/thunar-terminal.nix /home/mayon/nix-dotfiles/modules/home/programs/apps/thunar-terminal.nix

# dev
cp /home/mayon/nix-dotfiles/home/program/dev/git.nix /home/mayon/nix-dotfiles/modules/home/programs/dev/git.nix
cp /home/mayon/nix-dotfiles/home/program/dev/latex.nix /home/mayon/nix-dotfiles/modules/home/programs/dev/latex.nix
cp /home/mayon/nix-dotfiles/home/program/dev/vscode.nix /home/mayon/nix-dotfiles/modules/home/programs/dev/vscode.nix

# terminal
cp /home/mayon/nix-dotfiles/home/program/terminal/foot.nix /home/mayon/nix-dotfiles/modules/home/programs/terminal/foot.nix
cp /home/mayon/nix-dotfiles/home/program/terminal/tmux.nix /home/mayon/nix-dotfiles/modules/home/programs/terminal/tmux.nix
```

- [ ] **Step 2: Write modules/home/programs/apps/noctalia.nix with updated wallpaper paths**

Copy from `home/program/desktop/noctalia.nix` but change `../../wallpaper` → `../../_assets/wallpaper`:

```nix
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  wallpaperDir = "${../../_assets/wallpaper}";
  defaultWallpaperPath = "${../../_assets/wallpaper/wallpaper-001.jpg}";
  overviewWallpaperPath = "${../../_assets/wallpaper/wallpaper-002.jpg}";
in
{
  imports = [
    inputs.noctalia.homeModules.default
  ];

  config = {
    programs.noctalia-shell = {
      enable = true;
      package = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;

      systemd.enable = false;

      colors = {
        mError = "#e06c75";
        mOnError = "#111111";
        mOnPrimary = "#111111";
        mOnSecondary = "#111111";
        mOnSurface = "#abb2bf";
        mOnSurfaceVariant = "#9aa3b2";
        mOnTertiary = "#111111";
        mOnHover = "#e6eaf2";
        mOutline = "#3b4252";
        mPrimary = "#61afef";
        mSecondary = "#56b6c2";
        mShadow = "#000000";
        mSurface = "#1f2329";
        mHover = "#30384a";
        mSurfaceVariant = "#282c34";
        mTertiary = "#98c379";
      };

      settings = {
        general = {
          language = "zh-CN";
          radiusRatio = 0.6;
          boxRadiusRatio = 0.8;
          screenRadiusRatio = 0.7;
          animationSpeed = 0.95;
          enableShadows = true;
          enableBlurBehind = true;
        };

        ui = {
          fontDefault = "Noto Sans CJK SC";
          fontFixed = "JetBrains Mono Nerd Font";
          fontDefaultScale = 1;
          fontFixedScale = 1;
          tooltipsEnabled = true;
          panelBackgroundOpacity = 0.9;
          settingsPanelMode = "attached";
          panelsAttachedToBar = true;
        };

        bar = {
          barType = "simple";
          density = "compact";
          position = "top";
          floating = true;
          marginVertical = 6;
          marginHorizontal = 8;
          frameThickness = 10;
          frameRadius = 16;
          widgetSpacing = 8;
          contentPadding = 3;
          showCapsule = true;
          capsuleOpacity = 0.96;
          backgroundOpacity = 0.88;
          hideOnOverview = true;
          widgets = {
            left = [
              { id = "Launcher"; }
              {
                id = "Workspace";
                hideUnoccupied = false;
                labelMode = "none";
              }
              { id = "MediaMini"; }
            ];
            center = [ ];
            right = [
              { id = "Network"; }
              { id = "Bluetooth"; }
              { id = "Volume"; }
              { id = "Brightness"; }
              { id = "SystemMonitor"; }
              { id = "Tray"; }
              {
                id = "Battery";
                alwaysShowPercentage = true;
                warningThreshold = 28;
              }
              {
                id = "Clock";
                formatHorizontal = "HH:mm";
                formatVertical = "HH mm";
                useMonospacedFont = true;
                usePrimaryColor = true;
              }
              { id = "ControlCenter"; }
            ];
          };
        };

        location = {
          name = "Jingkou Qu, China";
          monthBeforeDay = false;
          use12hourFormat = false;
          weatherEnabled = true;
          weatherShowEffects = true;
          useFahrenheit = false;
          hideWeatherCityName = false;
          hideWeatherTimezone = false;
          showCalendarWeather = true;
          showWeekNumberInCalendar = true;
          firstDayOfWeek = 1;
        };

        wallpaper = {
          enabled = true;
          overviewEnabled = true;
          directory = wallpaperDir;
          automationEnabled = true;
          wallpaperChangeMode = "random";
          randomIntervalSec = 300;
          viewMode = "single";
          sortOrder = "name";
          fillMode = "crop";
          useSolidColor = false;
          transitionDuration = 1200;
          transitionType = "random";
          overviewBlur = 0.55;
          overviewTint = 0.65;
          hideWallpaperFilenames = true;
        };

        colorSchemes = {
          useWallpaperColors = false;
          predefinedScheme = "Noctalia (default)";
          darkMode = true;
        };

        appLauncher = {
          enableClipboardHistory = true;
          enableClipPreview = true;
          position = "center";
          viewMode = "list";
          density = "compact";
          iconMode = "tabler";
          showIconBackground = true;
          showCategories = true;
          terminalCommand = "foot -e";
        };

        controlCenter = {
          position = "close_to_bar_button";
          cards = [
            { enabled = true; id = "profile-card"; }
            { enabled = true; id = "shortcuts-card"; }
            { enabled = true; id = "audio-card"; }
            { enabled = true; id = "brightness-card"; }
            { enabled = true; id = "weather-card"; }
            { enabled = true; id = "media-sysmon-card"; }
          ];
        };

        notifications = {
          enabled = true;
          density = "compact";
          location = "top_right";
          overlayLayer = true;
          backgroundOpacity = 0.95;
          respectExpireTimeout = true;
        };

        osd = {
          enabled = true;
          location = "top_right";
          backgroundOpacity = 0.95;
        };

        idle = {
          enabled = true;
          screenOffTimeout = 600;
          lockTimeout = 660;
          suspendTimeout = 1800;
          fadeDuration = 5;
        };

        dock = {
          enabled = true;
          position = "bottom";
          displayMode = "auto_hide";
          dockType = "floating";
          backgroundOpacity = 0.92;
          floatingRatio = 1;
          size = 1;
          onlySameOutput = true;
          colorizeIcons = false;
          showLauncherIcon = true;
          launcherPosition = "end";
          inactiveIndicators = true;
          groupApps = true;
          groupContextMenuMode = "extended";
          groupIndicatorStyle = "dots";
          deadOpacity = 0.65;
          animationSpeed = 1;
          showDockIndicator = false;
          indicatorThickness = 3;
          indicatorColor = "primary";
          indicatorOpacity = 0.75;
        };
      };
    };

    home.file.".cache/noctalia/wallpapers.json".text = builtins.toJSON {
      defaultWallpaper = defaultWallpaperPath;
      wallpapers = {
        "eDP-1" = defaultWallpaperPath;
      };
    };
  };
}
```

- [ ] **Step 3: Commit**

```bash
git add modules/home/programs/
git commit -m "$(cat <<'EOF'
feat: migrate home/program into modules/home/programs/

Flatten desktop/ into apps/ (noctalia, thunar-terminal). Update noctalia
wallpaper paths from ../../wallpaper to ../../_assets/wallpaper.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 17: Migrate modules/home/shell and services (from home/)

**Files:**
- Create: `modules/home/shell/default.nix`
- Create: `modules/home/shell/zsh.nix`
- Create: `modules/home/services/default.nix`
- Create: `modules/home/services/clipboard.nix`
- Create: `modules/home/services/cliphist.nix`

- [ ] **Step 1: Copy all files from home/shell/ and home/service/**

```bash
cp /home/mayon/nix-dotfiles/home/shell/default.nix /home/mayon/nix-dotfiles/modules/home/shell/default.nix
cp /home/mayon/nix-dotfiles/home/shell/zsh.nix /home/mayon/nix-dotfiles/modules/home/shell/zsh.nix
cp /home/mayon/nix-dotfiles/home/service/default.nix /home/mayon/nix-dotfiles/modules/home/services/default.nix
cp /home/mayon/nix-dotfiles/home/service/clipboard.nix /home/mayon/nix-dotfiles/modules/home/services/clipboard.nix
cp /home/mayon/nix-dotfiles/home/service/cliphist.nix /home/mayon/nix-dotfiles/modules/home/services/cliphist.nix
```

- [ ] **Step 2: Commit**

```bash
git add modules/home/shell/ modules/home/services/
git commit -m "$(cat <<'EOF'
feat: migrate home shell and services into modules/home/

Pure content moves from home/shell/ and home/service/.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 18: Migrate wallpaper assets

**Files:**
- Move: `home/wallpaper/*` → `modules/home/_assets/wallpaper/*`

- [ ] **Step 1: Copy wallpaper files**

```bash
cp /home/mayon/nix-dotfiles/home/wallpaper/*.jpg /home/mayon/nix-dotfiles/modules/home/_assets/wallpaper/
cp /home/mayon/nix-dotfiles/home/wallpaper/*.png /home/mayon/nix-dotfiles/modules/home/_assets/wallpaper/
```

- [ ] **Step 2: Commit**

```bash
git add modules/home/_assets/
git commit -m "$(cat <<'EOF'
feat: migrate wallpapers to modules/home/_assets/wallpaper/

_ prefix prevents accidental glob imports by Nix module system.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 19: Create lib/ and flakeModules/ placeholders

**Files:**
- Create: `lib/default.nix`
- Create: `flakeModules/.gitkeep`

- [ ] **Step 1: Write lib/default.nix (empty placeholder)**

```nix
{ ... }:
{
  # Pure Nix helper functions.
  # Currently empty — extract here when the same expression appears ≥3 times.
}
```

- [ ] **Step 2: Create flakeModules/.gitkeep**

```bash
touch /home/mayon/nix-dotfiles/flakeModules/.gitkeep
```

- [ ] **Step 3: Commit**

```bash
git add lib/ flakeModules/
git commit -m "$(cat <<'EOF'
feat: add lib/ and flakeModules/ placeholders

lib/ for pure Nix helpers (empty until needed), flakeModules/ for
public flake-parts modules (empty, reserved for future publishing).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 20: Update .gitignore

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Update .gitignore for new paths**

Replace current content:

```
/result
/result-*

# Wallpaper assets tracked in modules/home/_assets/wallpaper/
```

- [ ] **Step 2: Commit**

```bash
git add .gitignore
git commit -m "$(cat <<'EOF'
chore: update .gitignore for new directory structure

Remove old suckless build artifact paths, add result symlink entries.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 21: Verify nix flake check passes

- [ ] **Step 1: Run nix flake check**

```bash
cd /home/mayon/nix-dotfiles && nix flake check 2>&1
```

Expected: All checks pass (flake-parts evaluation, treefmt check).

If `treefmt` reports formatting issues, run:

```bash
nix fmt
```

Then re-check.

- [ ] **Step 2: Verify nixosConfiguration evaluates**

```bash
cd /home/mayon/nix-dotfiles && nix eval .#nixosConfigurations.nixos-btw.config.system.build.toplevel.drvPath 2>&1
```

Expected: A derivation path is printed (no evaluation errors).

- [ ] **Step 3: Commit any formatting fixes**

```bash
git add -A
git commit -m "$(cat <<'EOF'
chore: apply nix fmt formatting fixes

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 22: Remove old files

**Files:**
- Delete: `configuration.nix`
- Delete: `hardware-configuration.nix`
- Delete: `host/` (all files)
- Delete: `system/` (all files)
- Delete: `home/` (all files)
- Delete: `dev/` (all files)

- [ ] **Step 1: Remove old directories**

```bash
cd /home/mayon/nix-dotfiles
git rm configuration.nix hardware-configuration.nix
git rm -r host/
git rm -r system/
git rm -r home/
git rm -r dev/
```

- [ ] **Step 2: Re-verify nix flake check after removal**

```bash
cd /home/mayon/nix-dotfiles && nix flake check 2>&1
```

Expected: Still passes — all references now point to new paths.

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat: remove old directory structure

Delete host/, system/, home/, dev/ — fully migrated to new flake-parts
structure under hosts/, modules/, flake/.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 23: Final dry-build verification

- [ ] **Step 1: Run nixos-rebuild dry-build**

```bash
sudo nixos-rebuild dry-build --flake /home/mayon/nix-dotfiles#nixos-btw 2>&1
```

Expected: Builds successfully.

- [ ] **Step 2: If dry-build passes, final status check**

```bash
cd /home/mayon/nix-dotfiles && git status && echo "---" && git log --oneline -10
```

Expected: Clean working tree, ~23 commits on the branch.

---

### Implementation Order Dependency

```
Task 1 (dirs)
  └─> Task 2 (flake.nix)
        └─> Task 3 (flake/system.nix)
        └─> Task 4 (flake/home.nix + dev.nix)
              └─> Task 5 (hosts)
              └─> Task 6-11 (modules/system/*)
              └─> Task 12-18 (modules/home/*)
                    └─> Task 19 (lib + flakeModules)
                          └─> Task 20 (.gitignore)
                                └─> Task 21 (nix flake check)
                                      └─> Task 22 (remove old files)
                                            └─> Task 23 (dry-build)
```

Tasks 6-11 can run in parallel, as can Tasks 12-18. Task 19-20 are independent of each other.
