{
  pkgs,
  ...
}:

{
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.waylandFrontend = true;
    fcitx5.addons = with pkgs; [
      (fcitx5-rime.override {
        rimeDataPkgs = [
          rime-ice
        ];
      })
      fcitx5-nord
      fcitx5-gtk
      libsForQt5.fcitx5-qt
    ];

    fcitx5.settings.inputMethod = {
      "Groups/0" = {
        Name = "Default";
        "Default Layout" = "us";
        DefaultIM = "rime";
      };
      "Groups/0/Items/0".Name = "keyboard-us";
      "Groups/0/Items/1".Name = "rime";
    };

    fcitx5.settings.addons.classicui.globalSection = {
      Theme = "Nord-Dark";
      DarkTheme = "Nord-Dark";
    };
  };

  # Home Manager already generates fcitx5-daemon.service for the graphical
  # session. Mask the XDG autostart desktop file so Fcitx5 does not start twice.
  xdg.configFile."autostart/org.fcitx.Fcitx5.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Fcitx 5
    Hidden=true
  '';
}
