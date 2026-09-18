{ pkgs, ... }:

let
  anime4k-assets = pkgs.fetchzip {
    url = "https://github.com/bloc97/Anime4K/releases/download/v4.0.1/Anime4K_v4.0.zip";
    hash = "sha256-9B6U+KEVlhUIIOrDauIN3aVUjZ/gQHjFArS4uf/BpaM=";
    stripRoot = false;
  };
in
{
  programs.mpv = {
    enable = true;

    scripts = with pkgs.mpvScripts; [
      mpris
      autoload
      thumbfast
      evafast
    ];

    config = {
      osc = "yes";
      osd-bar = "yes";
      border = "no";

      vo = "gpu-next";
      gpu-api = "vulkan";
      hwdec = "nvdec-copy";
      video-sync = "display-resample";
      interpolation = "yes";
      tscale = "oversample";

      # A sans, not the monospace this used to name: subtitles are prose, and
      # more to the point they are often Chinese here -- a Latin-only mono
      # family means every CJK glyph is a fontconfig fallback, so the line
      # renders in two typefaces with two different vertical metrics.
      # Noto Sans CJK SC covers both scripts in one family.
      sub-font = "Noto Sans CJK SC";
      sub-font-size = 45;
      sub-auto = "fuzzy";
      slang = "chs,sc,zh,chi,zho";

      glsl-shaders = "~~/shaders/Anime4K_Clamp_Highlights.glsl:~~/shaders/Anime4K_Restore_CNN_VL.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_VL.glsl:~~/shaders/Anime4K_AutoDownscalePre_x2.glsl:~~/shaders/Anime4K_AutoDownscalePre_x4.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl";
    };

    bindings = {
      "SPACE" = "cycle pause";
      "LEFT" = "seek -5";

      "WHEEL_UP" = "add volume 2";
      "WHEEL_DOWN" = "add volume -2";

      "CTRL+1" =
        "no-osd change-list glsl-shaders set \"~~/shaders/Anime4K_Clamp_Highlights.glsl:~~/shaders/Anime4K_Restore_CNN_VL.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_VL.glsl:~~/shaders/Anime4K_AutoDownscalePre_x2.glsl:~~/shaders/Anime4K_AutoDownscalePre_x4.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl\"; show-text \"Anime4K: Mode A (HQ)\"";
      "CTRL+0" = "no-osd change-list glsl-shaders clr \"\"; show-text \"Anime4K: Disabled\"";
    };

  };

  xdg.configFile."mpv/shaders".source = anime4k-assets;
}
