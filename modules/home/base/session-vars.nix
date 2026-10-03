{
  pkgs,
  pkgs-unstable,
  lib,
  ...
}:

let
  java = import ../../../lib/java.nix { inherit pkgs pkgs-unstable; };

  # Needed both by systemd user services (which do not source the shell profile)
  # and by interactive shells, so the same set is exported through both paths.
  shared = {
    NIXOS_OZONE_WL = "1";
    _JAVA_AWT_WM_NONREPARENTING = "1";
    # Qt apps started outside mango (systemd user units, desktop launchers)
    # need this too; base/qt.nix seeds the qt6ct palette. Octave pins itself
    # back to qt5ct in its own wrapper.
    QT_QPA_PLATFORMTHEME = "qt6ct";
    # The HM fcitx5 module writes these to home.sessionVariables only, which
    # interactive shells and mango pick up but systemd-launched desktop apps
    # do not (verified: systemd.user.sessionVariables had none). Same values,
    # exported through both paths.
    GLFW_IM_MODULE = "ibus";
    SDL_IM_MODULE = "fcitx";
    XMODIFIERS = "@im=fcitx";
    JAVA_HOME = "${java.jdks.${java.default}}";
  }
  // lib.mapAttrs' (version: jdk: lib.nameValuePair "JAVA${version}_HOME" "${jdk}") java.jdks;
in
{
  # Xft.dpi and the xrdb merge that actually delivers it live in xresources.nix.
  systemd.user.sessionVariables = shared;

  home = {
    sessionPath = [
      "${java.jdks.${java.default}}/bin"
      "$HOME/.local/bin"
    ];

    # IME variables now live in `shared` above; the HM fcitx5 module only
    # contributes the home-side set, so systemd-launched apps needed the
    # mirror to get them too.
    sessionVariables = shared // {
      EDITOR = "nvim";
      VISUAL = "nvim";
      # bat and delta share one syntax theme on purpose -- they were on
      # OneHalfDark and Nord respectively, so the same hunk looked different
      # depending on whether git paged it. bat ships no Tokyo Night, and its
      # only palette-following themes are 16-colour; Catppuccin Mocha is the
      # closest of the built-ins (#1e1e2e against the terminal's #1a1b26, same
      # blue-dark ground and pastel syntax family). `bat --list-themes` to see
      # the set.
      BAT_THEME = "Catppuccin Mocha";
    };
  };
}
