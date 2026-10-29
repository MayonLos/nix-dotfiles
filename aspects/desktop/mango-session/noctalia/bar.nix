{ palette }:
{
  bar.main = {
    position = "top";
    thickness = 30;
    reserve_space = true;
    auto_hide = false;
    layer = "top";
    panel_overlap = 1;
    background_opacity = 0.62;
    compositor_blur = true;
    border_width = 0;
    show_tooltip = true;
    radius = 0;
    margin_ends = 0;
    margin_edge = 0;
    padding = 16;
    widget_spacing = 10;
    shadow = false;
    contact_shadow = false;
    capsule = false;
    font_family = palette.fonts.sans;
    font_weight = 500;
    font_scale = 0.93;
    color = palette.brightFg;

    start = [
      "launcher"
      "active_window"
      "workspaces"
    ];
    center = [ ];
    end = [
      "tray"
      "network"
      "bluetooth"
      "volume"
      "battery"
      # Native control-center has no unread badge; this fallback disappears
      # completely once history is read, and opens the notifications tab.
      "notifications"
      "control-center"
      "clock"
    ];
  };

  widget = {
    launcher = {
      custom_image = "${../resources/nix-snowflake.svg}";
      custom_image_colorize = true;
      scale = 0.94;
      show_tooltip = false;
      color = palette.brightFg;
      actions.left = "panel-toggle nix-dotfiles/desktop-menus:system";
    };
    active_window = {
      display = "text_only";
      show_app_name = true; # small local extension using native app identity
      show_empty_label = false;
      min_length = 0;
      max_length = 160;
      font_weight = 650;
      title_scroll = "none";
    };
    workspaces = {
      style = "minimal";
      show_icons = false;
      show_labels = true;
      hide_when_empty = true;
      show_all_outputs = false;
      focused_output_only = false;
      active_dot = true;
      hover_preview = true;
      font_scale = 0.857;
      font_weight = 600;
      change_color_on_hover = true;
      capsule = false;
      focused_color = palette.brightFg;
      occupied_color = palette.muted;
      empty_color = palette.muted;
      urgent_color = "error";
    };
    tray = {
      drawer = true;
      pinned = [ "fcitx" ];
    };
    network.show_label = false;
    volume.show_label = false;
    battery = {
      # Native Tabler glyph + external percentage; no custom battery renderer.
      display_mode = "glyph";
      label_content = "percent";
      show_label = true;
      warning_color = palette.yellow;
      actions.left = "exec legion-conservation toggle";
    };
    notifications = {
      hide_when_no_unread = true;
      scale = 0.85;
    };
    "control-center".glyph = "adjustments-horizontal";
    clock.format = "{:%m月%d日 周%a %H:%M}";
  };

  dock = {
    enabled = true;
    position = "bottom";
    icon_size = 44;
    main_axis_padding = 10;
    cross_axis_padding = 8;
    item_spacing = 8;
    margin_edge = 8;
    margin_ends = 0;
    radius = 16;
    background_opacity = 0.80;
    compositor_blur = true;
    border_width = 1;
    border = "${palette.fg}22";
    # Mango layer blur turns the client shadow fringe opaque; keep the native
    # translucent capsule and fine outline without a second shadow surface.
    shadow = false;
    reserve_space = false;
    auto_hide = false;
    smart_auto_hide = true;
    # The edge trigger remains reachable over fullscreen windows.
    layer = "overlay";
    show_running = true;
    show_dots = true;
    show_instance_count = false;
    launcher_position = "start";
    launcher_icon = "layout-grid";
    magnification = true;
    magnification_scale = 1.2;
    active_scale = 1.0;
    inactive_scale = 0.92;
    active_opacity = 1.0;
    inactive_opacity = 0.9;
    pinned = [
      "kitty"
      "firefox"
      "obsidian"
      "thunar"
      "code"
      "qq"
      "musicfox"
    ];
  };
}
