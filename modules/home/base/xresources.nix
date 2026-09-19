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
  # 2026-08-21). Re-measured under mango on 2026-09-18, and the source-inspection
  # note that used to stand here was wrong: at mango's default
  # `xwayland_ignore_scale = 0` the X server ran at the *logical* size
  # (`xdpyinfo`: 1707x1067 = 2560/1.5) and every X surface was stretched 1.5x
  # onto the panel, which is why X11 clients -- Steam most visibly -- rendered
  # soft. wm/mango/config.nix now sets `xwayland_ignore_scale = 1`, so X windows
  # get physical-pixel buffers presented 1:1 (measured with an xclock:
  # 936x1010 logical vs 1392x1503 X-side, ratio 1.49).
  #
  # That makes this file load-bearing well beyond fcitx5: under 1:1
  # presentation an X client is *small* until it scales itself, and Xft.dpi is
  # how it learns to. The two settings are a pair -- do not remove one without
  # the other. Re-check with `xwininfo -root -tree` vs `mmsg get all-clients`.
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
