{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
let
  zenChrome = "${config.xdg.configHome}/zen/default/chrome";
in
{
  imports = [ inputs.zen-browser.homeModules.default ];

  programs.zen-browser = {
    enable = true;
    profiles.default = {
      id = 0;
      isDefault = true;
      settings = {
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
      };
    };
  };

  home.activation.seedZenChrome = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -e "${zenChrome}/userChrome.css" ]; then
      run mkdir -p "${zenChrome}"
      run ${pkgs.coreutils}/bin/install -m 0644 /dev/null "${zenChrome}/userChrome.css"
      run ${pkgs.coreutils}/bin/install -m 0644 /dev/null "${zenChrome}/userContent.css"
    fi
  '';
}
