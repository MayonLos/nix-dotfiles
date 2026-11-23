{
  config,
  hostFacts,
  ...
}:
{
  hardware = {
    # Stated here rather than left to Steam: nixpkgs' programs/steam.nix assigns
    # both of these plainly (not mkDefault) whenever Steam is enabled, so the
    # values have to agree with this file or evaluation fails outright.
    graphics = {
      enable = true;
      enable32Bit = true;
    };

    nvidia = {
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

    # Generates a CDI specification for the NVIDIA devices at boot. The locked
    # module also wires it into the rootless Docker daemon (CDI feature flag and
    # spec directories), so containers reach the GPU without the legacy runtime.
    nvidia-container-toolkit.enable = true;
  };

  services.xserver.videoDrivers = [
    "nvidia"
  ];
  # PRIME offload already contributes the Intel modesetting device with its
  # BusID; listing modesetting again would duplicate Device/Screen IDs if a
  # real Xorg server were ever enabled.

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
