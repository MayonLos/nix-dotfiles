_:

{
  programs.niri.settings = {
    window-rules = [
      {
        geometry-corner-radius = {
          top-left = 18.0;
          top-right = 18.0;
          bottom-left = 18.0;
          bottom-right = 18.0;
        };
        clip-to-geometry = true;
        draw-border-with-background = false;
        shadow = {
          enable = true;
          softness = 30.0;
          spread = 5.0;
          offset = {
            x = 0.0;
            y = 5.0;
          };
          color = "#00000088";
          inactive-color = "#00000055";
        };
      }
      {
        matches = [ { app-id = "foot"; } ];
        opacity = 0.8;
      }
      {
        matches = [ { app-id = "swayimg"; } ];
        open-floating = true;
        default-column-width = { proportion = 0.5; };
        border = { width = 0; };
      }
      {
        matches = [ { app-id = "^steam_app_"; } ];
        variable-refresh-rate = true;
        geometry-corner-radius = {
          top-left = 0.0;
          top-right = 0.0;
          bottom-left = 0.0;
          bottom-right = 0.0;
        };
      }
    ];

    layer-rules = [
      {
        matches = [
          { namespace = "^noctalia-overview*"; }
        ];
        place-within-backdrop = true;
      }
    ];
  };
}
