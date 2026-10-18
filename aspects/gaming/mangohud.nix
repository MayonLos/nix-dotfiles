_:

{
  programs.mangohud = {
    enable = true;
    settings = {
      gpu_stats = true;
      gpu_temp = true;
      gpu_power = true;
      gpu_core_clock = true;
      cpu_stats = true;
      cpu_temp = true;
      cpu_power = true;
      cpu_mhz = true;
      vram = true;
      ram = true;

      fps = true;
      frametime = true;
      frame_timing = true;
      present_mode = true;

      gamemode = true;
      vulkan_driver = true;
      engine_version = true;
      wine = true;

      position = "top-left";
      font_size = 22;
      round_corners = 8;
      background_alpha = 0.4;

      toggle_hud = "Shift_R+F12";
      no_display = false;
    };
  };
}
