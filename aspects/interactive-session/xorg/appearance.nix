{ palette }:
{
  config,
  lib,
  pkgs,
  hostFacts,
  ...
}:
let
  # Picom uses physical pixels; Dunst derives its logical scale from Xft.
  px = n: builtins.floor (n * hostFacts.display.x11Dpi / 96.0 + 0.5);
in
{
  # Lifecycle and D-Bus activation are owned by this feature's session target.
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
      shadow-radius = px 14;
      shadow-opacity = 0.18;
      shadow-offset-x = -(px 10);
      shadow-offset-y = -(px 6);
      shadow-color = palette.black;
      crop-shadow-to-monitor = true;
      # Solid reading surfaces do not need continuous background blur.
      blur-method = "none";
      # Keep composition stable when notifications appear over fullscreen apps.
      unredir-if-possible = false;
    };
    # libconfig group lists require parentheses, not HM's scalar-array writer.
    # Our configured dwm owns _MAYON_DWM_FLOATING on each managed client.
    # The @ condition reads the property on the client window. Later rules win.
    extraConfig = ''
      rules = (
        { corner-radius = 0; shadow = false; dim = 0.0; },
        {
          match = "_MAYON_DWM_FLOATING@ = 1";
          corner-radius = ${toString (px 6)};
          shadow = true;
        },
        # dmenu is an override-redirect window, not a dwm floating client.
        # Give this centered menu depth without changing other popup windows.
        { match = "class_g = 'dmenu'"; corner-radius = 0; shadow = true; },
        # Dunst draws its own rounded, opaque surface.
        { match = "class_g = 'Dunst'"; corner-radius = 0; shadow = false; },
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
        font = "${palette.fonts.sans} 10.5";
        # Dunst 1.13 scales logical dimensions by Xft.dpi / 96 on X11.
        scale = 0;
        follow = "keyboard";
        origin = "top-right";
        offset = "(14, 52)";
        width = 320;
        height = "(0, 220)";
        notification_limit = 3;
        transparency = 0;
        padding = 14;
        horizontal_padding = 16;
        text_icon_padding = 12;
        gap_size = 8;
        frame_width = 1;
        # Ordinary notifications share the menu's quiet outline. Only critical
        # notifications need an accent frame; focus blue belongs to navigation.
        frame_color = palette.selection;
        corner_radius = 6;
        separator_color = "frame";
        format = "<b>%s</b>\\n%b";
        word_wrap = true;
        ellipsize = "end";
        min_icon_size = 24;
        max_icon_size = 32;
        icon_theme = palette.iconTheme;
        enable_recursive_icon_lookup = true;
        progress_bar = true;
        progress_bar_height = 4;
        progress_bar_frame_width = 0;
        progress_bar_corner_radius = 2;
        progress_bar_min_width = 150;
        progress_bar_max_width = 280;
        highlight = palette.blue;
        show_indicators = true;
        history_length = 50;
        mouse_left_click = "close_current";
        mouse_middle_click = "do_action";
        mouse_right_click = "context";
        dmenu = "${config.home.profileDirectory}/bin/xorg-dmenu -p 通知";
        browser = "${pkgs.xdg-utils}/bin/xdg-open";
      };
      urgency_low = {
        background = palette.bg;
        foreground = palette.brightFg;
        frame_color = palette.selection;
        timeout = 4;
      };
      urgency_normal = {
        background = palette.bg;
        foreground = palette.brightFg;
        frame_color = palette.selection;
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
