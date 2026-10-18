{ palette }:
{ lib, pkgs, ... }:

let
  color =
    name: fallback: lib.removePrefix "#" (if palette == null then fallback else palette.${name});

  anime4k-assets = pkgs.fetchzip {
    url = "https://github.com/bloc97/Anime4K/releases/download/v4.0.1/Anime4K_v4.0.zip";
    hash = "sha256-9B6U+KEVlhUIIOrDauIN3aVUjZ/gQHjFArS4uf/BpaM=";
    stripRoot = false;
  };
  anime4k-shader-chain = "~~/shaders/Anime4K_Clamp_Highlights.glsl:~~/shaders/Anime4K_Restore_CNN_VL.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_VL.glsl:~~/shaders/Anime4K_AutoDownscalePre_x2.glsl:~~/shaders/Anime4K_AutoDownscalePre_x4.glsl:~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl";
in
{
  home.packages = [ pkgs.trash-cli ];

  programs.mpv = {
    enable = true;

    scripts = with pkgs.mpvScripts; [
      uosc
      mpris
      autoload
      thumbfast
      evafast
    ];

    config = {
      # uosc replaces mpv's built-in OSC and uses thumbfast for seek previews.
      osc = "no";
      osd-bar = "no";
      border = "no";

      vo = "gpu-next";
      gpu-api = "vulkan";
      # Hardware-specific decoding belongs to the host binding. Keep a safe,
      # portable default when this media aspect is used elsewhere.
      hwdec = lib.mkDefault "auto-safe";
      video-sync = "display-resample";
      interpolation = "yes";
      tscale = "oversample";

      # A sans, not the monospace this used to name: subtitles are prose, and
      # more to the point they are often Chinese here -- a Latin-only mono
      # family means every CJK glyph is a fontconfig fallback, so the line
      # renders in two typefaces with two different vertical metrics.
      # Noto Sans CJK SC covers both scripts in one family.
      sub-font = if palette == null then "Noto Sans CJK SC" else palette.fonts.sans;
      sub-font-size = 45;
      sub-color = if palette == null then "#d1d5de" else palette.brightFg;
      sub-border-color = if palette == null then "#181b20" else palette.deep;
      sub-border-size = 2;
      sub-auto = "fuzzy";
      slang = "chs,sc,zh,chi,zho";

      # uosc draws the progress/seek UI; use mono for timestamps and sans for
      # subtitle prose, with both surfaces following the fixed OneDark palette.
      osd-font = if palette == null then "JetBrainsMono Nerd Font" else palette.fonts.mono;
      osd-font-size = 26;
      osd-color = if palette == null then "#d1d5de" else palette.brightFg;
      osd-border-color = if palette == null then "#181b20" else palette.deep;
      osd-border-size = 2;
      osd-selected-color = if palette == null then "#4fa6ed" else palette.blue;
      osd-selected-outline-color = if palette == null then "#181b20" else palette.deep;
    };

    scriptOpts.uosc = {
      # Menu deletion must use the recoverable trash operation. uosc does
      # not fall back to rm when the trash command fails.
      use_trash = "yes";
      animation_duration = if palette != null && (palette.reducedMotion or false) then 0 else 100;
      color = "foreground=${color "brightFg" "d1d5de"},foreground_text=${color "deep" "181b20"},background=${color "surface" "282c34"},background_text=${color "brightFg" "d1d5de"},curtain=${color "deep" "181b20"},success=${color "green" "8ebd6b"},error=${color "red" "e55561"},match=${color "blue" "4fa6ed"},heatmap=${color "cyan" "48b0bd"}";
      timeline_style = "line";
      timeline_size = 36;
      timeline_persistency = "paused";
      progress = "windowed";
      top_bar = "no-border";
      top_bar_title = "yes";
      controls = "menu,gap,subtitles,audio,gap,space,prev,playlist,next,gap,fullscreen";
    };

    bindings = {
      "SPACE" = "cycle pause; script-binding uosc/flash-pause-indicator";
      "LEFT" = "no-osd seek -5; script-binding uosc/flash-timeline";
      # evafast owns RIGHT: tap to seek, hold to temporarily accelerate.

      "WHEEL_UP" = "no-osd add volume 2; script-binding uosc/flash-volume";
      "WHEEL_DOWN" = "no-osd add volume -2; script-binding uosc/flash-volume";

      "CTRL+1" =
        ''no-osd change-list glsl-shaders set "${anime4k-shader-chain}"; show-text "Anime4K: Mode A (HQ)"'';
      "CTRL+0" = "no-osd change-list glsl-shaders clr \"\"; show-text \"Anime4K: Disabled\"";
    };

  };

  xdg.configFile."mpv/shaders".source = anime4k-assets;
}
