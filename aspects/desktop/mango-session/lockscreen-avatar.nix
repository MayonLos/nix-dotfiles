{ avatar }:
{
  config,
  hostFacts,
  lib,
  ...
}:
{
  # The locked login box has no profile image. Its native sticker
  # widget can display the user-owned .face without an upstream patch.
  programs.noctalia.settings.lockscreen_widgets = lib.mkIf (avatar != null) {
    widget_order = lib.mkAfter [ "lockscreen-widget-avatar" ];
    widget.lockscreen-widget-avatar = {
      type = "sticker";
      output = hostFacts.display.name;
      cx = hostFacts.display.width / hostFacts.display.scale / 2;
      # Above the clock, leaving the login panel's auth card clear.
      cy = hostFacts.display.height / hostFacts.display.scale * 0.13;
      box_width = 80.0;
      box_height = 80.0;
      settings = {
        image_path = "${config.home.homeDirectory}/.face";
        opacity = 1.0;
      };
    };
  };

}
