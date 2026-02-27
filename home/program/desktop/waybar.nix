{ ... }:

{
  programs.waybar = {
    enable = true;

    settings.mainBar = {
      layer = "top";
      position = "top";
      height = 34;
      spacing = 4;

      modules-left = [
        "niri/workspaces"
        "wlr/taskbar"
        "mpris"
      ];

      modules-center = [];

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

      "wlr/taskbar" = {
        format = "{icon}";
        icon-size = 16;
        tooltip-format = "{title}";
        on-click = "activate";
        on-click-middle = "close";
      };

      "mpris" = {
        format = "{player_icon}  {dynamic}";
        format-paused = "{status_icon}  {dynamic}";
        format-stopped = "󰓛  No Music";
        dynamic-len = 42;
        dynamic-order = [
          "artist"
          "title"
        ];
        dynamic-separator = " - ";
        player-icons = {
          default = "󰎆";
          musicfox = "󰎆";
        };
        status-icons = {
          paused = "󰏤";
          playing = "󰐊";
          stopped = "󰓛";
        };
        tooltip = true;
        tooltip-format = "{player}: {dynamic}";
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
        on-click = "missioncenter";
      };

      "pulseaudio" = {
        format = "{icon}  {volume}%";
        format-muted = "󰝟";
        format-icons = {
          headphone = "󰋋";
          headphones = "󰋋";
          headset = "󰋎";
          "hands-free" = "󰋎";
          default = [
            "󰕿"
            "󰖀"
            "󰕾"
          ];
        };
        on-click = "pavucontrol";
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

      #taskbar,
      #mpris,
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
        color: #abb2bf;
      }

      /* Make taskbar container transparent so when it's empty nothing remains */
      #taskbar {
        background: transparent;
        margin: 0;
        padding: 0;
      }

      /* Extra safeguard if waybar applies .empty */
      #taskbar.empty {
        background: transparent;
        margin: 0;
        min-width: 0;
        padding: 0;
      }

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

      #taskbar button {
        background: transparent;
        border: none;
        box-shadow: none;
        margin: 0 2px;
        padding: 0 6px;
        color: #abb2bf;
      }

      #taskbar button:hover {
        background: rgba(97, 175, 239, 0.12);
        border-radius: 6px;
        color: #dcdfe4;
      }

      #taskbar button.active {
        background: rgba(97, 175, 239, 0.2);
        border-radius: 6px;
        box-shadow: inset 0 -2px 0 #61afef;
        color: #61afef;
      }

      #clock {
        font-feature-settings: "tnum";
        color: #c678dd;
      }

      #network {
        color: #61afef;
      }

      #pulseaudio {
        color: #d19a66;
      }

      #memory {
        color: #98c379;
      }

      #battery {
        color: #56b6c2;
      }
    '';
  };
}
