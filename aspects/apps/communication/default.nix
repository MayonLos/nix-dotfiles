_: {
  imports = [ ../../appearance/appearance ];
  den.aspects.communication = { user, ... }: {
    homeManager = { pkgs, ... }: {
      imports = [
        ./im.nix
        (import ./thunderbird.nix { palette = user.appearance; })
      ];
      # nixpkgs builds Vesktop with PipeWire support; this enables its system
      # Vencord integration. Its wrapper honors NIXOS_OZONE_WL in Wayland
      # sessions (set by interactive-session) and adds Electron's Wayland IME
      # flags when WAYLAND_DISPLAY is present.
      home.packages = [ (pkgs.vesktop.override { withSystemVencord = true; }) ];
    };
  };
}
