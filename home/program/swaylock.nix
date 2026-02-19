{
    pkgs,
    ...
}:

{
      programs.swaylock = {
    enable = true;
    package = pkgs.swaylock-effects;
    settings = {
      clock = true;
      screenshots = true;
      indicator = true;
      indicator-radius = 100;
      indicator-thickness = 7;
      effect-blur = "7x5";
      effect-vignette = "0.5:0.2";
      ring-color = "ff0000";
      key-hl-color = "880033";
    };
  };
}