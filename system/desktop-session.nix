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

  programs.gamemode.enable = true;
}
