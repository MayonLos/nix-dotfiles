{
  lib,
  palette,
  reducedMotion,
  distroLogo,
}:
{
  bar.main = {
    position = "top";
    # Sized for the 1.5 output scale (user: UI felt too large, 2026-10-25).
    thickness = 30;
    reserve_space = true;
    auto_hide = false;
    layer = "top";
    panel_overlap = 1;
    background_opacity = 0.98;
    border = "outline";
    border_width = 1;
    show_tooltip = true;
    radius = 10;
    margin_ends = 8;
    margin_edge = 6;
    padding = 6;
    widget_spacing = 5;
    shadow = true;
    contact_shadow = true;
    # The compact bar uses separators and underlines rather than filled group capsules.
    capsule = false;
    capsule_opacity = 1.0;
    capsule_fill = "surface_variant";
    capsule_radius = 8;
    capsule_thickness = 0.78;
    font_family = palette.fonts.sans;
    font_weight = 500;
    font_scale = 1.0;

    # Plugin widgets use manifest-id:entry-id. Everyday tools sit on the
    # left, the date and clock in the center, system status on the right.
    start = [
      "launcher"
      "separator-workspaces"
      "workspaces"
      "separator-layout"
      # Mode feedback must stay visible even when tool drawers collapse.
      "gambled23/mangowm-keymode:mangowm-keymode"
      "ezequiel/mango_layouts:btn"
      "group:tools"
      "separator-media"
      "group:media"
    ];
    center = [ "group:time" ];
    end = [
      "group:monitor"
      "separator-nix"
      "mindnbytes/nix-status:status"
      "separator-privacy"
      "privacy"
      "group:system"
      "separator-control"
      "control-center"
    ];

    capsule_group = map (group: group // { opacity = 0.0; }) [
      {
        id = "media";
        members = [ "media" ] ++ lib.optional (!reducedMotion) "audio_visualizer";
        accordion = false;
        padding = 6.0;
        widget_spacing = 4;
      }
      {
        id = "time";
        members = [
          "clock-date"
          "clock-time"
        ];
        accordion = false;
        padding = 4.0;
        widget_spacing = 4;
      }
      {
        id = "tools";
        members = [
          "fel/quill:status" # Always-visible anchor; only infrequent tools collapse.
          "8bury/mini-docker:mini-docker"
          "rxtsel/portctl:indicator"
          "3ri4ng0ld/ip-monitor:widget"
          "brightness"
          "power_profile"
          "caffeine"
        ];
        # Infrequent tools stay out of the default bar and appear on hover.
        accordion = true;
        accordion_direction = "end";
        padding = 4.0;
        widget_spacing = 4;
      }
      {
        id = "monitor";
        members = [
          "tmelik/system-monitor:summary"
          "monitor-gpu"
          "monitor-vram"
          "monitor-memory"
        ];
        accordion = true;
        accordion_direction = "end";
        padding = 4.0;
        widget_spacing = 4;
      }
      {
        id = "system";
        members = [
          "network"
          "bluetooth"
          "volume"
          "tray"
          "battery"
          "nix-dotfiles/legion-conservation:status"
          "notifications"
        ];
        accordion = false;
        padding = 4.0;
        widget_spacing = 4;
      }
    ];
  };

  widget = {
    launcher = {
      capsule = false;
      color = palette.brightFg;
      icon_color = palette.blue;
    };
    separator-workspaces = {
      type = "text";
      text = "│";
      color = palette.border;
    };
    separator-layout = {
      type = "text";
      text = "│";
      color = palette.border;
    };
    separator-media = {
      type = "text";
      text = "│";
      color = palette.border;
    };
    separator-nix = {
      type = "text";
      text = "│";
      color = palette.border;
    };
    separator-privacy = {
      type = "text";
      text = "│";
      color = palette.border;
    };
    separator-system = {
      type = "text";
      text = "│";
      color = palette.border;
    };
    separator-control = {
      type = "text";
      text = "│";
      color = palette.border;
    };

    # The community summary supplies CPU%; Noctalia's native sysmon widgets
    # are the hover-expanded GPU, VRAM, and RAM members of the same accordion.
    "tmelik/system-monitor:summary" = {
      show_cpu_usage = true;
      show_cpu_temperature = false;
      show_gpu_usage = "off";
      show_gpu_temperature = "off";
      show_gpu_vram = "off";
      show_ram = false;
      show_swap = false;
      show_disk = false;
      show_download = false;
      show_upload = false;
      show_top_processes = false;
      hide_unavailable = true;
      show_separators = false;
    };
    monitor-gpu = {
      type = "sysmon";
      stat = "gpu_usage";
      visualization = "none";
      show_glyph = false;
      custom_label = "GPU";
    };
    monitor-vram = {
      type = "sysmon";
      stat = "gpu_vram";
      visualization = "none";
      show_glyph = false;
      custom_label = "VRAM";
    };
    monitor-memory = {
      type = "sysmon";
      stat = "ram_pct";
      visualization = "none";
      show_glyph = false;
      custom_label = "MEM";
    };
    "nix-dotfiles/legion-conservation:status".active_color = palette.green;

    "control-center" = {
      custom_image = distroLogo;
      custom_image_colorize = false;
    };
    volume.show_label = true;
    # Fcitx's SNI pixmap uses the engine subModeLabel (Rime 中/英).
    # keyboard_layout reads XKB / SNI tooltip names, which cannot convey that.
    tray = {
      drawer = true;
      pinned = [ "fcitx" ];
    };
    privacy = {
      hide_inactive = true;
    };
    "fel/quill:status" = {
      hide_when_empty = false;
      show_label = false;
    };
    "8bury/mini-docker:mini-docker" = {
      # An idle Docker engine is normal; only running containers need space.
      inactive_color = "on_surface_variant";
      status_mode = "running_only";
    };

    # Super+R enters resize mode; hide the badge in default mode.
    "gambled23/mangowm-keymode:mangowm-keymode".hide_on_default = true;
    "ezequiel/mango_layouts:btn".show_text = true;

    battery = {
      # Use Noctalia's native battery drawing instead of the Tabler glyph;
      # this remains unmistakably a battery at the compact 30px bar height.
      display_mode = "graphic";
      warning_color = palette.yellow;
      label_content = "percent";
      show_label = true;
      # Keep the battery indicator itself as the one persistent target; its
      # left click toggles the declared host-side conservation command.
      actions.left = "exec legion-conservation toggle";
    };

    media = {
      hide_when_no_media = true;
      hide_when_idle = true;
      max_length = 160;
      title_scroll = if reducedMotion then "none" else "on_hover";
    };

    # Keep DND visible even without unread items; right-click toggles it.
    notifications.hide_when_no_unread = false;

    # A compact spectrum beside the existing media controls. PipeWire is
    # handled by Noctalia itself; no separate cava process is needed.
    audio_visualizer = {
      width = 26;
      bands = 6;
      mirrored = true;
      centered = true;
      show_when_idle = false;
      color_1 = "primary";
      color_2 = "secondary";
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

    clock-date = {
      type = "clock";
      format = "{:%m月%d日 周%a}";
      font_family = palette.fonts.sans;
    };
    clock-time = {
      type = "clock";
      format = "{:%H:%M}";
      vertical_format = "{:%H\n%M}";
      font_family = palette.fonts.mono;
      font_weight = 600;
    };

    workspaces = {
      # Minimal is the native no-fill workspace style; the local palette patch
      # colors the active label blue while retaining occupancy/urgent semantics.
      style = "minimal";
      label_source = "id";
      show_labels = true;
      hide_when_empty = false;
      show_all_outputs = false;
      focused_output_only = true;
      active_pill_size = 1.0;
      inactive_pill_size = 1.0;
      focused_color = palette.blue;
      occupied_color = palette.fg;
      empty_color = palette.border;
      urgent_color = "error";
      font_scale = 1.0;
    };
  };

}
