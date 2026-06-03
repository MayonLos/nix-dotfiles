{ config, ... }:

{
  programs.mangohud = {
    enable = true;
    enableSessionWide = false; # 不推荐全局开启，容易导致非游戏软件出现 OSD
    settings = {
      full = true;
      no_display = true; # 默认隐藏，按 Shift_L+F12 显示
      cpu_temp = true;
      gpu_temp = true;
      vram = true;
      ram = true;
      fps = true;
      frame_timing = 1;
      toggle_hud = "Shift_L+F12";
      toggle_logging = "Shift_L+F11";
      background_alpha = 0.4;
      font_size = 20;
      position = "top-left";
      round_corners = 10;
    };
  };
}