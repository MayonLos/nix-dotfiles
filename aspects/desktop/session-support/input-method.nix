{ palette }:
{
  config,
  inputs,
  pkgs,
  lib,
  ...
}:
let
  # fcitx5 must own a writable ~/.config/fcitx5: it rewrites `profile` from the
  # GUI and the optional WeTypeX addon writes its preferences there. Home
  # Manager's input-method module would otherwise make the whole directory a
  # read-only store link. Seed the two static files once and let the running
  # application own the directory afterwards.
  seed = import ../../../lib/seed-file.nix { inherit lib pkgs; };
  configHome = config.home.homeDirectory + "/.config";
  fcitx5Config = import ./fcitx5-config.nix { inherit pkgs palette; };
  fcitx5Profile = fcitx5Config.profile;
  fcitx5ClassicUi = fcitx5Config.classicUi;
in
{
  # The KDE settings module needs systemsettings; fcitx5-configtool stays available.
  xdg.dataFile."applications/kcm_fcitx5.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Fcitx 5
    Hidden=true
  '';

  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      waylandFrontend = true;
      addons = with pkgs; [
        (import ./rime/package.nix { inherit pkgs; })
        # Optional second engine: the open WeTypeX adapter for the WeChat
        # input engine. Rime stays the DefaultIM and the group item below
        # only makes the engine switchable; AI/voice/layer-shell/WeType skin
        # are disabled to keep the closure small and let the repository theme
        # own the candidate UI. The proprietary runtime is a user-data step,
        # not a Nix build step: run once as the user
        #   fcitx5-wetypex-setup --download --accept-upstream-license
        # Data lives in ~/.local/share/fcitx5-wetypex and survives updates.
        (inputs.wetypex.packages.${pkgs.stdenv.hostPlatform.system}.fcitx5-wetypex.override {
          enableAI = false;
          enableVoice = false;
          enableLayerShell = false;
          enableWeTypeTheme = false;
        })
        fcitx5-gtk
        libsForQt5.fcitx5-qt
        qt6Packages.fcitx5-configtool
      ];

    };
  };

  # Replace the old read-only HM directory link (first switch after this
  # change) and seed the files once. The seeds are idempotent and never
  # overwrite a profile or classicui.conf the user edited later.
  home.activation = {
    fcitx5ReplaceManagedConfigDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -L "${configHome}/fcitx5" ]; then
        run rm "${configHome}/fcitx5"
      fi
    '';
    seedFcitx5Profile = lib.hm.dag.entryAfter [
      "writeBoundary"
      "fcitx5ReplaceManagedConfigDir"
    ] (seed.mkScript "${configHome}/fcitx5/profile" { source = fcitx5Profile; });
    seedFcitx5ClassicUi = lib.hm.dag.entryAfter [
      "writeBoundary"
      "seedFcitx5Profile"
    ] (seed.mkScript "${configHome}/fcitx5/conf/classicui.conf" { source = fcitx5ClassicUi; });
  };

  systemd.user.services.fcitx5-daemon = {
    Unit = {
      # force: Replace HM generic graphical target relationships with the selected session targets.
      PartOf = lib.mkForce config.nixDotfiles.graphicalSessionTargets;
      # force: Replace HM generic graphical target relationships with the selected session targets.
      After = lib.mkForce config.nixDotfiles.graphicalSessionTargets;
      # Restart when a seeded file changes so a rebuild applies profile/theme edits.
      X-Restart-Triggers = [
        "${fcitx5Profile}"
        "${fcitx5ClassicUi}"
      ];
    };
    # force: Replace HM generic graphical target relationships with the selected session targets.
    Install.WantedBy = lib.mkForce config.nixDotfiles.graphicalSessionTargets;
  };
  xdg = {
    dataFile = {
      "fcitx5/themes/onedark".source = import ./rime/theme.nix {
        inherit pkgs palette;
      };

      "fcitx5/rime/default.custom.yaml".text = ''
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

      "fcitx5/rime/rime_ice.custom.yaml".text = ''
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

      "fcitx5/rime/rime_ice_technical.dict.yaml".source = ./rime/rime_ice_technical.dict.yaml;
      "fcitx5/rime/nixdotfiles_technical.dict.yaml".source = ./rime/nixdotfiles_technical.dict.yaml;
    };
  };
}
