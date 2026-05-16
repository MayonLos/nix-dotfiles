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
      datestr = "%Y-%m-%d";
      effect-blur = "8x5";
      effect-vignette = "0.3:0.7";
      fade-in = 0;
      grace = 0;

      # Ring indicator — One Dark
      indicator = true;
      indicator-radius = 80;
      indicator-thickness = 7;
      ring-color = "3b4252";
      ring-ver-color = "98c379";
      ring-wrong-color = "e06c75";
      ring-clear-color = "61afef";
      key-hl-color = "61afef";
      bs-hl-color = "e06c75";

      # Text
      text-color = "abb2bf";
      text-ver-color = "abb2bf";
      text-wrong-color = "e06c75";
      text-clear-color = "61afef";

      # Fill inside indicator
      inside-color = "1f232966";
      inside-ver-color = "1f232966";
      inside-wrong-color = "1f232966";
      inside-clear-color = "1f232966";

      separator-color = "00000000";
      line-uses-ring = true;
      font = "JetBrainsMono Nerd Font";
      show-failed-attempts = true;
    };
  };
}
