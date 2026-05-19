{ pkgs, ... }:
{
  home.packages = with pkgs; [ swayidle ];

  programs.swaylock = {
    enable = true;
    package = pkgs.swaylock-effects;
    settings = {
      # Screenshot + blur as background
      screenshots = true;
      clock = true;
      timestr = "%H:%M";
      datestr = "%a, %B %d";
      effect-blur = "14x8";
      effect-vignette = "0.4:0.8";
      effect-scale = "0.5";
      fade-in = 0;
      grace = 0;

      # Ring indicator — One Dark
      indicator = true;
      indicator-radius = 90;
      indicator-thickness = 8;
      ring-color = "2c313a";
      ring-ver-color = "98c379";
      ring-wrong-color = "e06c75";
      ring-clear-color = "61afef";
      key-hl-color = "61afef";
      bs-hl-color = "e06c75";

      # Text
      text-color = "abb2bf";
      text-ver-color = "98c379";
      text-wrong-color = "e06c75";
      text-clear-color = "61afef";

      # Fill inside indicator
      inside-color = "1e222a99";
      inside-ver-color = "1e222a99";
      inside-wrong-color = "1e222a99";
      inside-clear-color = "1e222a99";

      separator-color = "00000000";
      line-uses-ring = true;
      font = "JetBrainsMono Nerd Font";
      font-size = 28;
      show-failed-attempts = true;
    };
  };
}
