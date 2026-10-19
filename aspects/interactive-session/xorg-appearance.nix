{ palette }:
{
  config,
  lib,
  pkgs,
  hostFacts,
  ...
}:
let
  reducedMotion = palette.reducedMotion or false;
  # Picom uses physical pixels; Rofi uses em and Dunst derives its scale from Xft.
  px = n: builtins.floor (n * hostFacts.display.x11Dpi / 96.0 + 0.5);
  inherit (config.lib.formats.rasi) mkLiteral;
  literalAttrs = builtins.mapAttrs (_: mkLiteral);
in
{
  # Lifecycle and D-Bus activation are owned by xorg.nix's session target.
  services.picom = {
    enable = true;
    package = pkgs.picom;
    # The HM defaults emit legacy opacity/wintypes options, which Picom 13
    # ignores when modern rules are present. Keep one rules vocabulary.
    settings = lib.mkForce {
      backend = "glx";
      vsync = true;
      use-damage = true;
      fading = false;
      shadow = false;
      shadow-radius = px 16;
      shadow-opacity = 0.30;
      shadow-offset-x = -(px 12);
      shadow-offset-y = -(px 8);
      shadow-color = palette.black;
      crop-shadow-to-monitor = true;
      # Solid reading surfaces do not need continuous background blur.
      blur-method = "none";
      # Keep composition stable when notifications appear over fullscreen apps.
      unredir-if-possible = false;
    };
    # libconfig group lists require parentheses, not HM's scalar-array writer.
    # Native v13 presets: https://github.com/yshui/picom/blob/v13/man/picom.1.adoc
    # Our configured dwm owns _MAYON_DWM_FLOATING on each managed client.
    # The @ condition reads the property on the client window.
    extraConfig = ''
      rules = (
        { corner-radius = ${toString (px 12)}; shadow = false; dim = 0.0; },
        {
          match = "_MAYON_DWM_FLOATING@ = 1 || class_g = 'Rofi' || class_g = 'Dunst'";
          shadow = true;
        },
        ${lib.optionalString (!reducedMotion) ''
          {
            match = "!fullscreen && !override_redirect && (window_type = 'normal' || window_type = 'dialog')";
            animations = (
              { triggers = [ "open" ]; preset = "appear"; duration = 0.16; scale = 0.97; },
              { triggers = [ "close" ]; preset = "disappear"; duration = 0.12; scale = 0.98; }
            );
          },
          {
            match = "!fullscreen && _MAYON_DWM_FLOATING@ = 1";
            animations = (
              { triggers = [ "show" ]; preset = "appear"; duration = 0.14; scale = 0.98; },
              { triggers = [ "hide" ]; preset = "disappear"; duration = 0.10; scale = 0.98; }
            );
          },
        ''}
        # These clients draw their own rounded surfaces.
        { match = "class_g = 'Rofi' || class_g = 'Dunst'"; corner-radius = 0; },
        {
          match = "window_type = 'dock' || window_type = 'desktop'";
          corner-radius = 0;
          shadow = false;
        },
        # Rules disable Picom's implicit fullscreen corner exclusion; restore it.
        { match = "fullscreen"; corner-radius = 0; shadow = false; blur-background = false; }
      );
    '';
  };

  programs.rofi = {
    enable = true;
    package = pkgs.rofi;
    font = "${palette.fonts.sans} 10.5";
    terminal = "${pkgs.kitty}/bin/kitty";
    cycle = false;
    modes = [
      "drun"
      "window"
      "run"
    ];
    extraConfig = {
      show-icons = true;
      icon-theme = palette.iconTheme;
      matching = "fuzzy";
      sort = true;
      display-drun = "应用";
      display-window = "窗口";
      display-run = "命令";
      drun-display-format = "{name}";
      window-format = "{w} · {t}";
      disable-history = false;
    };
    theme = {
      "*" = literalAttrs {
        background-color = "transparent";
        text-color = palette.brightFg;
        border-color = palette.border;
        spacing = "0.6em";
      };
      window = literalAttrs {
        background-color = palette.bg;
        width = "calc(44em min 92%)";
        border = "${toString (px 1)}px";
        border-radius = "0.9em";
        padding = "1.0em";
      };
      mainbox.children = map mkLiteral [
        "inputbar"
        "message"
        "listview"
        "mode-switcher"
      ];
      inputbar =
        literalAttrs {
          background-color = palette.surface;
          border-radius = "0.5em";
          padding = "0.7em 0.9em";
          spacing = "0.8em";
        }
        // {
          children = map mkLiteral [
            "prompt"
            "entry"
            "case-indicator"
          ];
        };
      prompt = literalAttrs { text-color = palette.blue; };
      entry = {
        placeholder = "搜索…";
        placeholder-color = mkLiteral palette.fg;
        cursor-color = mkLiteral palette.blue;
      };
      listview = {
        lines = 8;
        columns = 1;
        fixed-height = true;
        dynamic = false;
        scrollbar = true;
        spacing = mkLiteral "0.25em";
      };
      element = literalAttrs {
        padding = "0.55em 0.7em";
        border-radius = "0.45em";
        spacing = "0.7em";
      };
      "element normal.normal, element alternate.normal" = literalAttrs {
        background-color = "transparent";
        text-color = palette.brightFg;
      };
      "element selected.normal, element selected.active" = literalAttrs {
        background-color = palette.blue;
        text-color = palette.black;
      };
      "element normal.active, element alternate.active" = literalAttrs {
        background-color = palette.selection;
        text-color = palette.brightFg;
      };
      "element normal.urgent, element alternate.urgent" = literalAttrs {
        border = "0 0 0 0.2em";
        border-color = palette.red;
        text-color = palette.brightFg;
      };
      "element selected.urgent" = literalAttrs {
        background-color = palette.yellow;
        text-color = palette.black;
      };
      "element-icon" = {
        size = mkLiteral "1.6em";
      };
      "element-text" = literalAttrs {
        text-color = "inherit";
        vertical-align = "0.5";
      };
      scrollbar = literalAttrs {
        width = "0.2em";
        handle-color = palette.border;
        handle-width = "0.2em";
        border-radius = "0.1em";
      };
      "mode-switcher" = literalAttrs {
        margin = "0.4em 0 0";
        spacing = "0.4em";
      };
      button = literalAttrs {
        background-color = palette.surface;
        text-color = palette.fg;
        border-radius = "0.4em";
        padding = "0.45em";
      };
      "button selected" = literalAttrs {
        background-color = palette.selection;
        text-color = palette.brightFg;
        border = "0 0 0.15em";
        border-color = palette.blue;
      };
      message = literalAttrs {
        background-color = palette.surface;
        border-radius = "0.4em";
        padding = "0.5em";
      };
    };
  };

  services.dunst = {
    enable = true;
    package = pkgs.dunst;
    iconTheme = {
      package = pkgs.papirus-icon-theme;
      name = palette.iconTheme;
      size = "32x32";
    };
    settings = {
      global = {
        font = "${palette.fonts.sans} 10";
        # Dunst 1.13 scales logical dimensions by Xft.dpi / 96 on X11.
        scale = 0;
        follow = "keyboard";
        origin = "top-right";
        offset = "(14, 58)";
        width = 380;
        height = "(0, 220)";
        notification_limit = 4;
        transparency = 0;
        padding = 14;
        horizontal_padding = 16;
        text_icon_padding = 12;
        gap_size = 8;
        frame_width = 1;
        frame_color = palette.border;
        corner_radius = 12;
        separator_color = "frame";
        format = "<b>%s</b>\\n%b";
        word_wrap = true;
        ellipsize = "end";
        min_icon_size = 24;
        max_icon_size = 48;
        icon_theme = palette.iconTheme;
        enable_recursive_icon_lookup = true;
        progress_bar = true;
        progress_bar_height = 6;
        progress_bar_frame_width = 0;
        progress_bar_corner_radius = 3;
        progress_bar_min_width = 150;
        progress_bar_max_width = 320;
        highlight = palette.blue;
        show_indicators = true;
        history_length = 50;
        mouse_left_click = "close_current";
        mouse_middle_click = "do_action";
        mouse_right_click = "context";
        dmenu = "${config.programs.rofi.finalPackage}/bin/rofi -dmenu -p 通知";
        browser = "${pkgs.xdg-utils}/bin/xdg-open";
      };
      urgency_low = {
        background = palette.bg;
        foreground = palette.brightFg;
        frame_color = palette.border;
        timeout = 4;
      };
      urgency_normal = {
        background = palette.bg;
        foreground = palette.brightFg;
        frame_color = palette.blue;
        timeout = 7;
      };
      urgency_critical = {
        background = palette.bg;
        foreground = palette.brightFg;
        frame_color = palette.red;
        default_icon = "dialog-error";
        timeout = 0;
      };
    };
  };
}
