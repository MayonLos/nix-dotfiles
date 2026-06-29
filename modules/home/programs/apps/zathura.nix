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

    # Noctalia app-theming: the `zathura` community template renders the palette
    # to ~/.config/zathura/noctaliarc (a separate file) and only dbus-reloads
    # zathura — it never touches zathurarc. So we `include` it ourselves at the
    # end of zathurarc; appended last, its recolor-* colors override the static
    # ones below, making zathura follow the live theme. zathurarc stays a clean
    # read-only HM symlink (the template never rewrites it).
    extraConfig = "include noctaliarc";

    options = {
      adjust-open = "best-fit";
      selection-clipboard = "clipboard";

      synctex = true;
      synctex-edit-modifier = "ctrl";

      smooth-reload = true;
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

  # zathura warns (but still loads) on a missing include; seed an empty (valid)
  # noctaliarc if noctalia hasn't rendered it yet. Mutable — noctalia owns it.
  home.activation.seedZathuraNoctaliaTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -e "${config.xdg.configHome}/zathura/noctaliarc" ]; then
      run mkdir -p "${config.xdg.configHome}/zathura"
      run ${pkgs.coreutils}/bin/install -m 0644 /dev/null "${config.xdg.configHome}/zathura/noctaliarc"
    fi
  '';
}
