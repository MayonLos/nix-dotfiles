{
  pkgs,
  lib,
  config,
  ...
}:

{
  programs.zathura = {
    enable = true;
    package = pkgs.zathura;

    extraConfig = "include noctaliarc";

    options = {
      adjust-open = "best-fit";
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

      guioptions = "sv";
      statusbar-home-tilde = true;
      window-title-basename = true;
      statusbar-page-percent = true;
      incremental-search = true;
      selection-notification = false;
      zoom-step = 10;
    };
  };

  home.activation.seedZathuraNoctaliaTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -e "${config.xdg.configHome}/zathura/noctaliarc" ]; then
      run mkdir -p "${config.xdg.configHome}/zathura"
      run ${pkgs.coreutils}/bin/install -m 0644 /dev/null "${config.xdg.configHome}/zathura/noctaliarc"
    fi
  '';
}
