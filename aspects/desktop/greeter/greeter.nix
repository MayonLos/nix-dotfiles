{ palette }:
{
  hostFacts,
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
  # gtkgreet 0.8 has no blur option. Preprocess only the public default
  # wallpaper; this derivation never reads a user's mutable wallpaper.
  authWallpaper =
    pkgs.runCommand "greeter-auth-wallpaper.png"
      {
        nativeBuildInputs = [ pkgs.imagemagick ];
      }
      ''
        magick ${wallpaper} -blur 0x24 -fill '${palette.black}' -colorize 48 "$out"
      '';
  # gtkgreet strncpy's the selected command into a 128-byte buffer and sends
  # that string as the sole greetd argv element. A command line with arguments
  # would be executed as one path and would be truncated.
  mangoLogin = pkgs.writeShellScript "mango-login" ''
    export XDG_SESSION_TYPE=wayland
    export XDG_CURRENT_DESKTOP=mango:wlroots
    export XDG_SESSION_DESKTOP=mango
    exec ${lib.getExe config.programs.mango.package}
  '';
  # The experiment branch may append more sessions. The first entry stays the
  # default selection, so a plain Enter keeps logging into Mango.
  loginCommands = [
    {
      name = "Mango";
      command = mangoLogin;
    }
  ]
  ++ config.nixDotfiles.extraLoginCommands;
  # gtkgreet always draws its "Command to run on login" chooser, and for the
  # single-session case it shows the whole /nix/store path of the login
  # command. The patch hides the chooser when only one command is available;
  # actions.c still reads the hidden widget's active text, so the login keeps
  # using the same store path and needs no PATH lookup in greetd.
  gtkgreet = pkgs.gtkgreet.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./gtkgreet-single-command.patch ];
    postPatch = (old.postPatch or "") + ''
      grep -Fq 'A single session needs no command chooser' gtkgreet/window.c
    '';
  });
  css = ''
    window {
      background-color: ${palette.black};
      background-image: url("file://${authWallpaper}");
      background-size: cover;
      background-position: center;
      background-repeat: no-repeat;
    }

    #clock {
      color: ${palette.brightFg};
      font-family: ${palette.fonts.sans}, "${palette.fonts.cjk}";
    }

    box#body {
      background-color: alpha(${palette.bg}, 0.92);
      color: ${palette.brightFg};
      border: 1px solid alpha(${palette.border}, 0.75);
      border-radius: 18px;
      padding: 30px 34px;
      min-width: 430px;
      box-shadow: 0 26px 70px alpha(${palette.black}, 0.55);
    }

    label {
      color: ${palette.brightFg};
      font-family: ${palette.fonts.sans}, "${palette.fonts.cjk}";
    }

    #input-field,
    #command-selector,
    entry {
      background-color: ${palette.surface};
      color: ${palette.brightFg};
      caret-color: ${palette.blue};
      border: 1px solid alpha(${palette.border}, 0.45);
      border-radius: 10px;
      min-height: 38px;
      padding: 0 12px;
    }

    #input-field:focus,
    #command-selector:focus,
    entry:focus {
      border-color: ${palette.blue};
    }

    button {
      border-radius: 10px;
      min-height: 36px;
      padding: 0 16px;
      font-family: ${palette.fonts.sans}, "${palette.fonts.cjk}";
    }

    button.suggested-action {
      background-color: ${palette.blue};
      color: ${palette.black};
      border: none;
    }
  '';
  swayConfig = ''
    output * background ${palette.black} solid_color
    output ${hostFacts.display.name} scale ${builtins.toJSON hostFacts.display.scale}
    seat seat0 xcursor_theme ${palette.cursor.name} ${toString palette.cursor.size}
    input type:keyboard xkb_layout us
    xwayland disable
    exec '${lib.getExe gtkgreet} -l -s /etc/greetd/gtkgreet.css -c ${(builtins.head loginCommands).command}; ${lib.getExe' pkgs.sway "swaymsg"} exit'
  '';
in
{
  imports = [ (import ./noctalia.nix { inherit palette; }) ];

  options.nixDotfiles.greeterBackend = lib.mkOption {
    type = lib.types.enum [
      "gtkgreet"
      "noctalia"
    ];
    default = "noctalia";
    description = ''
      Login greeter backend. `gtkgreet` keeps the previous sway+gtkgreet
      wrapper; `noctalia` runs Noctalia Greeter's own wlroots compositor and
      lists the installed wayland-sessions.
    '';
  };

  options.nixDotfiles.extraLoginCommands = lib.mkOption {
    type = lib.types.listOf (
      lib.types.submodule {
        options = {
          name = lib.mkOption { type = lib.types.str; };
          command = lib.mkOption { type = lib.types.str; };
        };
      }
    );
    default = [ ];
    description = "Extra login commands offered by gtkgreet, after the Mango session (gtkgreet backend only).";
  };

  config = lib.mkIf (config.nixDotfiles.greeterBackend == "gtkgreet") {
    assertions = [
      {
        assertion = config.programs.mango.enable or false;
        message = "login-screen starts the host Mango package.";
      }
    ]
    ++ map (entry: {
      assertion = builtins.stringLength entry.command < 128 && !lib.hasInfix " " entry.command;
      message = "gtkgreet 0.8 sends each login command as one argv element of at most 127 bytes (${entry.name}).";
    }) loginCommands
    ++ [
      {
        assertion =
          let
            execLine = lib.findFirst (line: lib.hasInfix "gtkgreet" line) "" (lib.splitString "
" swayConfig);
          in
          lib.hasInfix "; " execLine;
        message = "greeter exec must pass -c and separate the gtkgreet command from swaymsg with ';'.";
      }
    ];

    # cage 0.3.0 cannot set a per-output scale, so the greeter compositor is
    # sway and the internal output scale comes from host facts.
    services.greetd = {
      enable = true;
      settings.default_session.command = lib.concatStringsSep " " [
        (lib.getExe' pkgs.coreutils "env")
        "XCURSOR_THEME=${palette.cursor.name}"
        "XCURSOR_SIZE=${toString palette.cursor.size}"
        "XCURSOR_PATH=${pkgs.bibata-cursors}/share/icons"
        "XKB_DEFAULT_LAYOUT=us"
        "GTK_THEME=Adwaita:dark"
        (lib.getExe' pkgs.dbus "dbus-run-session")
        (lib.getExe pkgs.sway)
        "--config"
        "/etc/greetd/sway.conf"
      ];
    };

    fonts.packages = [
      pkgs.inter
      pkgs.noto-fonts-cjk-sans
    ];

    # The greeter session starts with an empty environment, before the user's
    # Home Manager profile exists. Cursor lookup uses XCURSOR_PATH above.
    environment = {
      etc = {
        "greetd/environments".text = lib.concatMapStrings (entry: "${entry.command}\n") loginCommands;
        "greetd/gtkgreet.css".text = css;
        "greetd/sway.conf".text = swayConfig;
      };
      pathsToLink = [ "/share/wayland-sessions" ];
      systemPackages = [ pkgs.bibata-cursors ];
    };
  };
}
