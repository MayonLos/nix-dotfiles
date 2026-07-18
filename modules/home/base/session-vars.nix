{ pkgs, ... }:

{
  xresources.properties."Xft.dpi" = 144;
  systemd.user.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    _JAVA_AWT_WM_NONREPARENTING = "1";
    JAVA8_HOME = "${pkgs.javaPackages.compiler.temurin-bin.jdk-8}";
    JAVA17_HOME = "${pkgs.javaPackages.compiler.temurin-bin.jdk-17}";
    JAVA21_HOME = "${pkgs.javaPackages.compiler.temurin-bin.jdk-21}";
    JAVA25_HOME = "${pkgs.javaPackages.compiler.temurin-bin.jdk-25}";
    JAVA_HOME = "${pkgs.javaPackages.compiler.temurin-bin.jdk-25}";
  };

  home.sessionPath = [
    "${pkgs.javaPackages.compiler.temurin-bin.jdk-25}/bin"
    "$HOME/.local/bin"
  ];

  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    _JAVA_AWT_WM_NONREPARENTING = "1";
    JAVA8_HOME = "${pkgs.javaPackages.compiler.temurin-bin.jdk-8}";
    JAVA17_HOME = "${pkgs.javaPackages.compiler.temurin-bin.jdk-17}";
    JAVA21_HOME = "${pkgs.javaPackages.compiler.temurin-bin.jdk-21}";
    JAVA25_HOME = "${pkgs.javaPackages.compiler.temurin-bin.jdk-25}";
    JAVA_HOME = "${pkgs.javaPackages.compiler.temurin-bin.jdk-25}";
    XMODIFIERS = "@im=fcitx";
    EDITOR = "nvim";
    VISUAL = "nvim";
    BAT_THEME = "OneHalfDark";
  };
}
