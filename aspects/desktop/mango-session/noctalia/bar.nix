{
  lib,
  palette,
  reducedMotion,
  distroLogo,
  pkgs,
  hostFacts,
}:
{
  bar.main = {
    position = "top";
    # Sized for the 1.5 output scale (user: UI felt too large, 2026-10-25).
    thickness = 34;
    reserve_space = true;
    auto_hide = false;
    layer = "top";
    panel_overlap = 1;
    background_opacity = 0.98;
    border = "outline";
    border_width = 1;
    show_tooltip = true;
    radius = 10;
    margin_ends = 12;
    margin_edge = 6;
    padding = 6;
    widget_spacing = 6;
    shadow = true;
    contact_shadow = true;
    # Only semantic groups and the launcher get a persistent surface.
    # Group capsules are independent of this per-widget default.
    capsule = false;
    capsule_opacity = 1.0;
    capsule_fill = "surface_variant";
    capsule_radius = 8;
    capsule_thickness = 0.78;
    font_family = palette.fonts.sans;
    font_weight = 500;
    font_scale = 1.0;

    # Plugin widgets use manifest-id:entry-id. Everyday tools sit on the
    # left, the clock and cat in the center, system status on the right.
    start = [
      "launcher"
      "workspaces"
      # Mode feedback must stay visible even when tool drawers collapse.
      "gambled23/mangowm-keymode:mangowm-keymode"
      "group:dev"
      "group:panels"
      "group:media"
    ];
    center = [ "group:time" ];
    end = [
      "group:sys"
      "group:devices"
      "tray"
      "group:power"
      "control-center"
    ];

    capsule_group = [
      {
        id = "media";
        members = [ "media" ] ++ lib.optional (!reducedMotion) "audio_visualizer";
        accordion = false;
        padding = 6.0;
        widget_spacing = 4;
      }
      {
        id = "time";
        members = [ "clock" ] ++ lib.optional (!reducedMotion) "noctalia/bongocat:cat";
        accordion = false;
        fill = palette.deep;
        foreground = "on_surface";
        padding = 8.0;
        widget_spacing = 8;
      }
      {
        id = "panels";
        members = [
          "fel/quill:status" # Markdown notes + todos; replaced noctalia/notes
          "8bury/mini-docker:mini-docker" # Docker management
        ];
        # First member stays visible; hover reveals Docker, not a click toggle.
        accordion = true;
        accordion_direction = "end";
        padding = 6.0;
        widget_spacing = 4;
      }
      {
        id = "sys";
        members = [
          "network"
          "volume"
          "notifications"
        ];
        accordion = false;
        fill = palette.surface;
        padding = 6.0;
        widget_spacing = 4;
      }
      {
        id = "devices";
        members = [
          "bluetooth"
          "brightness"
          "3ri4ng0ld/ip-monitor:widget"
        ];
        # Bluetooth anchors the device drawer; keyboard controls and the
        # control center remain available without hovering the bar.
        accordion = true;
        accordion_direction = "end";
        fill = palette.surface;
        padding = 6.0;
        widget_spacing = 4;
      }
      {
        id = "power";
        members = [
          "power_profile"
          "caffeine"
          "battery"
        ];
        accordion = false;
        fill = palette.surface;
        padding = 6.0;
        widget_spacing = 4;
      }
      {
        id = "dev";
        members = [
          "ezequiel/mango_layouts:btn"
          "rxtsel/portctl:indicator" # inspect and kill port listeners
          "sysmon"
        ];
        # Keep layout as the anchor; /pan also exposes both tool panels.
        accordion = true;
        accordion_direction = "end";
        padding = 6.0;
        widget_spacing = 4;
      }
    ];
  };

  widget = {
    launcher = {
      capsule = true;
      capsule_fill = palette.selection;
      color = palette.brightFg;
      icon_color = palette.blue;
    };

    "control-center" = {
      custom_image = distroLogo;
      custom_image_colorize = false;
    };
    "8bury/mini-docker:mini-docker" = {
      # An idle Docker engine is normal; only running containers need space.
      inactive_color = "on_surface_variant";
      status_mode = "running_only";
    };

    # Super+R enters resize mode; hide the badge in default mode.
    "gambled23/mangowm-keymode:mangowm-keymode".hide_on_default = true;
    "ezequiel/mango_layouts:btn".show_text = false;

    battery.warning_color = palette.yellow;

    media = {
      hide_when_no_media = true;
      max_length = 160;
      title_scroll = if reducedMotion then "none" else "on_hover";
    };

    # Keep DND visible even without unread items; right-click toggles it.
    notifications.hide_when_no_unread = false;

    # A compact spectrum beside the existing media controls. PipeWire is
    # handled by Noctalia itself; no separate cava process is needed.
    audio_visualizer = {
      width = 64;
      bands = 16;
      mirrored = true;
      centered = true;
      show_when_idle = false;
      color_1 = "primary";
      color_2 = "secondary";
    };

    "noctalia/bongocat:cat" = {
      executable_path = "${pkgs.evtest}/bin/evtest";
      input_devices = hostFacts.keyboardDevices;
      audio_spectrum = !reducedMotion;
      tappy_mode = !reducedMotion;
      rave_mode = false;
      use_mpris_filter = true;
    };

    network = {
      # The glyph already says connected / disconnected / which kind. The
      # SSID next to it is ~110 physical pixels of a string that does not
      # change and cannot be acted on; it is still one hover away.
      show_label = false;
    };

    sysmon = {
      # `highlightColor` defaults to ColorRole::Error (sysmon_widget.h:58),
      # so the CPU gauge is drawn in the palette's *error* colour at every
      # load -- a permanent red tick next to "1%". Red should mean
      # something is wrong. Primary is the accent the rest of the bar uses.
      highlight_color = "primary";
      # The label is as wide as the number in it, so the widget grew and
      # shrank between "1%" and "100%" and shoved its neighbours sideways
      # several times a second. Pin it to the width of the widest value.
      label_min_width = 34;
    };

    clock = {
      # %a follows the active LC_TIME locale; prefix it explicitly so Chinese
      # locales render e.g. 周日 instead of the ambiguous bare 日.
      format = "{:%m月%d日 周%a  %H:%M}";
      vertical_format = "{:%H\n%M}";
      font_family = palette.fonts.sans;
    };

    workspaces = {
      # Noctalia 5.3 draws app icons only in focus_hint (the active pill only).
      # Keep regular numbered capsules so all nine workspace identities stay visible.
      style = "regular";
      label_source = "id";
      show_labels = true;
      hide_when_empty = false;
      show_all_outputs = false;
      focused_output_only = true;
      active_pill_size = 1.5;
      inactive_pill_size = 1.0;
      focused_color = "hover";
      occupied_color = "surface_variant";
      empty_color = palette.deep;
      urgent_color = "error";
      font_scale = 1.0;
    };
  };

}
