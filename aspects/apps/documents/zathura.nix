{ palette }:
{
  pkgs,
  lib,
  config,
  ...
}:

let
  seedFile = import ../../../lib/seed-file.nix { inherit lib pkgs; };
  theme = if palette == null then null else import ./templates.nix { inherit pkgs palette; };
in

{
  programs.zathura = {
    enable = true;
    package = pkgs.zathura;

    extraConfig = ''
      include noctaliarc
      map <F4> toggle_statusbar
    '';

    options = {
      # Open with the whole page visible. `s` still switches to fit-to-width.
      adjust-open = "best-fit";
      selection-clipboard = "clipboard";

      synctex = true;
      synctex-edit-modifier = "ctrl";

      scroll-page-aware = true;
      database = "sqlite";
      continuous-hist-save = true;

      # Keep PDF recoloring off by default so documents open with their original
      # colors; `^r` can still toggle the dark rendering described by the
      # feature-owned palette template.
      #
      # The recolor colors live in the feature-owned palette template. This
      # keeps the declared default at false while making `^r` use
      # the same colors as the rest of the application.
      recolor = false;
      recolor-keephue = true;
      recolor-reverse-video = true;

      # Keep the canvas clear; F4 toggles the native statusbar when needed.
      guioptions = "";
      statusbar-page-percent = true;
      statusbar-basename = false;
      window-title-basename = false;
      font = "${if palette == null then "monospace" else palette.fonts.mono} 10";
      page-v-padding = 24;
      page-h-padding = 24;
      statusbar-h-padding = 12;
      statusbar-v-padding = 5;
      statusbar-home-tilde = true;
      incremental-search = true;
      selection-notification = false;
      scroll-step = 30;
      scroll-full-overlap = 0.15;
      zoom-step = 5;
    };
  };

  home.activation.seedZathuraNoctaliaTheme =
    seedFile.mkActivation "${config.xdg.configHome}/zathura/noctaliarc"
      {
        source = if theme == null then null else theme.zathura;
      };
}
