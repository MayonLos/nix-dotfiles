{
  config,
  hostFacts,
  ...
}:
{
  # Stated here rather than left to Steam: nixpkgs' programs/steam.nix assigns
  # both of these plainly (not mkDefault) whenever Steam is enabled, so the
  # values have to agree with this file or evaluation fails outright.
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  services.xserver.videoDrivers = [
    "nvidia"
  ];
  # PRIME offload already contributes the Intel modesetting device with its
  # BusID. Listing modesetting again creates duplicate Device/Screen IDs when
  # real Xorg is enabled; keep a single primary iGPU screen from that module.

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    powerManagement.finegrained = false;
    open = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    # nvidia-persistenced makes shutdown take the proper driver teardown path,
    # avoiding the nv_drm_master_drop -> ReleaseOwnership NULL deref.
    nvidiaPersistenced = true;

    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
      intelBusId = hostFacts.gpu.intelBusId;
      nvidiaBusId = hostFacts.gpu.nvidiaBusId;
    };
  };

  environment.etc."nvidia/nvidia-application-profiles-rc.d/50-mango-vram-fix.json".text = ''
    {
      "rules": [
        { "pattern": { "feature": "procname", "matches": "mango" },
          "profile": "Limit Free Buffer Pool" }
      ],
      "profiles": [
        { "name": "Limit Free Buffer Pool",
          "settings": [ { "key": "GLVidHeapReuseRatio", "value": 0 } ] }
      ]
    }
  '';
}
