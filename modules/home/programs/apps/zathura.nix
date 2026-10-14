{
  pkgs,
  lib,
  config,
  ...
}:

let
  seedFile = import ../../../../lib/seed-file.nix { inherit lib pkgs; };
in

{
  programs.zathura = {
    enable = true;
    package = pkgs.zathura;

    extraConfig = "include noctaliarc";

    options = {
      # Technical manuals are easier to read at the window's full width.
      # `a` fits the whole page; `s` restores fit-to-width.
      adjust-open = "width";
      selection-clipboard = "clipboard";

      synctex = true;
      synctex-edit-modifier = "ctrl";

      scroll-page-aware = true;
      database = "sqlite";
      continuous-hist-save = true;

      # These configure recoloring; they do not switch it on. `recolor` itself
      # stays at its default of false, so a PDF opens with its real colours and
      # `^r` toggles the dark rendering these keys describe.
      #
      # The two *colours* are deliberately absent. noctalia's zathura template
      # already writes `recolor-lightcolor` and `recolor-darkcolor` into
      # noctaliarc from the live palette, and Home Manager emits `options`
      # *after* the `include` above -- so setting them here silently won that
      # override and pinned `^r` to Catppuccin (#1e1e2e / #cdd6f4) while the
      # rest of the window followed the desktop theme.
      recolor-keephue = true;
      recolor-reverse-video = true;

      # Keep the page counter, without a permanent scrollbar or long path.
      guioptions = "s";
      font = "Noto Sans CJK SC 11";
      page-v-padding = 12;
      page-h-padding = 12;
      statusbar-h-padding = 12;
      statusbar-v-padding = 5;
      statusbar-basename = true;
      statusbar-home-tilde = true;
      window-title-basename = true;
      statusbar-page-percent = false;
      incremental-search = true;
      selection-notification = false;
      scroll-step = 30;
      scroll-full-overlap = 0.15;
      zoom-step = 5;
    };
  };

  home.activation.seedZathuraNoctaliaTheme =
    seedFile.mkActivation "${config.xdg.configHome}/zathura/noctaliarc"
      { };
}
