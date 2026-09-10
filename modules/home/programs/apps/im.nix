{
  pkgs,
  pkgs-unstable,
  lib,
  ...
}:

let
  # nixpkgs' wrapper puts only libglvnd and util-linux-minimal on
  # LD_LIBRARY_PATH and none of the 25 RPATH entries mention pipewire, so on
  # NixOS (no /usr/lib) QQ's runtime dlopen of libpipewire-0.3.so.0 fails.
  # The wrap below fixes that, and it works: `grep libpipewire /proc/<qq>/maps`
  # shows the library mapped. Keep it — QQ reaches for pipewire on more than
  # one path and this is cheap.
  #
  # **It does not buy screen sharing, and the earlier claim here that it did
  # was wrong.** Re-verified 2026-09-10 against qq-3.2.32's binary: QQ's own
  # share picker is X11-only. It carries XQueryTree / XGetImage /
  # XShmGetImage and has no Wayland toplevel enumeration whatsoever — neither
  # zwlr_foreign_toplevel_manager_v1 nor ext_foreign_toplevel_list_v1 is in the
  # binary, and the only Wayland globals it names are
  # ext_input_manager_v1/ext_input_v1. The org.freedesktop.portal.ScreenCast
  # and SelectSources strings that suggested otherwise are Electron's own code,
  # on a path QQ's picker never takes: with the share dialog open,
  # xdg-desktop-portal-wlr logged zero requests for the whole session.
  #
  # Under mango's rootless Xwayland there is nothing for XQueryTree to find, so
  # the picker ends at "该应用已无法共享". Nothing in this file can change that,
  # and nothing else in the repo does either -- the v4l2loopback virtual-camera
  # workaround was built, tried and then removed on request. Screen sharing goes
  # through a browser instead; see the `desktop-apps` skill.
  #
  # Verified 2026-08-13: dlopen("libpipewire-0.3.so.0") fails with QQ's own
  # environment and succeeds (pw_init included) with pipewire on the path.
  # That half was verified under niri, whose portal setup served
  # org.gnome.Mutter.ScreenCast. It does NOT carry over to mango: mango is
  # plain wlroots with no Mutter interface, so screen capture goes through
  # xdg-desktop-portal-wlr instead (modules/system/desktop/xdg.nix). The
  # LD_LIBRARY_PATH wrap below is about QQ's own dlopen and is unaffected by
  # which portal backend serves the request.
  #
  # No --enable-features=WebRTCPipeWireCapturer is added on purpose: it is
  # default-on since Chromium 110, and Chromium takes the *last*
  # --enable-features switch rather than merging them, so passing a second one
  # would silently drop the WaylandWindowDecorations that nixpkgs' wrapper sets.
  #
  # --ozone-platform=wayland overrides the --ozone-platform-hint=auto that
  # nixpkgs' wrapper passes. `auto` was resolving to X11 even though
  # WAYLAND_DISPLAY, XDG_SESSION_TYPE and NIXOS_OZONE_WL are all set and
  # libwayland-client resolves fine, which left QQ as the machine's only
  # XWayland client (`xlsclients` printed nothing else) with its IME on XIM and
  # its fcitx5 candidate window stuck at 96 DPI. Verified 2026-08-21: with the
  # platform pinned, a QQ started on a scratch --user-data-dir held *zero*
  # connections to @/tmp/.X11-unix/X0 across 24 s and did not crash — an
  # explicit --ozone-platform never falls back, so surviving proves Wayland
  # initialised. Its input now goes through text-input-v3, where classicui
  # already scales correctly from wp_fractional_scale_v1.
  #
  # If the tray icon regresses, drop this one flag; nothing else here depends
  # on it. Screen sharing is not a reason to touch it either way — see above.
  qq = pkgs.symlinkJoin {
    name = "qq-with-pipewire";
    paths = [ pkgs-unstable.qq ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/qq \
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ pkgs.pipewire ]} \
        --add-flags "--ozone-platform=wayland"

      # qq.desktop hardcodes the unwrapped store path, so the launcher would
      # bypass the wrapper entirely without this.
      rm $out/share/applications/qq.desktop
      substitute ${pkgs-unstable.qq}/share/applications/qq.desktop \
        $out/share/applications/qq.desktop \
        --replace-fail "${pkgs-unstable.qq}/bin/qq" "$out/bin/qq"
    '';
  };
in
{
  # Both from unstable — these chase upstream closely and stable lags:
  # qq 3.2.29 vs 3.2.32, wechat-uos 4.1.1.4 vs 4.1.1.7.
  home.packages = [
    # Passes --enable-wayland-ime --wayland-text-input-version=3 when
    # NIXOS_OZONE_WL and WAYLAND_DISPLAY are both set (they are), so fcitx5's
    # wayland frontend drives it over text-input-v3 rather than XIM.
    qq

    # wechat-uos rather than `wechat`: the UOS build tracks upstream more
    # closely (4.1.1.7 vs 4.1.1.4) and its launcher maps XMODIFIERS onto
    # QT_IM_MODULE/GTK_IM_MODULE explicitly. It pins QT_QPA_PLATFORM=xcb, so it
    # runs through XWayland — Xft.dpi=144 in session-vars keeps that readable.
    # Switch to `wechat` (official Linux AppImage) if the UOS build misbehaves.
    pkgs-unstable.wechat-uos
  ];
}
