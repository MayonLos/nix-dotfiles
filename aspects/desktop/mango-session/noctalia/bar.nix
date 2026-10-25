{
  palette,
  distroLogo,
}:
let
  separator = {
    type = "spacer";
    length = 15;
    decoration = "separator";
  };
  monitor = stat: label: {
    type = "sysmon";
    inherit stat;
    custom_label = label;
    show_glyph = false;
    visualization = "none";
    font_family = palette.fonts.mono;
    font_scale = 0.86;
    color = palette.brightFg;
    label_min_width = 28;
    highlight_color = palette.blue;
  };
in
{
  bar.main = {
    position = "top";
    thickness = 35;
    reserve_space = true;
    auto_hide = false;
    layer = "top";
    panel_overlap = 1;
    background_opacity = 0.98;
    border = "${palette.muted}55";
    border_width = 1;
    show_tooltip = true;
    radius = 9;
    margin_ends = 8;
    margin_edge = 6;
    padding = 7;
    widget_spacing = 6;
    shadow = true;
    contact_shadow = true;
    capsule = false;
    capsule_opacity = 1.0;
    capsule_fill = "surface_variant";
    capsule_radius = 6;
    capsule_thickness = 0.67;
    font_family = palette.fonts.sans;
    font_weight = 500;
    font_scale = 0.93;

    start = [
      "launcher"
      "separator-workspaces"
      "workspaces"
      "separator-layout"
      "gambled23/mangowm-keymode:mangowm-keymode"
      "ezequiel/mango_layouts:btn"
      "group:tools"
    ];
    center = [ "group:time" ];
    end = [
      "group:monitor"
      "separator-monitor"
      "mindnbytes/nix-status:status"
      "separator-system"
      "group:system"
      "separator-control"
      "control-center"
    ];
    capsule_group = [
      {
        id = "time";
        members = [
          "clock-date"
          "clock-dot"
          "clock-time"
        ];
        opacity = 0.0;
        accordion = false;
        padding = 4.0;
        widget_spacing = 7;
      }
      {
        id = "tools";
        members = [
          "fel/quill:status"
          "8bury/mini-docker:mini-docker"
          "rxtsel/portctl:indicator"
          "brightness"
          "power_profile"
          "caffeine"
        ];
        accordion = true;
        accordion_direction = "end";
        accordion_delay_ms = 100;
        opacity = 0.0;
        border_width = 0;
        padding = 4.0;
        widget_spacing = 10;
      }
      {
        id = "monitor";
        members = [
          "monitor-cpu"
          "monitor-memory"
          "monitor-gpu"
          "monitor-temp"
        ];
        opacity = 0.0;
        border_width = 0;
        accordion = false;
        padding = 2.0;
        widget_spacing = 6;
      }
      {
        id = "system";
        members = [
          "network"
          "bluetooth"
          "volume"
          "tray"
          "battery"
          "notifications"
        ];
        opacity = 0.0;
        accordion = false;
        padding = 4.0;
        widget_spacing = 8;
      }
    ];
  };

  # Per-widget scale multiplies Noctalia's output content scale for text,
  # glyphs, and internal geometry; spacers are sized explicitly below.
  widget =
    builtins.mapAttrs
      (
        _: settings: if (settings.type or null) == "spacer" then settings else settings // { scale = 1.15; }
      )
      {
        launcher = {
          capsule = false;
          glyph = "snowflake";
          icon_color = palette.blue;
        };
        separator-workspaces = separator;
        separator-layout = separator;
        separator-monitor = separator;
        separator-system = separator;
        separator-control = separator;
        clock-dot = {
          type = "spacer";
          length = 24;
          decoration = "dot";
        };
        monitor-cpu = (monitor "cpu_usage" "CPU") // {
          visualization = "graph";
        };
        monitor-memory = (monitor "ram_pct" "MEM") // {
          visualization = "ring";
          highlight_color = palette.green;
        };
        monitor-temp = (monitor "cpu_temp" "") // {
          temperature_hide_below = 80;
          hide_unavailable = true;
          color = palette.orange;
          highlight_color = palette.orange;
          label_min_width = 26;
        };
        monitor-gpu = (monitor "gpu_usage" "GPU") // {
          hide_unavailable = true;
          show_gpu_temperature = false;
          capsule = false;
          color = palette.orange;
          highlight_color = palette.orange;
          label_min_width = 28;
        };
        bluetooth.scale = 1.15;
        "control-center" = {
          glyph = "settings";
          icon_color = palette.blue;
        };
        volume = {
          show_label = false;
          font_family = palette.fonts.mono;
          color = palette.brightFg;
          icon_color = palette.fg;
        };
        tray = {
          drawer = true;
          pinned = [ "fcitx" ];
        };
        "fel/quill:status" = {
          hide_when_empty = false;
          show_label = false;
          icon_color = palette.blue;
        };
        "rxtsel/portctl:indicator".font_scale = 0.80;
        "8bury/mini-docker:mini-docker" = {
          inactive_color = "on_surface_variant";
          active_color = "secondary";
          status_mode = "running_only";
        };
        "gambled23/mangowm-keymode:mangowm-keymode".hide_on_default = true;
        "ezequiel/mango_layouts:btn" = {
          show_text = true;
          show_glyph = true;
          capsule = false;
          icon_color = palette.cyan;
          font_scale = 0.86;
        };
        "mindnbytes/nix-status:status" = {
          capsule = false;
          font_family = palette.fonts.mono;
          font_scale = 0.86;
        };
        brightness = {
          show_label = true;
          font_scale = 0.80;
          icon_color = palette.yellow;
          font_family = palette.fonts.mono;
          color = palette.brightFg;
        };
        power_profile = {
          icon_color = palette.green;
        };
        caffeine.icon_color = palette.muted;
        battery = {
          display_mode = "graphic";
          label_outside = true;
          warning_color = palette.yellow;
          label_content = "percent";
          show_label = true;
          color = palette.brightFg;
          font_family = palette.fonts.mono;
          actions.left = "exec legion-conservation toggle";
        };
        notifications.hide_when_no_unread = false;
        network.show_label = false;
        clock-date = {
          type = "clock";
          format = "{:%m月%d日 周%a}";
          font_family = palette.fonts.sans;
          color = palette.muted;
          font_scale = 0.89;
        };
        clock-time = {
          type = "clock";
          format = "{:%H:%M}";
          vertical_format = "{:%H\n%M}";
          font_family = palette.fonts.mono;
          font_weight = 600;
          font_scale = 1.03;
          color = palette.brightFg;
        };
        workspaces = {
          style = "minimal";
          label_source = "id";
          show_labels = true;
          hide_when_empty = true;
          minimum_visible = 5;
          show_all_outputs = false;
          focused_output_only = true;
          active_pill_size = 1.0;
          inactive_pill_size = 1.0;
          focused_color = palette.blue;
          occupied_color = palette.fg;
          empty_color = "#454c58";
          urgent_color = "error";
          font_scale = 0.89;
        };
      };
}
