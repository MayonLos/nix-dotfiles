{
  pkgs,
  home,
  host,
}:
let
  qq = pkgs.lib.findFirst (
    package: (package.name or "") == "qq-with-pipewire"
  ) (throw "Xorg capture check requires the real configured QQ wrapper") home.home.packages;
  packageNamed =
    name:
    pkgs.lib.findFirst (
      package: (package.name or "") == name
    ) (throw "Missing production Xorg package: ${name}") home.home.packages;
  launcher = packageNamed "xorg-launcher";
  menu = pkgs.lib.findFirst (
    package: (package.name or "") == "xorg-session-menu"
  ) (throw "Missing production Xorg menu") home.home.packages;
  metadata = pkgs.writeText "xorg-contract.json" (
    builtins.toJSON {
      units = pkgs.lib.getAttrs [
        "picom"
        "dunst"
        "xorg-copyq"
        "xorg-polkit"
        "xorg-lock"
        "xorg-status"
      ] home.systemd.user.services;
      sharedTargets = home.nixDotfiles.graphicalSessionTargets;
      defaultSession = host.services.displayManager.noctalia-greeter.settings.session.default;
      xserver = host.services.xserver.enable;
      startx = host.services.xserver.displayManager.startx.enable;
      generatedXinitrc = host.services.xserver.displayManager.startx.generateScript;
      rofiEnabled = home.programs.rofi.enable;
      x11Dpi = host.services.xserver.dpi;
      portal = host.xdg.portal.config.dwm;
      pam = builtins.hasAttr "i3lock" host.security.pam.services;
      xorgConfig = host.services.xserver.config;
    }
  );
  desktop = pkgs.writeText "xorg-programs.json" (
    builtins.toJSON {
      dwm = "${home.nixDotfiles.xorgDwmPackage}/bin/dwm";
      picom = "${pkgs.picom}/bin/picom";
      picomConfig = home.xdg.configFile."picom/picom.conf".source;
      launcher = "${launcher}/bin/xorg-launcher";
      dunst = "${pkgs.dunst}/bin/dunst";
      dunstConfig = home.xdg.configFile."dunst/dunstrc".source;
      xprop = "${pkgs.xprop}/bin/xprop";
      xrdb = "${pkgs.xrdb}/bin/xrdb";
      xwininfo = "${pkgs.xwininfo}/bin/xwininfo";
      xdotool = "${pkgs.xdotool}/bin/xdotool";
      xlib = "${pkgs.libx11}/lib/libX11.so.6";
      maim = "${pkgs.maim}/bin/maim";
      feh = "${pkgs.feh}/bin/feh";
      wallpaper = ./resources/wallpaper/wallpaper-009.png;
      xsetroot = "${pkgs.xsetroot}/bin/xsetroot";
      notifySend = "${pkgs.libnotify}/bin/notify-send";
      menu = "${menu}/bin/xorg-session-menu";
    }
  );
in
pkgs.runCommand "xorg-session-runtime"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.dbus
      pkgs.xvfb-run
      pkgs.xorg-server
      pkgs.fontconfig
    ];
  }
  ''
    export HOME="$TMPDIR/home" XDG_CONFIG_HOME="$TMPDIR/config" XDG_DATA_HOME="$TMPDIR/data" XDG_CACHE_HOME="$TMPDIR/cache" XDG_STATE_HOME="$TMPDIR/state" XDG_RUNTIME_DIR="$TMPDIR/runtime"
    mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR" "$out"
    chmod 700 "$XDG_RUNTIME_DIR"
    unset DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS
    export XORG_TEST_SHELL=${pkgs.bash}/bin/bash
    export XDG_DATA_DIRS=${pkgs.papirus-icon-theme}/share:${pkgs.hicolor-icon-theme}/share:$XDG_DATA_DIRS
    export FONTCONFIG_FILE=${
      pkgs.makeFontsConf {
        fontDirectories = [
          pkgs.noto-fonts-cjk-sans
          pkgs.nerd-fonts.jetbrains-mono
        ];
      }
    }
    python3 ${./resources/xorg}/test_session.py -v > "$out/supervisor.log" 2>&1 || { cat "$out/supervisor.log"; exit 1; }
    python3 ${./resources/xorg/test_qq.py} ${qq}/bin/qq > "$out/qq-wrapper.log" 2>&1 || { cat "$out/qq-wrapper.log"; exit 1; }
    dbus-run-session --config-file=${pkgs.dbus}/share/dbus-1/session.conf -- xvfb-run -a -s '-screen 0 1600x1000x24 -dpi ${toString host.services.xserver.dpi} -nolisten tcp +extension Composite' \
      python3 ${./resources/xorg/test_desktop.py} ${desktop} "$out" ${metadata} || { cat "$out"/*.log; exit 1; }
  ''
