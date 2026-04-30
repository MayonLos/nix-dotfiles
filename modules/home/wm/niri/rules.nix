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
      }
      {
        matches = [ { app-id = "foot"; } ];
        opacity = 0.8;
      }
      {
        matches = [ { app-id = "swayimg"; } ];
        open-floating = true;
        default-column-width = { proportion = 0.5; };
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
