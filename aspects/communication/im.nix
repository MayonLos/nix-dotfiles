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
  # through a browser instead. The optional real Xorg session uses QQ's X11
  # backend; its own picker still needs an actual call/capture acceptance test.
  #
  # Verified 2026-08-13: dlopen("libpipewire-0.3.so.0") fails with QQ's own
  # environment and succeeds (pw_init included) with pipewire on the path.
  # That half was verified under niri, whose portal setup served
  # org.gnome.Mutter.ScreenCast. It does NOT carry over to mango: mango is
  # plain wlroots with no Mutter interface, so screen capture goes through
  # xdg-desktop-portal-wlr instead (aspects/interactive-session/host/portal.nix). The
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
  # This historical Mango workaround remains Wayland-only. Forcing it in the
  # optional real Xorg session would prevent QQ from starting at all.
  qqLauncher = pkgs.writeShellScript "qq-session-launcher" ''
    backend=wayland
    if [[ "''${XDG_SESSION_TYPE:-}" == x11 || -z "''${WAYLAND_DISPLAY:-}" ]]; then
      backend=x11
    fi
    export LD_LIBRARY_PATH="${
      lib.makeLibraryPath [ pkgs.pipewire ]
    }''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    exec ${pkgs-unstable.qq}/bin/qq "--ozone-platform=$backend" "$@"
  '';
  qq = pkgs.symlinkJoin {
    name = "qq-with-pipewire";
    paths = [ pkgs-unstable.qq ];
    postBuild = ''
      rm "$out/bin/qq"
      cp ${qqLauncher} "$out/bin/qq"

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
  home.packages = [
    # Passes --enable-wayland-ime --wayland-text-input-version=3 when
    # NIXOS_OZONE_WL and WAYLAND_DISPLAY are both set in Mango, so fcitx5's
    # wayland frontend drives it over text-input-v3 rather than XIM.
    qq

    # Stable's launcher enables the Wayland sharing hook only in a Wayland
    # session. In real Xorg use `wemeet`, not `wemeet-xwayland` (which forces
    # that hook). Conference, camera/audio and capture still need a real call.
    pkgs.wemeet

    # unstable: official WeChat is 4.1.13.26 here; stable still has 4.1.1.4.
    # 输入法问题待解决，见 docs 待办（docs/neovim-rebuild-execution.md）。
    pkgs-unstable.wechat
  ];
}
