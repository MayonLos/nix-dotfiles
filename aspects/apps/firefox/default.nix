{ inputs, ... }:
{
  imports = [
    ../../desktop/mango-session
    ../../appearance/appearance
  ];
  den.aspects.firefox = { user, ... }: {
    noctaliaIntegrations = [
      {
        id = "firefox";
        templateFile = ./resources/noctalia-userChrome.css;
        hookDirectory = ./resources;
      }
    ];
    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        firefoxNoctaliaPaletteColors = {
          onedark_bg = user.appearance.bg;
          onedark_deep = user.appearance.deep;
          onedark_surface = user.appearance.surface;
          onedark_selection = user.appearance.selection;
          onedark_bright_fg = user.appearance.brightFg;
          onedark_fg = user.appearance.fg;
          onedark_muted = user.appearance.muted;
          onedark_border = user.appearance.border;
          onedark_blue = user.appearance.blue;
          onedark_black = user.appearance.black;
          onedark_red = user.appearance.red;
          onedark_purple = user.appearance.purple;
          onedark_cyan = user.appearance.cyan;
        };
        firefoxWithManagedThemeAndExtensions = pkgs.firefox.override {
          extraPolicies = {
            ExtensionSettings = {
              # These synchronized theme add-ons override Firefox's dark theme.
              "{74da71cc-4d66-48f5-95d1-1f017f18ffab}".installation_mode = "blocked";
              "{443bf4af-0884-4c22-886b-21f936e899df}".installation_mode = "blocked";
              "{7efc2a80-496f-49b1-88db-4ddd7d312757}".installation_mode = "blocked";
              "{894e1fa0-bfe2-4ee8-ad01-6e9ff4092ad0}".installation_mode = "blocked";
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
            (builtins.readFile ./resources/noctalia-userChrome.css)
        );
      in
      {
        imports = [ inputs.noctalia.homeModules.default ];
        programs.noctalia.settings.theme.templates.custom_colors =
          lib.mkIf config.programs.noctalia.enable
            (
              lib.mapAttrs (_: color: {
                inherit color;
                blend = false;
              }) firefoxNoctaliaPaletteColors
            );
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
