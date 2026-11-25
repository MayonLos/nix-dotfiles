{ palette, display }:
{ pkgs, lib, ... }:
let
  toml = pkgs.formats.toml { };
  noctalia = "${pkgs.local.noctaliaDesktop.noctalia}/bin/noctalia";
  # Keep the familiar Mango keybinds on the same chords. Commands that are
  # repository scripts resolve through the Home Manager profile PATH.
  nc = command: "${noctalia} msg ${command}";

  keybinds = {
    # Applications
    "Mod+Return" = {
      action = "spawn workspace-terminal";
      repeat = false;
    };
    "Mod+E" = {
      action = "spawn workspace-files";
      repeat = false;
    };
    "Mod+B" = {
      action = "spawn workspace-browser";
      repeat = false;
    };
    "Mod+Shift+Return" = {
      action = "spawn-floating kitty --class=mayon-scratch";
      repeat = false;
    };
    "Mod+Shift+E" = {
      action = "spawn-floating kitty --class=mayon-files yazi";
      repeat = false;
    };
    "Mod+Shift+C" = {
      action = "spawn-floating kitty --class=mayon-clash clashtui-mayon";
      repeat = false;
    };
    "Mod+Shift+D" = {
      action = "spawn-floating kitty --class=mayon-tools mayon-tools";
      repeat = false;
    };
    "Mod+Shift+B" = {
      action = "spawn-floating kitty --class=mayon-bili bilitui";
      repeat = false;
    };
    "Control+Shift+Escape" = {
      action = "spawn-floating kitty --class=mayon-monitor btop";
      repeat = false;
    };
    "Alt+Space" = {
      action = "spawn fuzzel --no-icons";
      repeat = false;
    };

    # Shell
    "Mod" = "spawn " + nc "panel-toggle launcher";
    "Mod+V" = "spawn " + nc "panel-toggle clipboard";
    "Mod+Escape" = "spawn " + nc "panel-toggle session";
    "Mod+Shift+Escape" = {
      action = "shortcuts-inhibit-toggle";
      allow_when_inhibited = true;
      repeat = false;
    };
    "Mod+Alt+L" = {
      action = "spawn " + nc "session lock";
      repeat = false;
    };
    "Mod+Shift+N" = {
      action = "spawn headset-mic toggle";
      repeat = false;
    };
    "Mod+Shift+XF86Assistant" = {
      action = "spawn mayon-voice toggle";
      repeat = false;
    };

    # Screenshots: Noctalia owns region/full screen, mark-shot keeps scrolling
    # capture and OCR scripts.
    "Print" = {
      action = "spawn ${pkgs.local.mark-shot}/bin/mark-shot";
      repeat = false;
    };
    "Shift+Print" = {
      action = "spawn ${pkgs.local.mark-shot}/bin/mark-shot --scroll";
      repeat = false;
    };
    "Mod+Print" = {
      action = "spawn " + nc "screenshot-region";
      repeat = false;
    };
    "Control+Print" = {
      action = "spawn " + nc "screenshot-fullscreen";
      repeat = false;
    };
    "Mod+Shift+Print" = {
      action = "spawn ocr-screen";
      repeat = false;
    };
    "Control+Shift+Print" = {
      action = "spawn ocr-region";
      repeat = false;
    };

    # Focus and movement
    "Mod+Left" = "window-focus-left";
    "Mod+Down" = "window-focus-down";
    "Mod+Up" = "window-focus-up";
    "Mod+Right" = "window-focus-right";
    "Mod+H" = "window-focus-left";
    "Mod+J" = "window-focus-down";
    "Mod+K" = "window-focus-up";
    "Mod+L" = "window-focus-right";
    "Mod+Tab" = {
      action = "window-focus-last";
      repeat = false;
    };
    "Mod+Shift+Left" = "column-move-left";
    "Mod+Shift+Right" = "column-move-right";
    "Mod+Shift+Up" = "window-move-up";
    "Mod+Shift+Down" = "window-move-down";

    # Window state and layout
    "Mod+Q" = {
      action = "window-close";
      repeat = false;
    };
    "Mod+Space" = {
      action = "window-toggle-floating";
      repeat = false;
    };
    "Mod+T" = {
      action = "window-toggle-pinned";
      repeat = false;
    };
    "Mod+F" = {
      action = "window-toggle-fullscreen";
      repeat = false;
    };
    "Mod+Shift+F" = {
      action = "window-toggle-maximize-to-edges";
      repeat = false;
    };
    "Mod+M" = {
      action = "window-toggle-maximize";
      repeat = false;
    };
    "Mod+R" = "window-cycle-primary-extent";
    "Mod+Shift+R" = "window-cycle-primary-extent-back";
    "Mod+Minus" = "window-modify-primary-extent -0.02";
    "Mod+Equal" = "window-modify-primary-extent +0.02";
    "Mod+Control+Minus" = "window-modify-secondary-extent -0.02";
    "Mod+Control+Equal" = "window-modify-secondary-extent +0.02";
    "Mod+Comma" = "window-consume-left";
    "Mod+Period" = "window-consume-right";
    "Mod+W" = {
      action = "column-toggle-tabbed";
      repeat = false;
    };
    "Mod+O" = {
      action = "overview-toggle";
      repeat = false;
    };
    "Mod+Shift+Space" = {
      action = "window-move-to-scratchpad";
      repeat = false;
    };
    "Mod+Control+Space" = {
      action = "scratchpad-toggle";
      repeat = false;
    };

    # Workspaces
    "Mod+1" = "workspace-switch 1";
    "Mod+2" = "workspace-switch 2";
    "Mod+3" = "workspace-switch 3";
    "Mod+4" = "workspace-switch 4";
    "Mod+5" = "workspace-switch 5";
    "Mod+6" = "workspace-switch 6";
    "Mod+7" = "workspace-switch 7";
    "Mod+8" = "workspace-switch 8";
    "Mod+9" = "workspace-switch 9";
    "Mod+Shift+1" = "window-move-to-workspace 1";
    "Mod+Shift+2" = "window-move-to-workspace 2";
    "Mod+Shift+3" = "window-move-to-workspace 3";
    "Mod+Shift+4" = "window-move-to-workspace 4";
    "Mod+Shift+5" = "window-move-to-workspace 5";
    "Mod+Shift+6" = "window-move-to-workspace 6";
    "Mod+Shift+7" = "window-move-to-workspace 7";
    "Mod+Shift+8" = "window-move-to-workspace 8";
    "Mod+Shift+9" = "window-move-to-workspace 9";

    # Hardware keys go through Noctalia so its OSDs are shown and the binds
    # stay available while the session is locked.
    "XF86AudioRaiseVolume" = {
      action = "spawn " + nc "volume-up";
      allow_when_locked = true;
    };
    "XF86AudioLowerVolume" = {
      action = "spawn " + nc "volume-down";
      allow_when_locked = true;
    };
    "XF86AudioMute" = {
      action = "spawn " + nc "volume-mute";
      allow_when_locked = true;
      repeat = false;
    };
    "XF86AudioMicMute" = {
      action = "spawn " + nc "mic-mute";
      allow_when_locked = true;
      repeat = false;
    };
    "XF86MonBrightnessUp" = {
      action = "spawn " + nc "brightness-up";
      allow_when_locked = true;
    };
    "XF86MonBrightnessDown" = {
      action = "spawn " + nc "brightness-down";
      allow_when_locked = true;
    };
    "XF86AudioPlay" = {
      action = "spawn " + nc "media toggle";
      allow_when_locked = true;
      repeat = false;
    };
    "XF86AudioNext" = {
      action = "spawn " + nc "media next";
      allow_when_locked = true;
    };
    "XF86AudioPrev" = {
      action = "spawn " + nc "media previous";
      allow_when_locked = true;
    };
  };
in
{
  xdg.configFile."umbriel/config.toml".source = toml.generate "umbriel-config.toml" {
    general = {
      # The shell is a compositor child so it dies with the session.
      autostart = [ noctalia ];
      xwayland = true;
      xwayland_native_resolution = true;
    };

    appearance.blur.radius = 3;

    input.keyboard.numlock_toggle = false;

    # Scrolling layout by default: the closest thing to Mango's tag model that
    # also gives the overview something to arrange. Per-workspace layouts stay
    # configurable at runtime.
    layout = {
      mode = "scrolling";
      extent_presets = [
        0.333
        0.5
        0.667
      ];
    };
    layout.scrolling.default_extent_fraction = 0.5;

    output.${display.name} = {
      scale = display.scale;
      position = [
        0
        0
      ];
    };

    inherit keybinds;

    window_rule = [
      { blur = true; }
      {
        match.app_id = "^dev\\.noctalia\\.Noctalia$";
        default_floating = true;
        default_floating_size_px = {
          width = 1020;
          height = 900;
        };
      }
      {
        match.app_id = "^dev\\.noctalia\\.UmbrielSharePicker$";
        default_floating = true;
        default_floating_size_px = {
          width = 800;
          height = 600;
        };
      }
      {
        match.title = "^(Picture-in-Picture|Picture in picture)$";
        default_floating = true;
        default_maximize = false;
        default_position = {
          x = 20;
          y = 20;
          anchor = "bottom_right";
        };
      }
    ];

    # Noctalia surfaces blur live content; the bar itself keeps the cached
    # wallpaper blur so a transparent bar costs no full-screen blur pass.
    layer_rule = [
      {
        match.namespace = "^noctalia-(bar-[^\"]+|notification|dock|panel|attached-panel|osd|desktop-widget-[^\"]*)$";
        blur = true;
        blur_ignore_alpha = 0.5;
        blur_popups = true;
      }
      {
        match.namespace = "^noctalia-(notification|dock|panel|attached-panel|osd)$";
        blur_optimized = false;
      }
    ];

    hot_corners.top_left = {
      enabled = true;
      delay_ms = 500;
      action = "overview-open";
    };
  };
}
