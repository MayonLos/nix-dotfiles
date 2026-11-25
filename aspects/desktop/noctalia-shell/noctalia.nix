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
      secondary = palette.green;
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
          inherit (palette)
            black
            red
            green
            yellow
            blue
            cyan
            ;
          magenta = palette.purple;
          white = palette.fg;
        };
        bright = {
          black = palette.muted;
          inherit (palette)
            red
            green
            blue
            cyan
            ;
          yellow = palette.orange;
          magenta = palette.purple;
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
      corner_radius_scale = 0.8;
      telemetry_enabled = false;
      screen_time_enabled = false;
      # Offline: all palette/weather/geolocation fetches are unnecessary here
      # and this removes the only recurring outbound HTTP from the shell.
      offline_mode = true;
      settings_show_advanced = true;
      clipboard_enabled = true;
      clipboard_history_max_entries = 50;
      animation = {
        enabled = !palette.reducedMotion;
        speed = 1.0;
      };
      # Floating panels get the repository's soft, bordered look; the control
      # center stays attached to the bar so it opens under the clicked icon.
      panel = {
        transparency_mode = "solid";
        borders = true;
        border_color = "outline_variant";
        border_width = 1.0;
        shadow = true;
        launcher_placement = "floating";
        clipboard_placement = "floating";
        control_center_placement = "floating";
        wallpaper_placement = "attached";
        session_placement = "attached";
        open_near_click_control_center = true;
      };
      shadow = {
        direction = "down";
        alpha = 0.5;
      };
      # Minimal launcher: search + results, no chrome the shell does not use.
      launcher = {
        layout = "simple";
        compact = true;
        show_icons = false;
        categories = false;
        show_navigation_labels = false;
        show_settings_button = false;
        show_session_button = false;
        show_app_origin_indicator = false;
        track_usage = true;
        sort_by_usage = true;
      };
      # The Umbriel session autostarts the repository's polkit-gnome agent;
      # Noctalia's own agent cannot register from this session cgroup.
      polkit_agent = false;
      time_format = "{:%H:%M}";
      date_format = "%m-%d";
    };

    theme = {
      mode = "dark";
      source = "custom";
      custom_palette = "one-dark";
      pure_black_dark = false;
      templates.enable_community_templates = false;
    };

    # Optional shell services that this desktop does not use. Disabling them
    # removes their background samplers and DBus agents.
    calendar.enabled = false;
    weather.enabled = false;
    location.auto_locate = false;

    control_center = {
      show_avatar_border = false;
      media.show_visualizer = false;
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
      scale = 0.95;
      background_opacity = 0.97;
      border = true;
      border_color = "outline_variant";
      border_width = 1;
      offset_x = 16;
      offset_y = 8;
    };

    osd = {
      position = "top_right";
      kinds.keyboard_layout = false;
      hide_delay_ms = 1400;
      scale = 0.95;
      background_opacity = 0.95;
      border = true;
      border_color = "outline_variant";
      border_width = 1;
      offset_x = 16;
      offset_y = 8;
    };

    lockscreen = {
      enabled = true;
      lock_before_suspend = true;
      grace_period_seconds = 0;
      blurred_desktop = true;
      transition = [ "fade" ];
      transition_duration = 450;
      tint_color = "surface";
      blur_intensity = 0.6;
      tint_intensity = 0.35;
    };

    # No timed idle lock or screen-off, matching the previous Mango policy:
    # lock only on Super+Alt+L and before suspend.
    idle.behavior = {
      lock = {
        enabled = false;
        timeout = 600;
        action = "lock";
      };
      screen-off = {
        enabled = false;
        timeout = 660;
        action = "screen_off";
      };
    };

    # Only CPU and memory are shown in the bar; the GPU/network/disk samplers
    # are disabled with 0 seconds instead of paying for their polling.
    system.monitor = {
      enabled = true;
      cpu_poll_seconds = 2.0;
      memory_poll_seconds = 2.0;
      gpu_poll_seconds = 0;
      network_poll_seconds = 3.0;
      disk_poll_seconds = 10.0;
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
        padding = 14;
        widget_spacing = 8;
        font_scale = 0.94;
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
          "notifications"
          "control-center"
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
        custom_label = "CPU";
        visualization = "none";
        show_value = true;
        show_glyph = false;
        label_show_units = true;
      };
      ram = {
        type = "sysmon";
        stat = "ram_used";
        custom_label = "MEM";
        visualization = "none";
        show_value = true;
        show_glyph = false;
        label_show_units = true;
      };
    };
  };
}
