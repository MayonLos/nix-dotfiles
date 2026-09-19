{ pkgs, pkgs-unstable, ... }:

let
  temurin = pkgs.javaPackages.compiler.temurin-bin;
  # 26 is not in stable 26.05 yet.
  temurin-unstable = pkgs-unstable.javaPackages.compiler.temurin-bin;

  # Needed both by systemd user services (which do not source the shell profile)
  # and by interactive shells, so the same set is exported through both paths.
  shared = {
    NIXOS_OZONE_WL = "1";
    _JAVA_AWT_WM_NONREPARENTING = "1";
    JAVA8_HOME = "${temurin.jdk-8}";
    JAVA17_HOME = "${temurin.jdk-17}";
    JAVA21_HOME = "${temurin.jdk-21}";
    JAVA25_HOME = "${temurin.jdk-25}";
    JAVA26_HOME = "${temurin-unstable.jdk-26}";
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

    # GLFW_IM_MODULE / SDL_IM_MODULE / XMODIFIERS are not here: the
    # i18n.inputMethod.fcitx5 module sets all three itself.
    sessionVariables = shared // {
      EDITOR = "nvim";
      VISUAL = "nvim";
      # bat and delta share one syntax theme on purpose -- they were on
      # OneHalfDark and Nord respectively, so the same hunk looked different
      # depending on whether git paged it. bat ships no Tokyo Night, and its
      # only palette-following themes are 16-colour; Catppuccin Mocha is the
      # closest of the built-ins (#1e1e2e against the terminal's #1a1b26, same
      # blue-dark ground and pastel syntax family). `bat --list-themes` to see
      # the set. Kept in step with magit-delta in emacs/lisp/git-magit.el.
      BAT_THEME = "Catppuccin Mocha";
    };
  };
}
