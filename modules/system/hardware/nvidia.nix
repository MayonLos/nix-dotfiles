{ config, ... }:
{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  services.xserver.videoDrivers = [
    "modesetting"
    "nvidia"
  ];

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    # finegrained (RTD3) fully powers down the dGPU when idle. On this Optimus
    # laptop that triggers an nvidia_modeset oops (nvKmsIoctl) while tearing the
    # GPU down at shutdown. Disabled to get clean shutdowns; costs a little idle
    # battery. (RANDSTRUCT — the other common cause — is off on this kernel.)
    powerManagement.finegrained = false;
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

