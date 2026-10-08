{
  pkgs,
  ...
}:

{
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      waylandFrontend = true;
      addons = with pkgs; [
        (fcitx5-rime.override {
          rimeDataPkgs = [
            pkgs.rime-ice
          ];
        })
        # The candidate window floats over whatever application has focus, so
        # it is the one surface that should match the *desktop* rather than
        # carry taste of its own. noctalia drives everything else here to Tokyo
        # Night; Nord-Dark was the last thing still disagreeing with it.
        # Storm rather than Day: the live palette's background is #1a1b26.
        fcitx5-tokyonight
        fcitx5-gtk
        libsForQt5.fcitx5-qt
        qt6Packages.fcitx5-configtool
      ];

      settings = {
        inputMethod = {
          "Groups/0" = {
            Name = "Default";
            "Default Layout" = "us";
            DefaultIM = "rime";
          };
          "Groups/0/Items/0".Name = "keyboard-us";
          "Groups/0/Items/1".Name = "rime";
        };

        addons.classicui.globalSection = {
          Theme = "Tokyonight-Mayon";
          DarkTheme = "Tokyonight-Mayon";
          Font = "Noto Sans CJK SC 10";
          "Vertical Candidate List" = "True";

          # No ForceWaylandDPI here. It was tried on 2026-08-21 and is wrong:
          # classicui already gets 1.5 from wp_fractional_scale_v1 on Wayland
          # and multiplies the DPI by it, so forcing 144 renders the popup at
          # 144 x 1.5 and every native client's candidate window grew by half
          # again. The Wayland path needs no correction.
          #
          # QQ is not the X11 exception anymore: im.nix pins it to Wayland, so
          # its input goes through text-input-v3 and this setting cannot affect
          # it. wechat-uos pins QT_QPA_PLATFORM=xcb, so it uses the X11 half of
          # classicui; that half is governed by PerScreenDPI and Xft.dpi.
          #
          # At its True default, fcitx5 derives the DPI from what Xwayland
          # reports for the screen — 2560x1600 in 677x423 mm, i.e. 96 — and
          # ignores Xft.dpi entirely. False makes it read Xft.dpi, which
          # base/xresources.nix sets to 144 and, more to the point, actually
          # merges into the running server.
          PerScreenDPI = "False";
        };
      };
    };
  };

  home = {
    # Compact the packaged theme's padding and improve contrast, including
    # its black-on-dark context menu. DPI still follows the client protocol.
    file.".local/share/fcitx5/themes/Tokyonight-Mayon/theme.conf".text =
      let
        themeDir = "${pkgs.fcitx5-tokyonight}/share/fcitx5/themes/Tokyonight-Storm";
      in
      builtins.replaceStrings
        [
          "Name=Tokyonight-storm"
          "#222436"
          "#000000"
          "#62a0ea"
          "#82aaff"
          "Image=radio.png"
          "Image=arrow.png"
          "Left=10"
          "Right=10"
          "Top=7"
          "Bottom=7"
          "Top=6"
          "Bottom=6"
        ]
        [
          "Name=Tokyonight-Mayon"
          "#1a1b26"
          "#c0caf5"
          "#7aa2f7"
          "#c0caf5"
          "Image=${themeDir}/radio.png"
          "Image=${themeDir}/arrow.png"
          "Left=7"
          "Right=7"
          "Top=3"
          "Bottom=3"
          "Top=3"
          "Bottom=3"
        ]
        (builtins.readFile "${themeDir}/theme.conf");

    file.".local/share/fcitx5/rime/default.custom.yaml".text = ''
      patch:
        __include: rime_ice_suggestion:/

        schema_list:
          - schema: rime_ice

        menu/page_size: 5

        key_binder/bindings/+:
          - { when: paging, accept: comma, send: Page_Up }
          - { when: has_menu, accept: period, send: Page_Down }

        ascii_composer/good_old_caps_lock: true
    '';

    file.".local/share/fcitx5/rime/rime_ice.custom.yaml".text = ''
      patch:
        # Explicitly retain learning and sentence composition for personal words.
        translator/enable_user_dict: true
        translator/enable_sentence: true
        # Lower short English collisions while retaining mixed-language input.
        reduce_english_filter/mode: all
    '';
  };
}
