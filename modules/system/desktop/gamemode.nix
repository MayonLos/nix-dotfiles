{ pkgs, ... }:

{
  programs.gamemode = {
    enable = true;
    settings = {
      custom = {
        start = "${pkgs.libnotify}/bin/notify-send 'GameMode Started'";
        end = "${pkgs.libnotify}/bin/notify-send 'GameMode Ended'";
      };
      gpu = {
        apply_gpu_optimisations = "accept-responsibility";
        gpu_vendor = "nvidia";
        nv_powermizer_mode = 1;
      };
    };
  };
}
