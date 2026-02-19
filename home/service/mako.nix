{
  ...
}:
{
  services.mako = {
    enable = true;
    settings = {
      # Default notification settings
      font = "Noto Sans CJK SC 10";
      width = 300;
      height = 100;
      margin = "10";
      padding = "10";
      border-radius = 8;
      border-size = 2;

      # Colors
      background-color = "#1e1e2e";
      text-color = "#cdd6f4";
      border-color = "#89b4fa";
      progress-color = "over #313244";

      # Behavior
      default-timeout = 5000;
      ignore-timeout = false;
      layer = "overlay";
      anchor = "top-right";

      # Features
      icons = true;
      max-icon-size = 48;
      markup = true;
      actions = true;

      # Urgency-based styling
      "urgency=low" = {
        border-color = "#94e2d5";
        default-timeout = 3000;
      };

      "urgency=normal" = {
        border-color = "#89b4fa";
        default-timeout = 5000;
      };

      "urgency=critical" = {
        border-color = "#f38ba8";
        background-color = "#302d41";
        default-timeout = 0;
      };

      "app-name=spotify" = {
        border-color = "#a6e3a1";
        default-timeout = 3000;
      };
    };
  };
}
