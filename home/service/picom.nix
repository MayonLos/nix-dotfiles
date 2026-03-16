{
  lib,
  ...
}:

{
  services.picom = {
    enable = true;
    backend = "glx";
    vSync = true;

    fade = true;
    fadeDelta = 15;
    fadeSteps = [
      0.03
      0.03
    ];

    shadow = true;
    shadowOpacity = 0.6;
    shadowOffsets = [
      0
      0
    ];

    settings = {
      frame-opacity = 0.7;

      shadow-radius = 1;
      shadow-color = "#393943";

      dithered-present = false;
      detect-rounded-corners = false;
      detect-client-opacity = true;
      use-ewmh-active-win = true;
      detect-transient = true;
      use-damage = true;
      log-level = "warn";

      blur = {
        method = "dual_kawase";
        size = 10;
        strength = 3;
      };
      blur-background-fixed = true;
    };

    extraConfig = ''
      rules = (
        { corner-radius = 12; },

        {
          match = "class_g = 'dwm' || name = 'dwm' || class_g = 'systray' || name = 'systray'";
          corner-radius = 0;
          shadow = false;
          full-shadow = false;
          dim = 0.0;
          opacity = 0.6;
          blur-background = true;
        },

        { match = "(focused || group_focused) && ! (class_g = 'dwm' || class_g = 'systray' || window_type = 'notification' || window_type = 'desktop')";
          opacity = 1.0; dim = 0.0; },

        { match = "! (focused || group_focused) && ! (class_g = 'dwm' || class_g = 'systray' || window_type = 'notification' || window_type = 'desktop')";
          opacity = 0.85; dim = 0.05; },

        { match = "fullscreen"; corner-radius = 0; },

        { match = "window_type = 'tooltip'",       opacity = 0.50; corner-radius = 10; fade = true; shadow = true;  full-shadow = false; },
        { match = "window_type = 'popup_menu'",    opacity = 0.70; corner-radius = 10; },
        { match = "window_type = 'dropdown_menu'", opacity = 0.70; corner-radius = 10; },

        { match = "class_g = 'kitty' || class_g = 'foot' || class_g = 'St' || class_g = 'st' || class_g = 'st-256color'",
          opacity = 0.90; blur-background = true; dim = 0.0; },
        { match = "! (focused || group_focused) && (class_g = 'kitty' || class_g = 'foot' || class_g = 'St' || class_g = 'st' || class_g = 'st-256color')",
          opacity = 0.82; },

        { match = "class_g *?= 'firefox'", opacity = 0.88; blur-background = true; shadow = true; full-shadow = true; },
        { match = "class_g *?= 'firefox' && ! (focused || group_focused)", opacity = 0.80; },

        { match = "(class_g *?= 'qq') || (class_g *?= 'linuxqq') || (name *?= 'qq')",
          opacity = 0.90; blur-background = true; shadow = true; full-shadow = true; dim = 0.0; },
        { match = "(! (focused || group_focused)) && ((class_g *?= 'qq') || (class_g *?= 'linuxqq') || (name *?= 'qq'))",
          opacity = 0.82; },

        { match = "window_type = 'notification'", opacity = 0.90; corner-radius = 10; blur-background = true; dim = 0.0; shadow = true; full-shadow = true; },
        { match = "window_type = 'notification' && ! (focused || group_focused)", opacity = 0.86; },

        { match = "(class_g *?= 'slop') || (name *?= 'slop') || (class_g *?= 'maim') || (name *?= 'maim')",
          blur-background = false; opacity = 1.0; dim = 0.0; shadow = false; full-shadow = false; }
      );

      animations = (
        { triggers = [ "open", "show" ];  preset = "appear";       scale = 0.90; duration = 0.30; },
        { triggers = [ "close", "hide" ]; preset = "disappear";    scale = 0.90; duration = 0.20; },
        { triggers = [ "increase-opacity" ]; preset = "appear";    scale = 0.98; duration = 0.12; },
        { triggers = [ "decrease-opacity" ]; preset = "disappear"; scale = 1.0;  duration = 0.10; },
        { triggers = [ "geometry" ]; preset = "geometry-change";   duration = 0.15; }
      );
    '';
  };

  # We launch picom manually from DWM; hide the XDG autostart entry so Wayland
  # sessions do not try to start it.
  xdg.configFile."autostart/picom.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=picom
    Hidden=true
  '';

  systemd.user.services.picom.Install.WantedBy = lib.mkForce [ ];
}
