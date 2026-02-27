{
  config,
  pkgs,
  ...
}:

{
  services.xserver = {
    enable = true;
    autoRepeatDelay = 200;
    autoRepeatInterval = 35;
    dpi = 144;
    videoDrivers = [
      "nvidia"
    ];
    desktopManager.runXdgAutostartIfNone = true;
    exportConfiguration = true;
    displayManager.startx.enable = true;
  };

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
      src = ../home/dwm;

      buildInputs =
        (old.buildInputs or [ ])
        ++ (with pkgs.xorg; [
          libXcursor
        ]);
    });
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
}
