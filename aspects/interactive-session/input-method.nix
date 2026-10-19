{ palette }:
{
  config,
  pkgs,
  lib,
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
          rimeDataPkgs = [ pkgs.rime-ice ];
        })
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
          Theme = "One-Dark-Darker";
          DarkTheme = "One-Dark-Darker";
          Font = "${palette.fonts.sans} 10";
          "Vertical Candidate List" = "True";

          # Wayland already scales classicui through wp_fractional_scale_v1.
          # Do not force 144 DPI there: it would multiply the scale twice.
          # QQ uses Wayland in Mango and X11 in dwm; X11 clients therefore
          # reads the merged Xft.dpi value through PerScreenDPI.
          PerScreenDPI = "False";
        };
      };
    };
  };

  systemd.user.services.fcitx5-daemon = {
    Unit.PartOf = lib.mkForce config.nixDotfiles.graphicalSessionTargets;
    Unit.After = lib.mkForce config.nixDotfiles.graphicalSessionTargets;
    Install.WantedBy = lib.mkForce config.nixDotfiles.graphicalSessionTargets;
  };
  xdg = {
    dataFile."fcitx5/themes/One-Dark-Darker/theme.conf".text = ''
      [Metadata]
      Name=One-Dark-Darker
      Version=1
      Author=mayon
      Description=One Dark Darker
      ScaleWithDPI=True

      [InputPanel]
      NormalColor=${palette.brightFg}
      HighlightColor=${palette.brightFg}
      HighlightCandidateColor=${palette.black}
      HighlightBackgroundColor=${palette.blue}
      FullWidthHighlight=True
      PageButtonAlignment=Bottom

      [InputPanel/Background]
      Color=${palette.bg}
      BorderColor=${palette.border}
      BorderWidth=1

      [InputPanel/Background/Margin]
      Left=2
      Right=2
      Top=2
      Bottom=2

      [InputPanel/Highlight]
      Color=${palette.blue}

      [InputPanel/Highlight/Margin]
      Left=7
      Right=7
      Top=3
      Bottom=3

      [InputPanel/ContentMargin]
      Left=0
      Right=0
      Top=0
      Bottom=0

      [InputPanel/TextMargin]
      Left=7
      Right=7
      Top=3
      Bottom=3

      [InputPanel/PrevPage]
      Image=${pkgs.fcitx5}/share/fcitx5/themes/default-dark/prev.png

      [InputPanel/NextPage]
      Image=${pkgs.fcitx5}/share/fcitx5/themes/default-dark/next.png

      [Menu/CheckBox]
      Image=${pkgs.fcitx5}/share/fcitx5/themes/default-dark/radio.png

      [Menu/SubMenu]
      Image=${pkgs.fcitx5}/share/fcitx5/themes/default-dark/arrow.png

      [Menu]
      NormalColor=${palette.brightFg}
      HighlightCandidateColor=${palette.black}

      [Menu/Background]
      Color=${palette.bg}
      BorderColor=${palette.border}
      BorderWidth=1

      [Menu/Background/Margin]
      Left=2
      Right=2
      Top=2
      Bottom=2

      [Menu/Highlight]
      Color=${palette.blue}

      [Menu/Highlight/Margin]
      Left=7
      Right=7
      Top=3
      Bottom=3

      [Menu/ContentMargin]
      Left=2
      Right=2
      Top=2
      Bottom=2

      [Menu/TextMargin]
      Left=5
      Right=5
      Top=3
      Bottom=3
    '';

    dataFile."fcitx5/rime/default.custom.yaml".text = ''
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

    dataFile."fcitx5/rime/rime_ice.custom.yaml".text = ''
      patch:
        # Retain learning and sentence composition for personal words.
        translator/enable_user_dict: true
        translator/enable_sentence: true
        # Read the upstream Rime-Ice dictionary plus our small supplemental
        # table, while keeping writes in the existing rime_ice.userdb.
        translator/dictionary: rime_ice_technical
        translator/user_dict: rime_ice
        # Lower short English collisions while retaining mixed-language input.
        reduce_english_filter/mode: all
    '';

    dataFile."fcitx5/rime/rime_ice_technical.dict.yaml".source = ./rime/rime_ice_technical.dict.yaml;
    dataFile."fcitx5/rime/nixdotfiles_technical.dict.yaml".source =
      ./rime/nixdotfiles_technical.dict.yaml;
  };
}
