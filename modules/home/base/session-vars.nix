_:

{
  xresources.properties."Xft.dpi" = 144;
  systemd.user.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    _JAVA_AWT_WM_NONREPARENTING = "1";
  };

  home.sessionPath = [ "$HOME/.local/bin" ];

  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    _JAVA_AWT_WM_NONREPARENTING = "1";
    XMODIFIERS = "@im=fcitx";
    EDITOR = "nvim";
    VISUAL = "nvim";
    BAT_THEME = "OneHalfDark";
  };
}
