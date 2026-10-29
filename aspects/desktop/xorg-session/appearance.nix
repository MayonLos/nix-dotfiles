{ palette }:
{
  config,
  lib,
  pkgs,
  hostFacts,
  ...
}:
let
  # Picom rules take physical pixels. Scale the shared 10 logical px radius at
  # the same X11 DPI used by the host; the 2 px focus border is set by dwm.
  px = n: builtins.floor (n * hostFacts.display.x11Dpi / 96.0 + 0.5);
  dunst = pkgs.dunst.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./resources/dunst-left-accent.patch ];
    postInstall = (old.postInstall or "") + ''
      service_dir="$out/share/dbus-1/services"
      rm "$service_dir/org.knopwob.dunst.service"
      cat > "$service_dir/org.freedesktop.Notifications.service" <<EOF
      [D-BUS Service]
      Name=org.freedesktop.Notifications
      Exec=${pkgs.coreutils}/bin/false
      SystemdService=dunst.service
      EOF
      grep -Fx 'SystemdService=dunst.service' "$service_dir/org.freedesktop.Notifications.service"
    '';
  });
in
{
  # Lifecycle and D-Bus activation are owned by this feature's session target.
  services.picom = {
    enable = true;
    package = pkgs.picom;
    # The HM defaults emit legacy opacity/wintypes options. Picom 13's ordered
    # rules below are the sole source of per-window effects.
    # force: Replace legacy HM Picom settings with the complete Picom 13 rule set.
    settings = lib.mkForce {
      backend = "glx";
      vsync = true;
      use-damage = true;
      fading = !palette.reducedMotion;
      # 0.10 per 10 ms is at most 100 ms for either transition.
      fade-in-step = 0.10;
      fade-out-step = 0.10;
      fade-delta = 8;
      shadow = false;
      shadow-radius = px 18;
      shadow-opacity = 0.24;
      shadow-offset-x = 0;
      shadow-offset-y = px 8;
      shadow-color = palette.black;
      crop-shadow-to-monitor = true;
      blur-method = "none";
      # Do not unredirect fullscreen windows; composition stays deterministic.
      unredir-if-possible = false;
    };
    extraConfig = ''
      rules = (
        # Normal clients keep the shared 10 logical px corners, soft shadow,
        # and full brightness while focused.
        {
          corner-radius = ${toString (px 10)};
          shadow = true;
          dim = 0.0;
        },
        { match = "!focused"; dim = 0.06; },
        { match = "focused"; dim = 0.0; },

        # dwm exports this WM-owned class for its 30 px floating status bar.
        { match = "class_g = 'dwm-bar'"; corner-radius = ${toString (px 10)}; shadow = true; dim = 0.0; },

        # Dunst paints its own rounded surface and urgency accent in Cairo.
        { match = "class_g = 'Dunst'"; corner-radius = 0; shadow = true; dim = 0.0; },

        # Games and fullscreen video/capture surfaces receive no compositor
        # decorations or dimming. The game marker is set by dwm rules.
        { match = "_MAYON_DWM_GAME@ = 1"; corner-radius = 0; shadow = false; dim = 0.0; fade = false; },
        { match = "fullscreen"; corner-radius = 0; shadow = false; dim = 0.0; fade = false; blur-background = false; },

        # i3lock-color owns a full-screen opaque surface; keep it unmodified.
        { match = "class_g = 'i3lock' || class_g = 'i3lock-color' || name = 'i3lock' || name = 'i3lock-color'"; corner-radius = 0; shadow = false; dim = 0.0; fade = false; blur-background = false; },

        # Desktop, dock and override-redirect utility surfaces should not inherit
        # client shadows or rounding.
        { match = "window_type = 'dock' || window_type = 'desktop'"; corner-radius = 0; shadow = false; dim = 0.0; }
      );
    '';
  };

  services.dunst = {
    enable = true;
    package = dunst;
    iconTheme = {
      package = config.gtk.iconTheme.package;
      name = config.gtk.iconTheme.name;
      size = "32x32";
    };
    settings = {
      global = {
        font = "${palette.fonts.sans} 10.5";
        # Dunst 1.13 auto-scales logical geometry from X11 output DPI.
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
        frame_color = palette.selection;
        corner_radius = 9;
        separator_color = "frame";
        format = "<b>%s</b>\\n%b";
        word_wrap = true;
        ellipsize = "end";
        min_icon_size = 24;
        max_icon_size = 32;
        icon_theme = config.gtk.iconTheme.name;
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
        dmenu = "${config.home.profileDirectory}/bin/xorg-rofi-dmenu -p 通知";
        browser = "${pkgs.xdg-utils}/bin/xdg-open";
      };
      # Dunst 1.13 has no left-only urgency-frame setting. The pinned Cairo
      # patch paints a narrow urgency-colored strip inside this neutral frame.
      urgency_low = {
        background = palette.deep;
        foreground = palette.brightFg;
        frame_color = palette.muted;
        timeout = 4;
      };
      urgency_normal = {
        background = palette.deep;
        foreground = palette.brightFg;
        frame_color = palette.blue;
        timeout = 7;
      };
      urgency_critical = {
        background = palette.deep;
        foreground = palette.brightFg;
        frame_color = palette.red;
        default_icon = "dialog-error";
        timeout = 0;
      };
    };
  };
}
