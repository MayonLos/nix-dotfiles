# Noctalia Greeter backend for the login-screen feature.
#
# The greeter is a greetd client with its own wlroots compositor. Sessions are
# discovered from share/wayland-sessions, so the existing Mango/Umbriel
# .desktop entries are reused instead of gtkgreet's environment file.
{ palette }:
{
  hostFacts,
  lib,
  pkgs,
  config,
  ...
}:
let
  greeter = pkgs.local.noctaliaDesktop.greeter;
  wallpaper =
    (import ../../appearance/appearance/resources/wallpaper/package.nix {
      inherit pkgs palette;
    }).default;
  format = pkgs.formats.toml { };
  greeterToml = format.generate "noctalia-greeter.toml" {
    session.default = "Mango";
    user.default = "mayon";

    appearance = {
      scheme = "Synced";
      theme_mode = "dark";
      password_style = "default";
      hide_logo = false;
      power_buttons_position = "bottom-right";
      # The session is fixed to One Dark; a scheme picker on the login screen
      # would advertise a choice that the shell and lock screen do not honor.
      scheme_selector_position = "hidden";
      corner_radius_scale = 0.8;
      font_family = "Inter";
      palette = {
        primary = palette.blue;
        on_primary = palette.black;
        secondary = palette.green;
        on_secondary = palette.black;
        tertiary = palette.cyan;
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
        blur = 0.5;
        tint = 0.35;
      };
    };

    clock = {
      enabled = true;
      position = "above-panel";
      time_format = "{:%H:%M}";
      date_format = "%m-%d";
      time_font_size = 48;
      date_font_size = 14;
    };

    # The greeter compositor runs before any desktop session; pin the panel
    # output so the login screen does not depend on Noctalia Sync state.
    output = {
      use_synced_settings = false;
      name = hostFacts.display.name;
      width = hostFacts.display.width;
      height = hostFacts.display.height;
      refresh_rate = hostFacts.display.refresh;
      scale = 1.5;
    };

    cursor = {
      theme = palette.cursor.name;
      size = palette.cursor.size;
      path = "${pkgs.bibata-cursors}/share/icons";
    };
    keyboard.layout = "us";
    idle.timeout = 0;
    auth.request_timeout = 60;
  };
in
{
  config = lib.mkIf (config.nixDotfiles.greeterBackend == "noctalia") {
    assertions = [
      {
        assertion = config.users.users ? greeter;
        message = "Noctalia Greeter needs the greetd `greeter` user.";
      }
    ];

    services.greetd = {
      enable = true;
      settings.default_session.command = "${greeter}/bin/noctalia-greeter-session";
    };

    # Session entries come from wayland-sessions. Mango's entry uses a bare
    # `Exec=mango` and Steam's uses `Exec=steam`, while greetd's service PATH
    # only contains its own tool packages. Add both binaries so selecting
    # those entries does not fail with "command not found".
    systemd.services.greetd.path = lib.mkAfter [
      config.programs.mango.package
      pkgs.steam
    ];

    environment.systemPackages = [
      greeter
      pkgs.bibata-cursors
    ];
    fonts.packages = [
      pkgs.inter
      pkgs.noto-fonts-cjk-sans
    ];
    environment.pathsToLink = [ "/share/wayland-sessions" ];

    services.accounts-daemon.enable = true;

    systemd.tmpfiles.settings."10-noctalia-greeter" = {
      "/var/lib/noctalia-greeter".d = {
        user = "greeter";
        group = "greeter";
        mode = "0750";
      };
      "/var/lib/noctalia-greeter/greeter.toml"."L+" = {
        argument = "${greeterToml}";
        user = "greeter";
        group = "greeter";
        mode = "0644";
      };
    };
  };
}
