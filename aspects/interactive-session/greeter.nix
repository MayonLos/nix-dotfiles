{ palette }:
{
  hostFacts,
  inputs,
  pkgs,
  ...
}:
let
  wallpaper = ./resources/wallpaper/wallpaper-009.png;
in
{
  imports = [ inputs.noctalia-greeter.nixosModules.default ];

  services.displayManager.noctalia-greeter = {
    enable = true;
    settings = {
      session.default = "Mango";

      appearance = {
        scheme = "Synced";
        password_style = "random";
        theme_mode = "dark";
        # Match the shell's central authentication scene and rounded surfaces.
        corner_radius_scale = 1.2;
        hide_logo = true;
        font_family = palette.fonts.sans;
        scheme_selector_position = "hidden";
        power_buttons_position = "bottom-right";
        palette = {
          primary = palette.blue;
          on_primary = palette.black;
          secondary = palette.cyan;
          on_secondary = palette.black;
          tertiary = palette.purple;
          on_tertiary = palette.black;
          error = palette.red;
          on_error = palette.black;
          surface = palette.bg;
          on_surface = palette.brightFg;
          surface_variant = palette.surface;
          on_surface_variant = palette.fg;
          outline = palette.border;
          shadow = palette.black;
          hover = palette.selection;
          on_hover = palette.brightFg;
        };
        wallpaper = {
          path = wallpaper;
          fill_mode = "crop";
          fill_color = palette.surface;
        };
      };

      clock = {
        enabled = true;
        position = "above-panel";
        time_format = "{:%H:%M}";
        date_format = "%m-%d %A";
      };

      # Pin the known internal panel scale while allowing unknown external
      # outputs to use the greeter's per-output automatic scale.
      output.scales = "${hostFacts.display.name}:${builtins.toJSON hostFacts.display.scale}";

      keyboard.layout = "us";
      cursor = {
        theme = palette.cursor.name;
        size = palette.cursor.size;
        path = pkgs.bibata-cursors;
      };
    };
  };

  environment.pathsToLink = [ "/share/wayland-sessions" ];

  # Greeter runs before the user session, so these assets must be in the
  # system closure and discoverable without relying on a user's Home Manager.
  environment.systemPackages = [
    pkgs.bibata-cursors
    pkgs.noto-fonts-cjk-sans
  ];
}
