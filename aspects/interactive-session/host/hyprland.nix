{ pkgs, ... }:
let
  sessionWrapper = pkgs.writeShellScriptBin "hyprland-session" (
    builtins.replaceStrings [ "@SYSTEMCTL@" ] [ "${pkgs.systemd}/bin/systemctl" ] (
      builtins.readFile ../resources/hyprland-session
    )
  );

  # Keep the pinned compositor binary/cache; only the login entry needs a
  # lifecycle wrapper. A derivation override would rebuild the whole compositor.
  hyprland = pkgs.lib.makeOverridable (
    {
      enableXWayland ? true,
    }:
    let
      compositor = pkgs.hyprland.override { inherit enableXWayland; };
    in
    pkgs.symlinkJoin {
      name = "hyprland-session-${pkgs.hyprland.version}";
      paths = [ compositor ];
      inherit (compositor) version meta;
      passthru = {
        providedSessions = [ "hyprland" ];
        inherit (compositor) man dev;
      };
      postBuild = ''
        # The alternate UWSM entry would bypass this session lifecycle.
        rm "$out/share/wayland-sessions/hyprland-uwsm.desktop"
        session="$out/share/wayland-sessions/hyprland.desktop"
        rm "$session"
        cp ${compositor}/share/wayland-sessions/hyprland.desktop "$session"
        chmod u+w "$session"
        substituteInPlace "$session" \
          --replace-fail "Exec=${compositor}/bin/start-hyprland" \
            "Exec=${sessionWrapper}/bin/hyprland-session ${compositor}/bin/start-hyprland"
      '';
    }
  ) { };
in
{
  programs.hyprland = {
    enable = true;
    # Home Manager owns the compositor target and environment import.
    withUWSM = false;
    package = hyprland;
  };

  xdg.portal.config.hyprland = {
    default = [
      "hyprland"
      "gtk"
    ];
    "org.freedesktop.impl.portal.ScreenCast" = "hyprland";
    "org.freedesktop.impl.portal.Screenshot" = "hyprland";
    "org.freedesktop.impl.portal.FileChooser" = "gtk";
    "org.freedesktop.impl.portal.Settings" = "gnome";
    "org.freedesktop.impl.portal.Secret" = "gnome-keyring";
  };
}
