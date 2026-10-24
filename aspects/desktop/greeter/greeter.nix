{ palette }:
{
  hostFacts,
  inputs,
  lib,
  pkgs,
  config,
  ...
}:
let
  wallpaper =
    (import ../../appearance/appearance/resources/wallpaper/package.nix {
      inherit pkgs palette;
    }).default;
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
        corner_radius_scale = 4.0 / 3.0;
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
        date_format = "%Y年%m月%d日 %A";
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

  # The pinned greeter calls setlocale(LC_ALL, "") and formats weekday names
  # from LC_TIME. greetd starts its session with a deliberately empty
  # environment, so pass the Chinese locale on the existing greeter command.
  # force: add LC_TIME to the pinned command while preserving XDG_DATA_DIRS and argument forwarding.
  services.greetd.settings.default_session.command = lib.mkForce (
    "${lib.getExe' pkgs.coreutils "env"} "
    + "LC_TIME=zh_CN.UTF-8 "
    + "XDG_DATA_DIRS=${config.services.displayManager.sessionData.desktops}/share "
    + "${config.services.displayManager.noctalia-greeter.package}/bin/noctalia-greeter-session -- "
    + config.services.displayManager.noctalia-greeter.greeter-args
  );

  # Greeter runs before the user session, so these assets must be in the
  # system closure and discoverable without relying on a user's Home Manager.
  environment.systemPackages = [
    pkgs.bibata-cursors
    pkgs.inter
    pkgs.noto-fonts-cjk-sans
  ];
}
