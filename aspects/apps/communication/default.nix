_: {
  den.aspects.communication = _: {
    homeManager = { pkgs, ... }: {
      imports = [
        ./im.nix
        ./thunderbird.nix
      ];
      # nixpkgs builds Vesktop with PipeWire support; this enables its system
      # Vencord integration. Its wrapper honors NIXOS_OZONE_WL in Wayland
      # sessions (set by interactive-session) and adds Electron's Wayland IME
      # flags when WAYLAND_DISPLAY is present.
      home.packages = [ (pkgs.vesktop.override { withSystemVencord = true; }) ];
    };
  };
}
