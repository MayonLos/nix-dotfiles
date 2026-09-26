{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
let
  zenChrome = "${config.xdg.configHome}/zen/default/chrome";
  zenOverrides = pkgs.writeText "zen-browser-overrides.css" ''
    /*
     * Small, stable UI refinements for Zen.
     *
     * Colors come from Noctalia's zen-browser template; keep geometry and
     * states here so a palette change does not require editing this file.
     */

    /* Give the navigation row a little breathing room without wasting space. */
    #zen-appcontent-navbar-container {
      padding: 6px 10px 0 !important;
    }

    #urlbar-background {
      border: 1px solid color-mix(in srgb, var(--outline) 70%, transparent) !important;
      border-radius: 12px !important;
      box-shadow: none !important;
      transition: border-color 140ms ease, box-shadow 140ms ease !important;
    }

    #urlbar[focused] > #urlbar-background {
      border-color: var(--primary) !important;
      box-shadow: 0 0 0 2px color-mix(in srgb, var(--primary) 22%, transparent) !important;
    }

    /* Make the vertical tab list read as a quiet stack of cards. */
    #zen-tabs-wrapper .tabbrowser-tab {
      margin: 2px 7px !important;
      border-radius: 10px !important;
      min-height: 34px !important;
    }

    #zen-tabs-wrapper .tab-background {
      border-radius: 10px !important;
      transition: background-color 140ms ease, box-shadow 140ms ease !important;
    }

    #zen-tabs-wrapper .tabbrowser-tab[selected] .tab-background {
      background: color-mix(in srgb, var(--hl_low) 88%, var(--primary)) !important;
      box-shadow: inset 2px 0 0 var(--primary) !important;
    }

    #zen-tabs-wrapper .tabbrowser-tab:hover:not([selected]) .tab-background {
      background: color-mix(in srgb, var(--hl_med) 72%, transparent) !important;
    }

    /* Keep the workspace switcher visually aligned with the tab cards. */
    #zen-workspaces-button,
    #zen-sidebar-top-buttons {
      border-radius: 12px !important;
    }

    #zen-workspaces-button {
      margin: 6px 7px !important;
      border: 1px solid color-mix(in srgb, var(--outline) 45%, transparent) !important;
    }

    #zen-sidebar-splitter {
      width: 4px !important;
    }

    /* A soft frame around page content keeps browser chrome distinct. */
    #zen-tabbox-wrapper {
      border-radius: 14px 0 0 0 !important;
      overflow: clip !important;
    }

    /* Reduce visual noise from disabled toolbar actions. */
    toolbar .toolbarbutton-1[disabled] > .toolbarbutton-icon {
      opacity: 0.38 !important;
    }
  '';
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
    fi

    if [ ! -e "${zenChrome}/userContent.css" ]; then
      run mkdir -p "${zenChrome}"
      run ${pkgs.coreutils}/bin/install -m 0644 /dev/null "${zenChrome}/userContent.css"
    fi

    # Keep the visual tweaks separate from Noctalia's generated import. This
    # file is deliberately mutable in the profile, but refreshed from the
    # declarative source on activation so CSS changes remain reproducible.
    run ${pkgs.coreutils}/bin/install -m 0644 ${zenOverrides} "${zenChrome}/mayon-overrides.css"
    if ! ${pkgs.gnugrep}/bin/grep -Fq '@import "mayon-overrides.css";' "${zenChrome}/userChrome.css"; then
      printf '%s\n' '@import "mayon-overrides.css";' >> "${zenChrome}/userChrome.css"
    fi
  '';
}
