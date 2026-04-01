{ pkgs, ... }:
{
  programs.foot = {
    enable = true;
    package = pkgs.foot;
    settings = {
      main = {
        term = "xterm-256color";
        font = "JetBrainsMono Nerd Font:size=8";
        dpi-aware = "yes";
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

      colors = {
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
}
