_: {
  den.aspects.media = { user, ... }: {
    homeManager = { pkgs, ... }: {
      imports = [
        (import ./mpv.nix { palette = user.appearance; })
        ./musicfox.nix
        ./obs-studio.nix
        ./blender.nix
        (import ./images.nix { palette = user.appearance; })
      ];
      xdg.mimeApps.enable = true;
      xdg.mimeApps.defaultApplications = {
        "video/mp4" = [ "mpv.desktop" ];
        "video/x-matroska" = [ "mpv.desktop" ];
        "video/webm" = [ "mpv.desktop" ];
        "video/quicktime" = [ "mpv.desktop" ];
      };
      home.packages = with pkgs; [
        ffmpeg
        gimp
        kdePackages.kdenlive
        imagemagick
      ];
    };
  };
}
