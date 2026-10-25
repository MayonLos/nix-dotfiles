{
  config,
  lib,
  pkgs,
  ...
}:

let

  # Needed both by systemd user services (which do not source the shell profile)
  # and by interactive shells, so the same set is exported through both paths.
  shared = {
    # Reuse HM's sole pointerCursor declaration for systemd-launched clients too.
    XCURSOR_THEME = config.home.pointerCursor.name;
    XCURSOR_SIZE = toString config.home.pointerCursor.size;
    _JAVA_AWT_WM_NONREPARENTING = "1";
    # Qt apps started outside the compositor (systemd user units, desktop launchers)
    # need this too; qt.nix seeds the qt6ct palette.
    QT_QPA_PLATFORMTHEME = "qt6ct";
    # Installing qt6ct alone does not add its QPA plugin to other Qt apps.
    # Their wrappers prefix their own plugin directories and retain this one.
    QT_PLUGIN_PATH = "${pkgs.qt6Packages.qt6ct}/${pkgs.qt6Packages.qtbase.qtPluginPrefix}";
    # GTK3/4's native chooser integration delegates to the shared FileChooser
    # portal. Session backends explicitly route that interface to GTK.
    GTK_USE_PORTAL = "1";
    # Search root, not its 2.10.0/engines subdirectory: GTK3 must resolve its
    # own ABI directory and never see GTK2 engines as unversioned modules.
    GTK_PATH = "${config.gtk.gtk2.theme.package}/lib/gtk-2.0";
    # The HM fcitx5 module writes these to home.sessionVariables only, which
    # interactive shells and the compositor pick up but systemd-launched desktop apps
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
      BAT_THEME = lib.mkDefault "base16";
    };
  };
}
