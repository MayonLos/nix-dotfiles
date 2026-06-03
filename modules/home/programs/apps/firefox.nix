{
  config,
  ...
}:

{
  programs.firefox = {
    enable = true;
    configPath = "${config.xdg.configHome}/mozilla/firefox";

    profiles.default = {
      id = 0;
      name = "default";

      userChrome = ''
        #TabsToolbar {
          visibility: collapse !important;
        }

        .titlebar-buttonbox-container {
          display: none !important;
        }

        #titlebar {
          margin-bottom: -45px !important;
        }

        #nav-bar {
          margin-top: -2px !important;
        }
      '';

    };
  };
}
