# Seeded fcitx5 configuration files.
#
# Home Manager's input-method module would install the whole ~/.config/fcitx5
# as a read-only store link, but fcitx5 rewrites `profile` and addon
# preferences from its GUI. The directory therefore belongs to the user;
# input-method.nix seeds these two files only when they are missing and
# rime-checks.nix reads the classicui seed to assert the theme contract.
{ pkgs, palette }:
{
  profile = pkgs.writeText "fcitx5-profile" ''
    [Groups/0]
    Name=Default
    Default Layout=us
    DefaultIM=rime

    [Groups/0/Items/0]
    Name=keyboard-us

    [Groups/0/Items/1]
    Name=rime
  '';

  classicUi = pkgs.writeText "fcitx5-classicui.conf" ''
    PreferTextIcon=True
    TrayOutlineColor=#00000000
    Theme=onedark
    DarkTheme=onedark
    Font=${palette.fonts.cjk} 10
    Vertical Candidate List=False
    PerScreenDPI=False
  '';
}
