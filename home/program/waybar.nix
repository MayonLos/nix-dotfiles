{ pkgs, ... }:

{
  programs.waybar = {
    enable = true;

    settings.mainBar = {
      layer = "top";
      position = "top";
      height = 32;
      spacing = 6;

      modules-left = [
        "wlr/taskbar"
        "niri/window"
      ];

      modules-center = [
        "niri/workspaces"
      ];

      modules-right = [
        "network"
        "pulseaudio"
        "backlight"
        "memory"
        "battery"
        "tray"
        "clock"
      ];

      "niri/workspaces" = {
        format = "{icon}";
        format-icons = {
          active = "";
          default = "";
        };
      };

      "niri/window" = {
        format = "{}";
        max-length = 45;
      };

      "wlr/taskbar" = {
        format = "{icon}";
        icon-size = 16;
        tooltip-format = "{title}";
        on-click = "activate";
        on-click-middle = "close";
      };

      "network" = {
        interval = 2;
        format-wifi = "  {essid}";
        format-ethernet = "󰈀  {ifname}";
        format-disconnected = "󰖪  Off";
        tooltip-format = "IP: {ipaddr}\nSignal: {signalStrength}%\n↓ {bandwidthDownBytes}\n↑ {bandwidthUpBytes}";
      };

      "memory" = {
        interval = 10;
        format = "󰍛  {used:0.1f}G";
      };

      "pulseaudio" = {
        format = "{icon}  {volume}%";
        format-muted = "󰝟";
        format-icons.default = [
          "󰕿"
          "󰖀"
          "󰕾"
        ];
      };

      "backlight" = {
        format = "{icon}  {percent}%";
        format-icons = [
          "󰃞"
          "󰃟"
          "󰃠"
        ];
      };

      "battery" = {
        interval = 60;
        format = "{icon}  {capacity}%";
        format-icons = [
          "󰂎"
          "󰁺"
          "󰁻"
          "󰁼"
          "󰁽"
          "󰁾"
          "󰁿"
          "󰂀"
          "󰂂"
          "󰁹"
        ];
      };

      "clock" = {
        interval = 1;
        format = "󱑂  {:%H:%M}";
        format-alt = "󰃭  {:%Y-%m-%d}";

        tooltip = true;

        tooltip-format = "<span size='9pt'>{calendar}</span>";

        calendar = {
          mode = "month";
          weeks-pos = "";

          format = {
            months = "<span color='#61afef'><b>{}</b></span>";
            weekdays = "<span color='#abb2bf'>{}</span>";
            days = "<span color='#dcdfe4'>{}</span>";
            today = "<span color='#e06c75'><b><u>{}</u></b></span>";
          };
        };
      };

      "tray" = {
        icon-size = 16;
        spacing = 10;
      };
    };

    style = ''
            * {
              font-family: "JetBrainsMono Nerd Font";
              font-size: 13px;
              font-weight: 600;
              min-height: 0;
            }

            window#waybar {
              background: #1f2329;
              border-bottom: 1px solid #2c313c;
              padding: 0 8px;
            }

            #network,
            #pulseaudio,
            #backlight,
            #memory,
            #battery,
            #tray,
            #clock {
              background: #282c34;
              border-radius: 8px;
              margin: 4px 3px;
              padding: 0 12px;
            }
            #clock {
              font-feature-settings: "tnum";
            }
            #network  { color: #61afef; }
            #memory   { color: #98c379; }
            #pulseaudio { color: #d19a66; }
            #battery  { color: #56b6c2; }
            #clock    { color: #c678dd; }
      #workspaces {
        background: transparent;
        margin: 4px 3px;
        padding: 0 6px;
      }

      #workspaces button {
        background: transparent;
        border: none;
        box-shadow: none;
        padding: 0 10px;
        color: #5c6370;
      }

      #workspaces button:hover {
        background: transparent;
        color: #abb2bf;
      }

      #workspaces button.active {
        background: transparent;
        border: none;
        box-shadow: none;
        color: #61afef;
      }

    '';
  };
}
