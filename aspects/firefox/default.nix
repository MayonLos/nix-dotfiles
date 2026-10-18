_: {
  den.quirks.noctaliaIntegrations.description = "Selected applications requesting Noctalia palette integration";
  den.aspects.firefox = { user, ... }: {
    noctaliaIntegrations = [ "firefox" ];
    homeManager =
      { lib, pkgs, ... }:
      let
        firefoxAddons = {
          darkReader = pkgs.fetchurl {
            name = "darkreader-4.9.133.xpi";
            url = "https://addons.mozilla.org/firefox/downloads/file/5055786/darkreader-4.9.133.xpi";
            hash = "sha256-6wbFCW12FhbH8dlUwRUkykv/T+cikETcH84oiowIU6s=";
          };
        };
        firefoxWithManagedThemeAndExtensions = pkgs.firefox.override {
          extraPolicies = {
            ExtensionSettings = {
              "addon@darkreader.org" = {
                installation_mode = "force_installed";
                install_url = "file://${firefoxAddons.darkReader}";
                updates_disabled = true;
              };
              # These synchronized theme add-ons override Firefox's dark theme.
              "{74da71cc-4d66-48f5-95d1-1f017f18ffab}".installation_mode = "blocked";
              "{443bf4af-0884-4c22-886b-21f936e899df}".installation_mode = "blocked";
              "{7efc2a80-496f-49b1-88db-4ddd7d312757}".installation_mode = "blocked";
              "{894e1fa0-bfe2-4ee8-ad01-6e9ff4092ad0}".installation_mode = "blocked";
            };
          };
          extraPrefs = ''
            lockPref("extensions.activeThemeID", "firefox-compact-dark@mozilla.org");
          '';
        };
        firefoxChrome = pkgs.writeText "firefox-userChrome-fallback.css" (
          builtins.replaceStrings
            [
              "{{ colors.surface.default.hex }}"
              "{{ colors.surface_container_lowest.default.hex }}"
              "{{ colors.surface_container_high.default.hex }}"
              "{{ colors.on_surface.default.hex }}"
              "{{ colors.on_surface_variant.default.hex }}"
              "{{ colors.primary.default.hex }}"
              "{{ colors.tertiary.default.hex }}"
              "{{ colors.secondary.default.hex }}"
            ]
            [
              user.appearance.bg
              user.appearance.deep
              user.appearance.selection
              user.appearance.fg
              user.appearance.muted
              user.appearance.blue
              user.appearance.purple
              user.appearance.cyan
            ]
            (builtins.readFile ./resources/noctalia-userChrome.css)
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
