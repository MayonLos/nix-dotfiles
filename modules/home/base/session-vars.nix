_:

{
  # Reaches systemd user session → niri (launched as systemd service) inherits these
  systemd.user.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    _JAVA_AWT_WM_NONREPARENTING = "1";
  };

  # Reaches shell sessions (terminals)
  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    _JAVA_AWT_WM_NONREPARENTING = "1";
    XMODIFIERS = "@im=fcitx";
    EDITOR = "nvim";
    VISUAL = "nvim";
    BAT_THEME = "OneHalfDark";
  };
}
