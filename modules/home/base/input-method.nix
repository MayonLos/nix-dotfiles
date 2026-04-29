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
          pkgs.rime-ice
        ];
      })
      fcitx5-nord
      fcitx5-gtk
      libsForQt5.fcitx5-qt
      qt6Packages.fcitx5-configtool
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

  home.file.".local/share/fcitx5/rime/default.custom.yaml".text = ''
    patch:
      __include: rime_ice_suggestion:/

      schema_list:
        - schema: rime_ice

      menu/page_size: 9

      key_binder/bindings/+:
        - { when: paging, accept: comma, send: Page_Up }
        - { when: has_menu, accept: period, send: Page_Down }

      ascii_composer/good_old_caps_lock: true
  '';

  home.sessionVariables = {
    GLFW_IM_MODULE = "ibus";
  };
}
