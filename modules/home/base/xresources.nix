{
  pkgs,
  config,
  lib,
  ...
}:

let
  # X clients get physical pixels, not logical ones, so each has to be told
  # 96 x 1.5 = 144 DPI itself -- nothing scales them afterwards.
  #
  # The original measurement was taken under niri + xwayland-satellite: QQ's
  # window was 1251x1498 X pixels against the 834x999 logical size niri
  # reported, exactly 1.5x (`xwininfo -root -tree` vs `niri msg windows`,
  # 2026-08-21). It still applies to mango's built-in Xwayland by source
  # inspection rather than by re-measurement: client.c converts with
  # "X11 = logical * scale" and `xwayland_ignore_scale` defaults to 0, so the
  # X server again runs at the output's real scale. Worth re-checking with
  # `xwininfo -root -tree` vs `mmsg get all-clients` the first time the fcitx5
  # candidate window looks wrong.
  #
  # Home Manager writes ~/.Xresources but only merges it into a running server
  # when DISPLAY happens to be set in the activation environment
  # (home-manager/modules/xresources.nix), which it never is under
  # `nixos-rebuild`. Its other delivery path, xsession.profileExtra, belongs to
  # startx and mango does not source it. The result was a completely empty
  # resource database — `xrdb -query` printed nothing — which is why fcitx5's
  # X11 candidate window stayed at 96 DPI while everything on Wayland was fine.
  xrdbMerge = pkgs.writeShellScript "xrdb-merge-xresources" ''
    # Mango starts its built-in Xwayland lazily, so the X server need not have
    # answered when this session unit first runs.
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
  # 2560x1600 at mango scale 1.5. Consumed by fcitx5's X11 candidate window
  # (which needs PerScreenDPI=False in base/input-method.nix to look at it at
  # all) and by any other X client that reads Xft.dpi.
  xresources.properties."Xft.dpi" = 144;

  systemd.user.services.xrdb-merge = {
    Unit = {
      Description = "Merge ~/.Xresources into mango's built-in Xwayland server";
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
