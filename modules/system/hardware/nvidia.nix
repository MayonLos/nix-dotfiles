{ config, ... }:
{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  services.xserver.videoDrivers = [ "modesetting" "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    powerManagement.finegrained = true;
    open = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;

    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  # 修复 NVIDIA 在 Niri/Wayland 上的 VRAM 显存泄露问题
  environment.etc."nvidia/nvidia-application-profiles-rc.d/50-niri-vram-fix.json".text = ''
    {
      "rules": [
        { "pattern": { "feature": "procname", "matches": "niri" },
          "profile": "Limit Free Buffer Pool" }
      ],
      "profiles": [
        { "name": "Limit Free Buffer Pool",
          "settings": [ { "key": "GLVidHeapReuseRatio", "value": 0 } ] }
      ]
    }
  '';
}