{ palette }:
{ pkgs, lib, ... }:
let
  toml = pkgs.formats.toml { };
  json = pkgs.formats.json { };
  noctalia = pkgs.local.noctaliaDesktop.noctalia;
  wallpaper =
    (import ../../appearance/appearance/resources/wallpaper/package.nix {
      inherit pkgs palette;
    }).default;

  # One Dark -> Noctalia palette format 2 (16 direct roles plus terminal ANSI).
  oneDark = {
    version = 2;
    base = "One Dark";
    dark = {
      primary = palette.blue;
      on_primary = palette.black;
      secondary = palette.purple;
      on_secondary = palette.black;
      tertiary = palette.cyan;
      on_tertiary = palette.black;
      error = palette.red;
      on_error = palette.black;
      surface = palette.bg;
      on_surface = palette.fg;
      surface_container = palette.surface;
      on_surface_variant = palette.muted;
      outline_variant = palette.border;
      shadow = palette.black;
      hover = palette.selection;
      on_hover = palette.brightFg;
      terminal = {
        background = palette.bg;
        foreground = palette.fg;
        cursor = palette.blue;
        cursor_text = palette.black;
        selection_bg = palette.selection;
        selection_fg = palette.brightFg;
        normal = {
          black = palette.black;
          red = palette.red;
          green = palette.green;
          yellow = palette.yellow;
          blue = palette.blue;
          magenta = palette.purple;
          cyan = palette.cyan;
          white = palette.fg;
        };
        bright = {
          black = palette.muted;
          red = palette.red;
          green = palette.green;
          yellow = palette.orange;
          blue = palette.blue;
          magenta = palette.purple;
          cyan = palette.cyan;
          white = palette.brightFg;
        };
      };
    };
  };
in
{
  home.packages = [ noctalia ];

  # Palettes live next to the config and are selected by name, matching the
  # upstream Home Manager module's layout.
  xdg.configFile."noctalia/palettes/one-dark.json".source = json.generate "one-dark.json" oneDark;

  xdg.configFile."noctalia/config.toml".source = toml.generate "noctalia-config.toml" {
    shell = {
      # Empty means "whatever GTK/fontconfig resolves", which keeps the
      # repository's Inter/Noto configuration authoritative.
      font_family = "";
      corner_radius_scale = 1.0;
      telemetry_enabled = false;
      settings_show_advanced = true;
      clipboard_enabled = true;
      # The repository's polkit-gnome agent is bound to mango-session.target,
      # so the Umbriel session uses Noctalia's built-in agent instead.
      polkit_agent = true;
      time_format = "{:%H:%M}";
      date_format = "%m-%d";
    };

    theme = {
      mode = "dark";
      source = "custom";
      custom_palette = "one-dark";
      pure_black_dark = false;
    };

    wallpaper = {
      enabled = true;
      fill_mode = "crop";
      transition = [ "fade" ];
      transition_duration = 600;
      directory = "";
    };
    wallpaper.default.path = "${wallpaper}";

    backdrop.enabled = false;

    notification = {
      enable_daemon = true;
      colorize_icons = false;
      group_by_app = true;
      scale = 1.0;
    };

    osd = {
      position = "top_right";
      hide_delay_ms = 1400;
      scale = 1.0;
      background_opacity = 0.97;
      border = false;
      offset_x = 16;
      offset_y = 8;
    };

    lockscreen = {
      enabled = true;
      lock_before_suspend = true;
      grace_period_seconds = 0;
      blurred_desktop = false;
      transition = [
        "fade"
        "wipe"
      ];
      transition_duration = 900;
      tint_color = "surface";
      blur_intensity = 0.5;
      tint_intensity = 0.3;
    };

    idle.behavior = {
      lock = {
        enabled = true;
        timeout = 600;
        action = "lock";
      };
      screen-off = {
        enabled = true;
        timeout = 660;
        action = "screen_off";
      };
    };

    system.monitor = {
      enabled = true;
      cpu_poll_seconds = 2.0;
      memory_poll_seconds = 2.0;
      network_poll_seconds = 3.0;
    };

    dock.enabled = false;

    bar = {
      order = [ "main" ];
      main = {
        position = "top";
        layer = "top";
        thickness = 30;
        # Fully transparent like the Mango mangobar; the bar itself publishes a
        # wallpaper-blur region only where its layer rule applies.
        background_opacity = 0.0;
        compositor_blur = false;
        border_width = 0.0;
        shadow = false;
        radius = 0;
        margin_ends = 0;
        margin_edge = 0;
        padding = 16;
        widget_spacing = 10;
        font_scale = 0.93;
        font_weight = 500;
        reserve_space = true;
        capsule = false;
        show_tooltip = true;
        start = [ "workspaces" ];
        center = [ "active_window" ];
        end = [
          "tray"
          "network"
          "battery"
          "cpu"
          "ram"
          "clock"
        ];
      };
    };

    widget = {
      workspaces = {
        style = "minimal";
        show_labels = true;
        label_source = "id";
        max_label_chars = 1;
        focused_color = "primary";
        occupied_color = "on_surface_variant";
        empty_color = "surface_container";
        urgent_color = "error";
        change_color_on_hover = true;
        hide_when_empty = false;
      };
      active_window = {
        display = "text_only";
        title_scroll = "none";
        min_length = 0;
        max_length = 160;
        show_empty_label = false;
      };
      clock = {
        format = "{:%H:%M}";
        tooltip_format = "{:%Y-%m-%d %A}";
      };
      cpu = {
        type = "sysmon";
        stat = "cpu_usage";
        visualization = "none";
        show_value = true;
        label_show_units = false;
      };
      ram = {
        type = "sysmon";
        stat = "ram_used";
        visualization = "none";
        show_value = true;
        label_show_units = false;
      };
    };
  };
}
