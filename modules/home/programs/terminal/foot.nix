{
  pkgs,
  lib,
  config,
  ...
}:
let
  # Noctalia's foot template renders the active palette to this file
  # (output_path = $XDG_CONFIG_HOME/foot/themes/noctalia). We `include` it from
  # foot.ini below so foot follows the live theme. Declaring the include here —
  # rather than letting the template's apply.sh sed it into foot.ini — keeps
  # foot.ini a clean read-only HM symlink: apply.sh sees the include already
  # present (`grep include.*noctalia`) and skips its rewrite.
  noctaliaTheme = "${config.xdg.configHome}/foot/themes/noctalia";
in
{
  programs.foot = {
    enable = true;
    package = pkgs.foot;
    settings = {
      main = {
        term = "xterm-256color";
        font = "JetBrainsMono Nerd Font:size=8";
        dpi-aware = "yes";
        include = noctaliaTheme; # noctalia-rendered palette (colors-dark)
      };

      mouse = {
        hide-when-typing = "yes";
        alternate-scroll-mode = "yes";
      };

      cursor = {
        style = "beam";
        blink = "yes";
        blink-rate = "500";
        beam-thickness = "1.5";
      };

      scrollback = {
        lines = 5000;
        multiplier = "5.0";
        indicator-position = "relative";
      };

      colors-dark = {
        alpha = "0.8";
      };

      url = {
        launch = "xdg-open \${url}";
        osc8-underline = "url-mode";
      };

      desktop-notifications = {
        inhibit-when-focused = "yes";
      };

      tweak = {
        font-monospace-warn = "no";
        grapheme-shaping = "yes";
      };

      key-bindings = {
        show-urls-launch = "Control+Shift+o";
        show-urls-copy = "Control+Shift+p";
        scrollback-up-half-page = "Control+u";
        scrollback-down-half-page = "Control+d";
        scrollback-home = "Control+Shift+Home";
        scrollback-end = "Control+Shift+End";
        search-start = "Control+Shift+r";
        font-increase = "Control+equal";
        font-decrease = "Control+minus";
        font-reset = "Control+0";
      };
    };
  };

  # foot refuses to start on a missing `include` target, so seed an empty (valid)
  # theme file if noctalia hasn't rendered it yet. Mutable, non-HM-managed —
  # noctalia overwrites it on every theme change.
  home.activation.seedFootNoctaliaTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -e "${noctaliaTheme}" ]; then
      run mkdir -p "$(dirname "${noctaliaTheme}")"
      run ${pkgs.coreutils}/bin/install -m 0644 /dev/null "${noctaliaTheme}"
    fi
  '';
}
