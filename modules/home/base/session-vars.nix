_:

{
  # 96 DPI × 1.5 scale = 144; tells X11/XWayland apps to render at native resolution
  xresources.properties."Xft.dpi" = 144;
  # Reaches systemd user session → niri (launched as systemd service) inherits these
  systemd.user.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    _JAVA_AWT_WM_NONREPARENTING = "1";
  };

  # Add ~/.local/bin to PATH (for pipx, cargo, agy, etc.)
  home.sessionPath = [ "$HOME/.local/bin" ];

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
