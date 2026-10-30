_: {
  den.schema.host.imports = [ ./contract.nix ];
  den.aspects = {
    legion-laptop = { host, ... }: {
      nixos.imports = [
        ./boot.nix
        ./firmware.nix
        ./intel-video.nix
        ./nvidia.nix
        (import ./bluetooth.nix host.facts.bluetooth)
        ./power.nix
        ./memory.nix
        {
          programs.gamemode.settings.gpu = {
            apply_gpu_optimisations = "accept-responsibility";
            gpu_device = host.facts.gpu.gameModeDevice;
            nv_powermizer_mode = 1;
          };
        }
      ];
    };
    legion-laptop-user = { host, ... }: {
      user.extraGroups = [ "legion-conservation" ];
      homeManager = { pkgs, ... }: {
        programs.mpv.config.hwdec = host.facts.gpu.mpvHwdec;
        home.packages = [
          pkgs.lenovo-legion
          (import ./conservation.nix { inherit pkgs; })
        ];
      };
    };
  };
}
