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

      recolor-keephue = true;
      recolor-reverse-video = true;
      recolor-lightcolor = "#1e1e2e";
      recolor-darkcolor = "#cdd6f4";

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
