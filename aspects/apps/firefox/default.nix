{
  imports = [
    ../../desktop/mango-session
    ../../appearance/appearance
  ];
  den.aspects.firefox = { user, ... }: {
    homeManager =
      {
        lib,
        pkgs,
        ...
      }:
      let
        firefoxWithManagedThemeAndExtensions = pkgs.firefox.override {
          extraPolicies = {
            ExtensionSettings = {
              # These synchronized theme add-ons override Firefox's dark theme.
              "{74da71cc-4d66-48f5-95d1-1f017f18ffab}".installation_mode = "blocked";
              "{443bf4af-0884-4c22-886b-21f936e899df}".installation_mode = "blocked";
              "{7efc2a80-496f-49b1-88db-4ddd7d312757}".installation_mode = "blocked";
              "{894e1fa0-bfe2-4ee8-ad01-6e9ff4092ad0}".installation_mode = "blocked";
              # The cleanup audit's two browser-side recommendations: paper
              # collection (Zotero) and content blocking. install_url pulls the
              # signed latest XPI from AMO on first start, so a fresh profile
              # needs network once; the extensions update themselves afterwards.
              "uBlock0@raymondhill.net" = {
                installation_mode = "force_installed";
                install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
              };
              "zotero@chnm.gmu.edu" = {
                installation_mode = "force_installed";
                install_url = "https://addons.mozilla.org/firefox/downloads/latest/zotero-connector/latest.xpi";
              };
            };
          };
          extraPrefs = ''
            lockPref("extensions.activeThemeID", "firefox-compact-dark@mozilla.org");
            lockPref("widget.use-xdg-desktop-portal.file-picker", 1);
          '';
        };
        firefoxChrome = pkgs.writeText "firefox-userChrome-fallback.css" (
          builtins.replaceStrings
            [
              "{{ colors.onedark_bg_value.default.hex }}"
              "{{ colors.onedark_surface_value.default.hex }}"
              "{{ colors.onedark_deep_value.default.hex }}"
              "{{ colors.onedark_selection_value.default.hex }}"
              "{{ colors.onedark_bright_fg_value.default.hex }}"
              "{{ colors.onedark_fg_value.default.hex }}"
              "{{ colors.onedark_blue_value.default.hex }}"
              "{{ colors.onedark_cyan_value.default.hex }}"
              "{{ colors.onedark_purple_value.default.hex }}"
            ]
            [
              user.appearance.bg
              user.appearance.surface
              user.appearance.deep
              user.appearance.selection
              user.appearance.brightFg
              user.appearance.fg
              user.appearance.blue
              user.appearance.cyan
              user.appearance.purple
            ]
            (builtins.readFile ./resources/userChrome.css)
        );
      in
      {
        xdg.mimeApps.enable = true;
        xdg.mimeApps.defaultApplications = {
          "x-scheme-handler/about" = [ "firefox.desktop" ];
          "x-scheme-handler/unknown" = [ "firefox.desktop" ];
        };
        home.packages = [ firefoxWithManagedThemeAndExtensions ];
        home.activation.seedFirefoxProfileUi = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          ${pkgs.python3}/bin/python3 ${./resources}/seed-firefox-ui.py ${firefoxChrome}
        '';
        assertions = [
          {
            assertion = user.appearance != null;
            message = "Select an appearance for the Firefox browser chrome fallback";
          }
        ];
      };
  };
}
