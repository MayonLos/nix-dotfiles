{
    ...
}:

{
  programs.niri.settings = {
  window-rules = [
    {
      geometry-corner-radius = {
        top-left = 12.0;
        top-right = 12.0;
        bottom-left = 12.0;
        bottom-right = 12.0;
      };
      clip-to-geometry = true;
      draw-border-with-background = false;
    }

      {
    matches = [{ app-id = "foot"; }];
    opacity = 0.8;
  }
  ];
layer-rules = [
    {
      matches = [
        { namespace = "swww-daemonoverview"; }
      ];
      
      place-within-backdrop = true;
    }
  ];
};
}