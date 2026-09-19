_: {
  # Tokyo Night, `night` variant: background #1a1b26, which is exactly what
  # noctalia renders into kitty's palette. That is the point of the choice --
  # the whole host runs one scheme, and noctalia is its source of truth
  # (modules/home/wm/mango/noctalia.nix drives kitty, gtk, qt, mango, btop,
  # cava, yazi, zathura, vscode and zen from the live theme). nvim, Emacs,
  # tmux and fcitx5 cannot read that palette at runtime, so they are pinned to
  # the same scheme by hand instead -- the two-tier rule in the desktop-apps
  # skill.
  #
  # `storm` and `moon` are the lighter siblings; theme.nix can switch between
  # all four at runtime without a rebuild.
  colorschemes.tokyonight = {
    enable = true;
    settings = {
      style = "night";
      styles.comments.italic = true;
      # Float borders and the sidebar keep the buffer's own background --
      # highlights.nix then makes NormalFloat fully transparent on top of it,
      # for the reason documented there.
      styles.floats = "transparent";
      styles.sidebars = "transparent";
    };
  };
}
