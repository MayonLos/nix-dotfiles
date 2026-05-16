{ pkgs, ... }:
{
  programs.waybar = {
    enable = true;
    package = pkgs.waybar;

    settings = [
      {
        layer = "top";
        position = "top";
        fixed-center = true;
        height = 40;
        margin-top = 0;
        margin-left = 0;
        margin-right = 0;
        margin-bottom = 0;
        spacing = 0;
        exclusive = true;
        passthrough = false;
        reload_style_on_change = true;

        modules-left = [
          "ext/workspaces"
        ];
        modules-center = [ "dwl/window" ];
        modules-right = [
          "tray"
          "backlight"
          "network"
          "wireplumber"
          "battery"
          "clock"
        ];

        "ext/workspaces" = {
          format = "{id}";
          ignore-hidden = true;
          sort-by-number = true;
          all-outputs = false;
          on-click = "activate";
          on-right-click = "deactivate";
        };

        "dwl/window" = {
          format = "{}";
          max-length = 72;
          rewrite = {
            "(.*) — Mozilla Firefox" = "$1";
            "(.*) - fish" = "$1";
            "(.*) - nvim" = "$1";
          };
        };

        tray = {
          icon-size = 15;
          spacing = 10;
        };

        network = {
          interval = 10;
          format-wifi = "<span foreground='#61afef'> </span>{signalStrength}%";
          format-ethernet = "<span foreground='#61afef'>󰈀 </span>{ifname}";
          format-linked = "<span foreground='#56b6c2'>󰈁 </span>{ifname}";
          format-disconnected = "<span foreground='#e5c07b'>󰖪 </span>offline";
          format-disabled = "<span foreground='#5c6370'>󰖪 </span>disabled";
          tooltip-format-wifi = "{ssid}  {signalStrength}%\n{ipaddr}";
          tooltip-format-ethernet = "{ifname}\n{ipaddr}";
          tooltip-format-disconnected = "Disconnected";
          on-click = "foot -e nmtui";
        };

        wireplumber = {
          format = "<span foreground='#98c379'>{icon}</span>{volume}%";
          format-muted = "<span foreground='#5c6370'>󰝟 </span>mute";
          format-icons = [
            " "
            " "
            " "
          ];
          max-volume = 150;
          on-click = "pavucontrol";
          on-click-right = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
          on-scroll-up = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.05+ -l 1.0";
          on-scroll-down = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.05-";
        };

        backlight = {
          device = "intel_backlight";
          format = "<span foreground='#e5c07b'>󰃠 </span>{percent}%";
          on-scroll-up = "brightnessctl --class=backlight set +5%";
          on-scroll-down = "brightnessctl --class=backlight set 5%-";
        };

        battery = {
          interval = 30;
          states = {
            warning = 30;
            critical = 15;
          };
          format = "<span foreground='#98c379'>{icon} </span>{capacity}%";
          format-warning = "<span foreground='#e5c07b'>{icon} </span>{capacity}%";
          format-critical = "<span foreground='#e06c75'>{icon} </span>{capacity}%";
          format-charging = "<span foreground='#98c379'>󰚥 </span>{capacity}%";
          format-plugged = "<span foreground='#98c379'> </span>{capacity}%";
          format-full = "<span foreground='#98c379'>󰁹 </span>{capacity}%";
          format-icons = [
            ""
            ""
            ""
            ""
            ""
          ];
          tooltip-format = "{time}";
        };

        clock = {
          format = "<span foreground='#c678dd'>󰥔 </span>{:%a %m-%d  %H:%M}";
          format-alt = "{:%Y-%m-%d %H:%M:%S}";
          tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
          calendar = {
            mode = "year";
            mode-mon-col = 3;
            on-scroll = 1;
            on-click-right = "mode";
            format = {
              months = "<span color='#abb2bf'><b>{}</b></span>";
              days = "<span color='#828997'>{}</span>";
              weeks = "<span color='#61afef'><b>W{}</b></span>";
              weekdays = "<span color='#56b6c2'><b>{}</b></span>";
              today = "<span color='#e06c75'><b><u>{}</u></b></span>";
            };
          };
        };
      }
    ];

    style = ''
      * {
        font-family: "IosevkaTerm Nerd Font", "JetBrainsMono Nerd Font", monospace;
        font-size: 14px;
        border: none;
        border-radius: 0;
        min-height: 0;
        margin: 0;
        padding: 0;
        box-shadow: none;
        text-shadow: none;
        color: #abb2bf;
      }

      window#waybar {
        background: rgba(40, 44, 52, 0.72);
        color: #abb2bf;
        border-bottom: 1px solid rgba(92, 99, 112, 0.28);
        border-radius: 0;
      }

      window#waybar > box {
        padding: 4px 12px;
      }

      .modules-left,
      .modules-center,
      .modules-right {
        background: transparent;
      }

      tooltip {
        background: rgba(31, 35, 41, 0.94);
        border: 1px solid rgba(92, 99, 112, 0.45);
        border-radius: 12px;
      }

      tooltip label {
        color: #abb2bf;
        padding: 8px 10px;
      }

      #workspaces,
      #tray,
      #backlight,
      #window,
      #network,
      #wireplumber,
      #battery,
      #clock {
        min-height: 30px;
        background: transparent;
      }

      #workspaces {
        padding: 0 10px 0 0;
      }

      #workspaces button {
        min-width: 28px;
        padding: 0 8px;
        margin: 0 4px 0 0;
        color: #5c6370;
        background: transparent;
        border-bottom: 2px solid transparent;
        transition: all 0.18s ease;
      }

      #workspaces button:hover {
        color: #abb2bf;
        background: rgba(97, 175, 239, 0.10);
        border-bottom-color: rgba(97, 175, 239, 0.25);
      }

      #workspaces button.active {
        color: #61afef;
        background: rgba(97, 175, 239, 0.12);
        border-bottom-color: #61afef;
        font-weight: 600;
      }

      #workspaces button.visible {
        color: #7f848e;
      }

      #workspaces button.urgent {
        color: #e06c75;
        border-bottom-color: #e06c75;
      }

      #window {
        padding: 0 18px;
        color: #828997;
        font-weight: 500;
      }

      #window.empty {
        background: transparent;
        color: transparent;
      }

      #tray,
      #backlight,
      #network,
      #wireplumber,
      #battery,
      #clock {
        padding: 0 10px;
        margin-left: 2px;
        color: #abb2bf;
      }

      #tray {
        padding-right: 12px;
        margin-right: 4px;
      }

      #tray > .passive {
        -gtk-icon-effect: dim;
      }

      #tray > .needs-attention {
        -gtk-icon-effect: highlight;
        background: rgba(224, 108, 117, 0.14);
        border-radius: 8px;
      }

      #backlight:hover,
      #network:hover,
      #wireplumber:hover,
      #battery:hover,
      #clock:hover {
        background: rgba(171, 178, 191, 0.08);
        border-radius: 8px;
      }

      #network.disconnected {
        color: #e5c07b;
      }

      #network.disabled,
      #wireplumber.muted {
        color: #5c6370;
      }

      #battery.warning {
        color: #e5c07b;
      }

      #battery.critical {
        color: #e06c75;
      }

      #battery.charging,
      #battery.plugged {
        color: #98c379;
      }

      #clock {
        color: #d7dae0;
        font-weight: 500;
        margin-left: 6px;
      }
    '';
  };
}
