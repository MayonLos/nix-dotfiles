{
  pkgs,
  ...
}:

{
  services.dunst = {
    enable = true;
    iconTheme = {
      package = pkgs.papirus-icon-theme;
      name = "Papirus-Dark";
      size = "32x32";
    };
    settings = {
      global = {
        monitor = 0;
        follow = "mouse";
        origin = "top-right";
        offset = "(20,40)";
        gap_size = 8;
        notification_limit = 5;

        width = "(300,420)";
        height = "(0,300)";
        padding = 14;
        horizontal_padding = 14;
        line_height = 0;
        corner_radius = 10;
        separator_height = 2;
        separator_color = "frame";

        transparency = 0;
        frame_width = 2;
        frame_color = "#313244";

        font = "JetBrainsMono Nerd Font 10";
        markup = "full";
        format = "<b>%s</b>\\n%b%p";
        alignment = "left";
        ellipsize = "middle";
        word_wrap = true;
        ignore_newline = false;

        show_age_threshold = 60;
        stack_duplicates = true;
        hide_duplicate_count = true;
        history_length = 50;
        indicate_hidden = true;

        icon_position = "left";
        max_icon_size = 48;

        mouse_left_click = "close_current";
        mouse_middle_click = "do_action, close_current";
        mouse_right_click = "close_all";

        browser = "xdg-open";
        dmenu = "dmenu -p dunst";

        progress_bar = true;
        progress_bar_height = 6;
        progress_bar_min_width = 120;
        progress_bar_max_width = 280;
        progress_bar_corner_radius = 3;
        progress_bar_frame_width = 0;

        show_indicators = true;
      };

      urgency_low = {
        background = "#1e1e2e";
        foreground = "#cdd6f4";
        frame_color = "#313244";
        timeout = 4;
      };

      urgency_normal = {
        background = "#1e1e2e";
        foreground = "#cdd6f4";
        frame_color = "#313244";
        timeout = 8;
      };

      urgency_critical = {
        background = "#1e1e2e";
        foreground = "#f38ba8";
        frame_color = "#f38ba8";
        timeout = 0;
      };
    };
  };

  xdg.configFile."dunst/sound.conf".text = ''
    sound_low=/usr/share/sounds/freedesktop/stereo/message.oga
    sound_normal=/usr/share/sounds/freedesktop/stereo/message.oga
    sound_critical=/usr/share/sounds/freedesktop/stereo/dialog-error.oga

    volume_low=32768
    volume_normal=49152
    volume_critical=65536

    quiet_start=23
    quiet_end=7
  '';
}
