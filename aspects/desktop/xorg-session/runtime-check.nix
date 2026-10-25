{
  pkgs,
  home,
  host,
  appearance,
}:
let
  wallpapers = import ../../appearance/appearance/resources/wallpaper/package.nix {
    inherit pkgs;
    palette = appearance;
  };
  qq = pkgs.lib.findFirst (
    package: (package.name or "") == "qq-with-pipewire"
  ) (throw "Xorg capture check requires the real configured QQ wrapper") home.home.packages;
  packageNamed =
    name:
    pkgs.lib.findFirst (
      package: (package.name or "") == name
    ) (throw "Missing production Xorg package: ${name}") home.home.packages;
  launcher = packageNamed "xorg-launcher";
  notificationMenu = packageNamed "xorg-rofi-dmenu";
  menu = packageNamed "xorg-session-menu";
  powerMenu = packageNamed "xorg-power-menu";
  status = packageNamed "xorg-status";
  lock = packageNamed "xorg-lock";
  metadata = pkgs.writeText "xorg-contract.json" (
    builtins.toJSON {
      units = pkgs.lib.getAttrs [
        "picom"
        "dunst"
        "xorg-copyq"
        "xorg-polkit"
        "xorg-lock"
        "xorg-status"
        "xorg-background"
        "xorg-outputs"
        "xorg-idle"
      ] home.systemd.user.services;
      sharedTargets = home.nixDotfiles.graphicalSessionTargets;
      defaultSession = host.services.displayManager.noctalia-greeter.settings.session.default;
      wallpaper = wallpapers.default;
      greeterWallpaper = host.services.displayManager.noctalia-greeter.settings.appearance.wallpaper.path;
      xserver = host.services.xserver.enable;
      startx = host.services.xserver.displayManager.startx.enable;
      generatedXinitrc = host.services.xserver.displayManager.startx.generateScript;
      rofiEnabled = home.programs.rofi.enable;
      x11Dpi = host.services.xserver.dpi;
      mangoBindings =
        home.wayland.windowManager.mango.settings.bind
        ++ home.wayland.windowManager.mango.settings.key_mode.common.bind
        ++ home.wayland.windowManager.mango.settings.key_mode.common.bindl;
      portal = host.xdg.portal.config.dwm;
      pam = builtins.hasAttr "i3lock" host.security.pam.services;
      xorgConfig = host.services.xserver.config;
    }
  );
  desktop = pkgs.writeText "xorg-programs.json" (
    builtins.toJSON {
      dwm = "${home.nixDotfiles.xorgDwmPackage}/bin/dwm";
      dwmConfig = "${home.nixDotfiles.xorgDwmPackage}/share/dwm/config.h";
      dwmBindings = "${home.nixDotfiles.xorgDwmPackage}/share/dwm/keybindings.json";
      dwmRules = "${home.nixDotfiles.xorgDwmPackage}/share/dwm/window-rules.json";
      picom = "${pkgs.picom}/bin/picom";
      picomConfig = home.xdg.configFile."picom/picom.conf".source;
      launcher = "${launcher}/bin/xorg-launcher";
      rofiDmenu = "${notificationMenu}/bin/xorg-rofi-dmenu";
      powerMenu = "${powerMenu}/bin/xorg-power-menu";
      menu = "${menu}/bin/xorg-session-menu";
      status = "${status}/bin/xorg-status";
      statusScript = ./resources/status.py;
      lock = "${lock}/bin/xorg-lock";
      rofi = "${pkgs.rofi}/bin/rofi";
      rofiConfig = home.home.file.${home.programs.rofi.configPath}.source;
      launcherTheme = home.xdg.configFile."rofi/launcher.rasi".source;
      powerEntries = ./resources/power-menu.json;
      powerIcons = home.xdg.configFile."rofi/power-icons".source;
      powerTheme = home.xdg.configFile."rofi/power.rasi".source;
      copyq = "${pkgs.copyq}/bin/copyq";
      screenshot = "${packageNamed "xorg-screenshot"}/bin/xorg-screenshot";
      satty = "${pkgs.satty}/bin/satty";
      xclip = "${pkgs.xclip}/bin/xclip";
      dunst = "${home.services.dunst.package}/bin/dunst";
      dunstPackage = "${home.services.dunst.package}";
      dunstConfig = home.xdg.configFile."dunst/dunstrc".source;
      xterm = "${pkgs.xterm}/bin/xterm";
      xprop = "${pkgs.xprop}/bin/xprop";
      xrdb = "${pkgs.xrdb}/bin/xrdb";
      xwininfo = "${pkgs.xwininfo}/bin/xwininfo";
      xdotool = "${pkgs.xdotool}/bin/xdotool";
      xlib = "${pkgs.libx11}/lib/libX11.so.6";
      imagemagickImport = "${pkgs.imagemagick}/bin/import";
      feh = "${pkgs.feh}/bin/feh";
      wallpaper = wallpapers.default;
      xsetroot = "${pkgs.xsetroot}/bin/xsetroot";
      notifySend = "${pkgs.libnotify}/bin/notify-send";
      palette = appearance;
    }
  );
in
pkgs.runCommand "xorg-session-runtime"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.dbus
      pkgs.util-linux
      pkgs.xvfb-run
      pkgs.xorg-server
      pkgs.fontconfig
      pkgs.imagemagick
    ];
  }
  ''
    export HOME="$TMPDIR/home" XDG_CONFIG_HOME="$TMPDIR/config" XDG_DATA_HOME="$TMPDIR/data" XDG_CACHE_HOME="$TMPDIR/cache" XDG_STATE_HOME="$TMPDIR/state" XDG_RUNTIME_DIR="$TMPDIR/runtime"
    mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR" "$out"
    test "$(magick identify -format '%wx%h' ${wallpapers.default})" = 2560x1600
    test '${wallpapers.default}' = '${host.services.displayManager.noctalia-greeter.settings.appearance.wallpaper.path}'
    chmod 700 "$XDG_RUNTIME_DIR"
    unset DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS
    export XORG_TEST_SHELL=${pkgs.bash}/bin/bash
    # Satty's drawing canvas needs EGL even with GTK's Cairo renderer. Supply
    # llvmpipe explicitly: the sandbox has no /run/opengl-driver or GPU device.
    export LIBGL_ALWAYS_SOFTWARE=1
    export GALLIUM_DRIVER=llvmpipe
    export LIBGL_DRIVERS_PATH=${pkgs.mesa}/lib/dri
    export __EGL_VENDOR_LIBRARY_FILENAMES=${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json
    export XDG_DATA_DIRS=${home.services.dunst.iconTheme.package}/share:${pkgs.hicolor-icon-theme}/share:$XDG_DATA_DIRS
    export FONTCONFIG_FILE=${
      pkgs.makeFontsConf {
        fontDirectories = [
          pkgs.noto-fonts-cjk-sans
          pkgs.maple-mono.NF-CN
          pkgs.inter
        ];
      }
    }
    cp ${desktop} "$out/programs.json"
    cp ${metadata} "$out/metadata.json"
    python3 -B ${./.}/tests/test_tools.py -v > "$out/tools.log" 2>&1 || { cat "$out/tools.log"; exit 1; }
    python3 -B ${./.}/tests/test_status.py -v > "$out/status.log" 2>&1 || { cat "$out/status.log"; exit 1; }
    python3 -B ${./.}/tests/test_session.py -v > "$out/supervisor.log" 2>&1 || { cat "$out/supervisor.log"; exit 1; }
    python3 -B ${./.}/tests/test_qq.py ${qq}/bin/qq > "$out/qq-wrapper.log" 2>&1 || { cat "$out/qq-wrapper.log"; exit 1; }
    dbus-run-session --config-file=${pkgs.dbus}/share/dbus-1/session.conf -- xvfb-run -a -s '-screen 0 2560x1600x24 -dpi ${toString host.services.xserver.dpi} -nolisten tcp +extension Composite' \
      python3 -B ${./.}/tests/test_desktop.py ${desktop} "$out" ${metadata} || { cat "$out"/*.log; exit 1; }
    xvfb-run -a -s '-screen 0 2560x1600x24 -dpi ${toString host.services.xserver.dpi} -nolisten tcp' \
      python3 -B ${./.}/tests/test_menu.py ${desktop} "$out"
  ''
