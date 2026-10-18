_:

let

  # Needed both by systemd user services (which do not source the shell profile)
  # and by interactive shells, so the same set is exported through both paths.
  shared = {
    NIXOS_OZONE_WL = "1";
    _JAVA_AWT_WM_NONREPARENTING = "1";
    # Qt apps started outside mango (systemd user units, desktop launchers)
    # need this too; base/qt.nix seeds the qt6ct palette.
    QT_QPA_PLATFORMTHEME = "qt6ct";
    # The HM fcitx5 module writes these to home.sessionVariables only, which
    # interactive shells and mango pick up but systemd-launched desktop apps
    # do not (verified: systemd.user.sessionVariables had none). Same values,
    # exported through both paths.
    GLFW_IM_MODULE = "ibus";
    SDL_IM_MODULE = "fcitx";
    XMODIFIERS = "@im=fcitx";
  };
in
{
  # Xft.dpi and the xrdb merge that actually delivers it live in xresources.nix.
  systemd.user.sessionVariables = shared;

  home = {
    sessionPath = [
      "$HOME/.local/bin"
    ];

    # IME variables now live in `shared` above; the HM fcitx5 module only
    # contributes the home-side set, so systemd-launched apps needed the
    # mirror to get them too.
    sessionVariables = shared // {
      # A built-in syntax preset; terminal surfaces and ANSI colors remain
      # owned by the shared fixed palette. No runtime theme writer is needed.
      BAT_THEME = "Catppuccin Mocha";
    };
  };
}
