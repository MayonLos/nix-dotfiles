{
  pkgs,
  config,
  lib,
  ...
}:

let
  # X11 clients reach niri through xwayland-satellite, which runs the X server
  # at the output's real scale rather than at 1: QQ's window measures 1251x1498
  # X pixels against the 834x999 logical size niri reports for it, exactly 1.5x
  # (`xwininfo -root -tree` vs `niri msg windows`, 2026-08-21). X pixels are
  # therefore physical pixels and nothing scales an X client afterwards, so
  # every one of them has to be told 96 x 1.5 = 144 DPI itself.
  #
  # Home Manager writes ~/.Xresources but only merges it into a running server
  # when DISPLAY happens to be set in the activation environment
  # (home-manager/modules/xresources.nix), which it never is under
  # `nixos-rebuild`. Its other delivery path, xsession.profileExtra, belongs to
  # startx and niri does not source it. The result was a completely empty
  # resource database — `xrdb -query` printed nothing — which is why fcitx5's
  # X11 candidate window stayed at 96 DPI while everything on Wayland was fine.
  xrdbMerge = pkgs.writeShellScript "xrdb-merge-xresources" ''
    # niri spawns xwayland-satellite alongside the compositor, but Xwayland
    # itself is socket-activated behind it and need not have answered yet.
    for _ in $(seq 50); do
      if ${lib.getExe pkgs.xrdb} -merge ${config.xresources.path}; then
        exit 0
      fi
      sleep 0.2
    done
    echo "xrdb: no X server answered on DISPLAY=$DISPLAY after 10s" >&2
    exit 1
  '';
in
{
  # 2560x1600 at niri scale 1.5. Consumed by fcitx5's X11 candidate window
  # (which needs PerScreenDPI=False in base/input-method.nix to look at it at
  # all) and by any other X client that reads Xft.dpi.
  xresources.properties."Xft.dpi" = 144;

  systemd.user.services.xrdb-merge = {
    Unit = {
      Description = "Merge ~/.Xresources into the xwayland-satellite X server";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${xrdbMerge}";
    };

    Install.WantedBy = [ "graphical-session.target" ];
  };
}
