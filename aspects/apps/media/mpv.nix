{ palette }:
{ lib, pkgs, ... }:

let
  color = name: lib.removePrefix "#" palette.${name};

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
      (uosc.overrideAttrs (old: {
        postPatch =
          (old.postPatch or "")
          + ''
            cp ${./resources/uosc-subtitle-margin.lua} src/uosc/lib/compact-subtitles.lua
            ${pkgs.python3}/bin/python3 ${./resources/compact-uosc.py} src/uosc
          ''
          + lib.optionalString (palette != null) ''
            ${pkgs.python3}/bin/python3 ${./resources/refine-uosc.py} src/uosc
          '';
      }))
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
      # The selected CJK family covers both scripts in one family.
      sub-font = if palette == null then "sans-serif" else palette.fonts.cjk;
      sub-font-size = 45;
      sub-border-size = 2;
      sub-auto = "fuzzy";
      slang = "chs,sc,zh,chi,zho";

      # uosc draws the progress/seek UI; use mono for timestamps and sans for
      # subtitle prose, with both surfaces following the fixed OneDark palette.
      osd-font = if palette == null then "monospace" else palette.fonts.mono;
      osd-font-size = 26;
      osd-border-size = 2;
    }
    // lib.optionalAttrs (palette != null) {
      sub-color = palette.brightFg;
      sub-border-color = palette.deep;
      osd-color = palette.brightFg;
      osd-border-color = palette.deep;
      osd-selected-color = palette.blue;
      osd-selected-outline-color = palette.deep;
    };

    scriptOpts.uosc = {
      # Menu deletion must use the recoverable trash operation. uosc does
      # not fall back to rm when the trash command fails.
      use_trash = "yes";
      animation_duration = if palette != null && (palette.reducedMotion or false) then 0 else 100;
      border_radius = 8;
      timeline_style = "line";
      timeline_line_width = 2;
      timeline_size = 28;
      compact_rail = "yes";
      controls_size = 28;
      controls_margin = 24;
      controls_spacing = 4;
      controls_persistency = "";
      volume = "none";
      proximity_in = 12;
      proximity_out = 32;
      timeline_persistency = "";
      progress = "never";
      top_bar = "never";
      top_bar_title = "no";
      top_bar_flash_on = "";
      # Track/chapters/playlist remain reachable from the menu and keys.
      controls = "play-pause,space,menu,fullscreen";
    }
    // lib.optionalAttrs (palette != null) {
      # The bounded uosc theme adaptation separates selection from the
      # foreground used by icons/progress, keeping both readable.
      color = "selection=${color "selection"},foreground=${color "brightFg"},foreground_text=${color "deep"},background=${color "bg"},background_text=${color "brightFg"},curtain=${color "black"},success=${color "green"},error=${color "red"},match=${color "blue"},heatmap=${color "cyan"}";
      opacity = "menu=1,submenu=1,title=1,tooltip=1,curtain=0.32";
    };

    bindings = {
      "s" = "script-binding uosc/subtitles";
      "a" = "script-binding uosc/audio";
      "c" = "script-binding uosc/chapters";
      "p" = "script-binding uosc/playlist";
      "TAB" = "script-binding uosc/menu";
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
