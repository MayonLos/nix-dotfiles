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
        # NVIDIA dGPU is /dev/dri/card0 on this host (Intel i915 is card1).
        gpu_device = 0;
        nv_powermizer_mode = 1;
      };
    };
  };
}
