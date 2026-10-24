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
        (import ./rime/package.nix { inherit pkgs; })
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
          Font = "${palette.fonts.cjk} 13";
          "Vertical Candidate List" = "False";

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
    dataFile."fcitx5/themes/One-Dark-Darker".source = import ./rime/theme.nix {
      inherit pkgs palette;
    };

    dataFile."fcitx5/rime/default.custom.yaml".text = ''
      patch:
        __include: rime_ice_suggestion:/

        schema_list:
          - schema: rime_ice

        menu/page_size: 7

        key_binder/bindings/+:
          - { when: paging, accept: comma, send: Page_Up }
          - { when: has_menu, accept: period, send: Page_Down }

        ascii_composer/good_old_caps_lock: true
    '';

    dataFile."fcitx5/rime/rime_ice.custom.yaml".text = ''
      patch:
        # Conservative model weights recommended by rime-frost's README:
        # https://github.com/gaboolic/rime-frost#使用语言模型
        # Keep our existing Rime-Ice dictionary and all of its Lua processors.
        grammar:
          language: wanxiang-lts-zh-hans
          non_collocation_penalty: -4
          collocation_max_length: 5
          collocation_min_length: 2
          collocation_penalty: -14
        translator/contextual_suggestions: true
        translator/max_homophones: 4
        translator/max_homographs: 2
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
