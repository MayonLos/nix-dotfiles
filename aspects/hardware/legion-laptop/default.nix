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
