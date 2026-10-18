{ lib, ... }:
let
  # Named ANSI colours consume the terminal's palette without extra effects.
  section = label: color: {
    type = "custom";
    format = "{#${color}}── ${label} {#light_black}────────────────{#}";
  };
in

{
  programs = {
    fastfetch = {
      enable = true;
      settings = {
        logo = {
          type = "builtin";
          source = "NixOS_small";
          position = "left";
          padding.right = 2;
          color = {
            "1" = "blue";
            "2" = "cyan";
          };
        };
        display = {
          hideCursor = true;
          disableLinewrap = true;
          brightColor = false;
          separator = "  ";
          key = {
            width = 12;
            paddingLeft = 1;
          };
          color = {
            output = "default";
            separator = "light_black";
          };
          bar = {
            width = 8;
            char = {
              elapsed = "■";
              total = "─";
            };
            color = {
              total = "light_black";
              border = "light_black";
            };
          };
        };
        modules = [
          {
            type = "title";
            format = "{#bold_magenta}{user-name}{#}{#light_black}@{#blue}{host-name}{#}";
          }
          "break"
          (section "SYSTEM" "blue")
          {
            type = "os";
            key = " OS";
            keyColor = "blue";
          }
          {
            type = "kernel";
            key = " Kernel";
            keyColor = "cyan";
          }
          {
            type = "uptime";
            key = " Up";
            keyColor = "green";
          }
          {
            type = "packages";
            key = "󰏖 Pkgs";
            keyColor = "yellow";
          }
          {
            type = "wm";
            key = " WM";
            keyColor = "magenta";
          }
          {
            type = "display";
            key = "󰍹 Display";
            keyColor = "blue";
            compactType = "original-with-refresh-rate";
          }
          "break"
          (section "HARDWARE" "magenta")
          {
            type = "cpu";
            key = " CPU";
            keyColor = "cyan";
          }
          {
            type = "gpu";
            key = "󰾲 GPU";
            keyColor = "green";
            format = "{vendor} {name}";
          }
          {
            type = "memory";
            key = " Memory";
            keyColor = "yellow";
            percent.type = 3;
          }
          {
            type = "disk";
            key = " Disk";
            keyColor = "yellow";
            folders = "/";
            percent.type = 3;
          }
          {
            type = "battery";
            key = " Battery";
            keyColor = "blue";
            percent.type = 3;
          }
          "break"
          {
            type = "colors";
            symbol = "circle";
          }
        ];
      };
    };

    # The portable CLI uses btop's built-in theme. A selected desktop may
    # choose Noctalia's palette; HM remains the single btop.conf renderer.
    btop = {
      enable = true;
      settings = {
        color_theme = lib.mkDefault "Default";
        # Keep the terminal background consistent with other CLI tools.
        theme_background = false;
        vim_keys = true;
      };
    };
  };
}
