{ config, lib, ... }:

{
  programs.niri.settings = {
    window-rules = [
      {
        geometry-corner-radius = {
          top-left = if config.my.desktop.shell == "noctalia" then 18.0 else 12.0;
          top-right = if config.my.desktop.shell == "noctalia" then 18.0 else 12.0;
          bottom-left = if config.my.desktop.shell == "noctalia" then 18.0 else 12.0;
          bottom-right = if config.my.desktop.shell == "noctalia" then 18.0 else 12.0;
        };
        clip-to-geometry = true;
        draw-border-with-background = false;
      }
      {
        matches = [{ app-id = "foot"; }];
        opacity = 0.8;
      }
    ];

    layer-rules =
      lib.optionals (config.my.desktop.shell == "classic") [
        {
          matches = [
            { namespace = "swww-daemonoverview"; }
          ];
          place-within-backdrop = true;
        }
      ]
      ++ lib.optionals (config.my.desktop.shell == "noctalia") [
        {
          matches = [
            { namespace = "^noctalia-overview*"; }
          ];
          place-within-backdrop = true;
        }
      ];
  };
}
