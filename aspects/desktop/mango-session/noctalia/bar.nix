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
    icon_color = palette.brightFg;

    start = [
      "launcher"
      "active_window"
      "workspaces"
    ];
    center = [ ];
    end = [
      "tray"
      # Mihomo (Clash Verge core) status and node switching; hover for
      # traffic and selections, click for the control panel.
      "mdj2812/mihomo-control:widget"
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
    "mdj2812/mihomo-control:widget" = {
      # Icon only keeps the bar quiet; status colour still shows connectivity.
      label_content = "none";
      icon_color_mode = "status";
    };
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
      # R44: two native tray items belong inline; no attached drawer capsule.
      drawer = false;
      scale = 1.125;
      match_adjacent_spacing = true;
      pinned = [ "fcitx" ];
    };
    # A common 18 logical px Tabler box (native base 16) improves legibility
    # at 1.5 output scale. Only unavailable/disconnected devices use grey.
    network = {
      show_label = false;
      scale = 1.125;
    };
    bluetooth.scale = 1.125;
    volume = {
      show_label = false;
      scale = 1.125;
      mute_color = palette.muted;
    };
    battery = {
      # R44 keeps native Tabler battery outline + bolt even at AC charge limit.
      scale = 1.125;
      display_mode = "glyph";
      label_content = "percent";
      show_label = true;
      warning_color = palette.yellow;
      actions.left = "exec legion-conservation toggle";
    };
    notifications = {
      hide_when_no_unread = true;
      scale = 1.125;
    };
    "control-center" = {
      glyph = "adjustments-horizontal";
      scale = 1.125;
    };
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
