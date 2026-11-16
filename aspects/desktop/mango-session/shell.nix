{ palette }:
{
  config,
  hostFacts,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  mkGraphicalService = import ../../../lib/service.nix;
  rgba = color: "${lib.removePrefix "#" color}ff";
  # mangobar's nerd glyphs sit in the private-use plane. JSON \u is four
  # digits, so each codepoint becomes a surrogate pair.
  glyph =
    cp:
    let
      n = cp - 65536;
      hi = 55296 + n / 1024;
      lo = 56320 + lib.mod n 1024;
      hex = value: lib.fixedWidthString 4 "0" (lib.toHexString value);
    in
    builtins.fromJSON "\"\\u${hex hi}\\u${hex lo}\"";
  g = hex: glyph (lib.fromHexString hex);
  logicalHeight = hostFacts.display.height * 1.0 / hostFacts.display.scale;
  # top_margin is a fraction of the output (0 exclusive, 1 exclusive in the
  # toml reader). Assume a 52px pill whose center is 96 + 26 logical px above
  # the bottom edge, matching the old OSD clearance on this panel.
  osdTopMargin = (logicalHeight - 96.0 - 26.0) / logicalHeight;
  osdStyle = pkgs.writeText "swayosd-style.css" ''
    /* Compact pill: the default inset and default GTK label/icon sizes made the
       volume OSD read as oversized next to the 30px bar. */
    window#osd {
      border-radius: 999px;
      background-color: ${palette.surface};
      border: 1px solid ${palette.border};
    }
    window#osd #container {
      margin: 8px 14px;
    }
    window#osd label {
      font-size: 13px;
      color: ${palette.brightFg};
    }
    window#osd image {
      -gtk-icon-size: 18px;
      color: ${palette.brightFg};
    }
    window#osd trough,
    window#osd segment {
      background-color: ${palette.selection};
      border-radius: 999px;
      min-height: 4px;
    }
    window#osd progress,
    window#osd segment.active {
      background-color: ${palette.blue};
      border-radius: 999px;
      min-height: 4px;
    }
  '';
  # mako 1.11.0 ships share/dbus-1/services/fr.emersion.mako.service whose
  # file name does not match org.freedesktop.Notifications, so dbus-broker logs
  # a naming warning and (with both the profile and ~/.local/share copies in
  # XDG_DATA_DIRS) also a duplicate-name warning. More importantly that file
  # only Exec's the binary: a notification arriving before the session unit
  # starts can make the bus launch a second daemon that binds the name first,
  # starving the unit. Drop the upstream file and install one correctly named
  # service that delegates activation to the user unit.
  makoPackage = pkgs.mako.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      rm -f $out/share/dbus-1/services/fr.emersion.mako.service
    '';
  });
  # mangobar 0.1.1 draws disabled DBusMenu items with a hardcoded 50% gray and
  # only applies CSS to `menuitem` / `menuitem:hover`, so the One Dark muted
  # colour cannot be expressed from the stylesheet. The patch adds that one
  # selector; it keeps the compiled 50% gray as the default when the stylesheet
  # does not set one.
  mangobarPackage = pkgs.local.mangobar.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./mangobar/menuitem-disabled.patch ];
    # The patch touches three files; fail rather than fuzz it into the wrong
    # place when upstream rewrites the menu drawing.
    patchFlags = "-p1 --fuzz=0";
    postPatch = (old.postPatch or "") + ''
      grep -Fq 'Style menuitem_disabled;' style.h
      grep -Fq 'ss->menuitem_disabled' style.c
      grep -Fq 'lr = dis_r;' mangobar.c
    '';
  });
in
{
  imports = [ inputs.mangobar.homeManagerModules.default ];

  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        # Columns, not pixels. 60 plus the 16px horizontal pad is near the
        # old 520px launcher. Inter has no CJK; fontconfig supplies the fallback.
        font = "${palette.fonts.sans}:size=14";
        terminal = lib.getExe pkgs.kitty;
        "icon-theme" = palette.iconTheme;
        width = 60;
        lines = 8;
        anchor = "center";
        layer = "overlay";
        "horizontal-pad" = 20;
        "vertical-pad" = 10;
        "inner-pad" = 2;
        "line-height" = 22;
      };
      colors = {
        background = rgba palette.surface;
        text = rgba palette.brightFg;
        match = rgba palette.blue;
        selection = rgba palette.selection;
        "selection-text" = rgba palette.brightFg;
        "selection-match" = rgba palette.blue;
        border = rgba palette.border;
      };
      border = {
        width = 1;
        radius = 12;
      };
    };
  };

  services = {
    mangobar = {
      enable = true;
      package = mangobarPackage;
      systemdTarget = "mango-session.target";
      settings = {
        layer = "top";
        height = 30;
        # buffer-scale defaults to 1 and multiplies the output scale. Setting 2
        # would double a 1.5 output. One profile, no output key: every output.
        # The window title sits in the center so the left group only carries the
        # layout symbol and workspace numbers.
        "modules-left" = [
          "layout"
          "workspaces"
          # Drawn only while the minimized count is greater than 0.
          "hideclients"
        ];
        "modules-center" = [ "window" ];
        "modules-right" = [
          "tray"
          "cpu"
          "memory"
          "network"
          "battery"
          "clock"
        ];
        workspaces = {
          "hide-empty" = true;
          "on-click" = "activate";
          "on-click-right" = "toggle";
        };
        # Client title from Mango IPC, not an application-resolved name.
        # max-length is pixels.
        window = {
          format = "{}";
          "max-length" = 300;
        };
        # layout_symbol from Mango, not the English word "tile".
        layout.format = "{}";
        tray = {
          "icon-size" = 18;
          spacing = 10;
        };
        network = {
          format = "{icon}";
          "format-wifi" = "{signal}";
          "format-ethernet" = "{icon}";
          "format-disconnected" = "{icon}";
          "icon-wifi" = g "F05A9";
          "icon-ethernet" = g "F0200";
          "icon-disconnected" = g "F05AA";
          "signal-icons" = map g [
            "F092F"
            "F091F"
            "F0922"
            "F0925"
            "F0928"
          ];
        };
        battery = {
          format = "{icon} {percent}%";
          icons = map g [
            "F008E"
            "F007A"
            "F007B"
            "F007C"
            "F007D"
            "F007E"
            "F007F"
            "F0080"
            "F0081"
            "F0082"
            "F0079"
          ];
          "icon-charging" = g "F0084";
          "icon-full" = g "F0079";
          "hide-on-ac" = false;
          "on-click" = "legion-conservation toggle";
        };
        # The fcitx tray already shows "en"; a keyboardlayout module would add
        # a second "us" label. {usage} is the /proc/stat percentage. {load} is
        # the 1-minute load average; the upstream example "{load}%" prints that
        # average with a percent sign. Memory {} is
        # (MemTotal-MemAvailable)/MemTotal. CSS ids are #cpu and #mem.
        cpu = {
          format = "CPU {usage}%";
          interval = 2;
        };
        memory = {
          format = "MEM {}%";
          interval = 2;
        };
        # Count of minimized clients. mangobar omits the module at 0.
        # CSS id is #hideclients. The glyph is nf-md-eye-off.
        hideclients.format = "${g "F0209"} {}";
        clock.format = "{:L%m月%d日 周%a %H:%M}";
      };
    };

    mako = {
      enable = true;
      package = makoPackage;
      settings = {
        anchor = "top-right";
        width = 360;
        # outer-margin is the list inset. margin is added per card, so a top
        # margin of 0 keeps the first card 42px below the screen edge, clear of
        # the 30px bar. The bottom 8px separates stacked cards.
        "outer-margin" = "42,28,0,0";
        margin = "0,0,8,0";
        padding = "14,16";
        "border-size" = 1;
        "border-color" = palette.border;
        "border-radius" = 12;
        "background-color" = palette.surface;
        "text-color" = palette.brightFg;
        font = "${palette.fonts.sans} 11";
        "max-visible" = 3;
        layer = "overlay";
        "default-timeout" = 5000;
        icons = true;
        "max-icon-size" = 32;
        # mako 1.11 has no built-in sound; on-notify runs one shell command per
        # opened notification. Store paths only: mako's spawn PATH is thin and
        # a missing audio daemon must not turn into a mako error.
        "on-notify" =
          "exec ${pkgs.pipewire}/bin/pw-play ${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/message-new-instant.oga >/dev/null 2>&1";
      };
    };

    swayosd = {
      enable = true;
      topMargin = osdTopMargin;
      stylePath = osdStyle;
    };
  };

  xdg.dataFile."dbus-1/services/org.freedesktop.Notifications.service".text = ''
    [D-BUS Service]
    Name=org.freedesktop.Notifications
    Exec=${lib.getExe makoPackage}
    SystemdService=mako.service
  '';

  xdg.configFile = {
    "mangobar/style.css".text = ''
      * {
        font-family: "${palette.fonts.mono}";
        font-size: 13px;
        font-weight: Medium;
        color: ${palette.brightFg};
        background: none;
        border-radius: 0;
        padding: 0;
        margin: 0;
      }
      #bar {
        /* Fully transparent: no fill and no blur behind the bar. */
        background: none;
        margin: 0;
        padding: 0 12px;
      }
      #tags {
        color: ${palette.fg};
        padding: 0;
        margin: 0 1px;
      }
      #tags.occupied {
        color: ${palette.fg};
      }
      #tags.empty {
        color: ${palette.muted};
      }
      #tags.active {
        color: ${palette.blue};
      }
      #tags.urgent {
        color: ${palette.red};
      }
      #tags.hover {
        color: ${palette.brightFg};
      }
      #layout {
        color: ${palette.fg};
        padding: 0;
        margin: 0 4px;
      }
      #hideclients {
        color: ${palette.muted};
        padding: 0 6px;
      }
      #title {
        color: ${palette.brightFg};
        padding: 0 8px;
      }
      #clock {
        color: ${palette.brightFg};
        padding: 0 12px;
      }
      #network {
        color: ${palette.brightFg};
        padding: 0 7px;
      }
      #battery {
        color: ${palette.brightFg};
        padding: 0 7px;
      }
      #cpu, #mem {
        color: ${palette.brightFg};
        padding: 0 7px;
      }
      #tray {
        padding: 0 4px;
      }
      /*
       * Tray context menus (StatusNotifierItem DBusMenu) belong to whichever
       * background program registered the item, so this block is the only
       * place that themes all of them at once: fcitx, Bluetooth, network and
       * any other SNI host use the same mangobar-drawn popup. mangobar draws
       * the popup itself with a 1px border and clamps the item rows to one
       * font; `menu`/`menuitem`/`menuitem:hover`/`menuitem:disabled` are the
       * only selectors it understands (style.c). Keep the same surface,
       * border and 12px radius as mako and fuzzel, and the bar text colour.
       */
      menu {
        background-color: ${palette.surface};
        border-color: ${palette.border};
        border-radius: 12px;
        font-size: 13px;
      }
      menuitem {
        color: ${palette.brightFg};
      }
      menuitem:hover {
        color: ${palette.brightFg};
        background-color: ${palette.selection};
      }
      menuitem:disabled {
        color: ${palette.muted};
      }
    '';

    "swayosd/config.toml".text = ''
      [server]
      top_margin = ${toString osdTopMargin}
      show_percentage = true
    '';
  };

  # mako 1.11.0 ships a D-Bus service that Exec's the binary and has no
  # SystemdService= line. This unit still owns the name for the session.
  # A notification that arrives before it is up can start a second process
  # through that Exec line; the second one fails to bind the name.
  systemd.user.services = {
    # The desktop has no shell-provided authentication agent. Keep one
    # session-scoped polkit agent so pkexec/GUI actions can prompt. The system
    # polkit daemon itself is enabled by session-support's host side.
    polkit-gnome-authentication-agent-1 = mkGraphicalService {
      target = "mango-session.target";
      description = "polkit authentication agent";
      unit = {
        StartLimitIntervalSec = 60;
        StartLimitBurst = 3;
      };
      service = {
        ExecCondition = "${pkgs.runtimeShell} -c '[ -n \"$WAYLAND_DISPLAY\" ]'";
        # nixpkgs installs the agent under libexec, not bin.
        ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };

    mangobar = {
      Unit = {
        StartLimitIntervalSec = 60;
        StartLimitBurst = 3;
        X-Restart-Triggers = [ config.xdg.configFile."mangobar/style.css".source ];
      };
      Service = {
        # force: The mangobar module waits 3s; session services here wait 2s.
        RestartSec = lib.mkForce 2;
        UnsetEnvironment = [ "LC_ALL" ];
        # %a is "Sun" unless the clock runs in zh_CN. LC_ALL would hide LC_TIME.
        Environment = [ "LC_TIME=zh_CN.UTF-8" ];
      };
    };

    mako = mkGraphicalService {
      target = "mango-session.target";
      description = "mako notification daemon";
      unit = {
        StartLimitIntervalSec = 60;
        StartLimitBurst = 3;
      };
      service = {
        Type = "dbus";
        BusName = "org.freedesktop.Notifications";
        ExecCondition = "${pkgs.runtimeShell} -c '[ -n \"$WAYLAND_DISPLAY\" ]'";
        ExecStart = lib.getExe config.services.mako.package;
        ExecReload = "${lib.getExe' config.services.mako.package "makoctl"} reload";
        Restart = "always";
        RestartSec = 2;
      };
    };

    swayosd = {
      Unit = {
        # force: The swayosd module follows graphical-session.target; this session is mango-session.target.
        PartOf = lib.mkForce [ "mango-session.target" ];
        # force: The swayosd module follows graphical-session.target; this session is mango-session.target.
        After = lib.mkForce [ "mango-session.target" ];
        # force: The swayosd module allows five starts in ten seconds; session services here allow three in sixty.
        StartLimitBurst = lib.mkForce 3;
        # force: The swayosd module allows five starts in ten seconds; session services here allow three in sixty.
        StartLimitIntervalSec = lib.mkForce 60;
        X-Restart-Triggers = [ config.xdg.configFile."swayosd/config.toml".source ];
      };
      # force: The swayosd module follows graphical-session.target; this session is mango-session.target.
      Install.WantedBy = lib.mkForce [ "mango-session.target" ];
    };
  };
}
