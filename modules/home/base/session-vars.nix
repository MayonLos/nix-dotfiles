{ pkgs, ... }:

let
  temurin = pkgs.javaPackages.compiler.temurin-bin;

  # Needed both by systemd user services (which do not source the shell profile)
  # and by interactive shells, so the same set is exported through both paths.
  shared = {
    NIXOS_OZONE_WL = "1";
    _JAVA_AWT_WM_NONREPARENTING = "1";
    JAVA8_HOME = "${temurin.jdk-8}";
    JAVA17_HOME = "${temurin.jdk-17}";
    JAVA21_HOME = "${temurin.jdk-21}";
    JAVA25_HOME = "${temurin.jdk-25}";
    JAVA_HOME = "${temurin.jdk-25}";
  };
in
{
  # Xft.dpi and the xrdb merge that actually delivers it live in xresources.nix.
  systemd.user.sessionVariables = shared;

  home = {
    sessionPath = [
      "${temurin.jdk-25}/bin"
      "$HOME/.local/bin"
    ];

    sessionVariables = shared // {
      XMODIFIERS = "@im=fcitx";
      EDITOR = "nvim";
      VISUAL = "nvim";
      BAT_THEME = "OneHalfDark";
    };
  };
}
