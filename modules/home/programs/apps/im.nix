{ pkgs-unstable, ... }:
{
  # Both from unstable — these chase upstream closely and stable lags:
  # qq 3.2.29 vs 3.2.32, wechat-uos 4.1.1.4 vs 4.1.1.7.
  home.packages = with pkgs-unstable; [
    # Passes --enable-wayland-ime --wayland-text-input-version=3 when
    # NIXOS_OZONE_WL and WAYLAND_DISPLAY are both set (they are), so fcitx5's
    # wayland frontend drives it over text-input-v3 rather than XIM.
    qq

    # wechat-uos rather than `wechat`: the UOS build tracks upstream more
    # closely (4.1.1.7 vs 4.1.1.4) and its launcher maps XMODIFIERS onto
    # QT_IM_MODULE/GTK_IM_MODULE explicitly. It pins QT_QPA_PLATFORM=xcb, so it
    # runs through XWayland — Xft.dpi=144 in session-vars keeps that readable.
    # Switch to `wechat` (official Linux AppImage) if the UOS build misbehaves.
    wechat-uos
  ];
}
