{
  palette,
}:
{ lib, ... }:
let
  # An absent optional appearance keeps portable CLI consumers on ANSI roles.
  colors =
    if palette == null then
      {
        blue = "blue";
        cyan = "cyan";
        green = "green";
        yellow = "yellow";
        purple = "magenta";
        fg = "default";
        border = "light_black";
      }
    else
      palette;
  section = label: color: {
    type = "custom";
    format = "{#${color}}╭─ ${label} ─────────────────────────╮{#}";
  };
  sectionEnd = color: {
    type = "custom";
    format = "{#${color}}╰────────────────────────────────────╯{#}";
  };
  key = glyph: label: color: {
    key = "${glyph} ${label}";
    keyColor = color;
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
            "1" = colors.blue;
            "2" = colors.cyan;
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
            output = colors.fg;
            separator = colors.border;
          };
          bar = {
            width = 8;
            char = {
              elapsed = "■";
              total = "─";
            };
            color = {
              total = colors.border;
              inherit (colors) border;
            };
          };
        };
        modules = [
          {
            type = "title";
            format = "{#${colors.purple}}{user-name}{#}{#${colors.border}}@{#}{#${colors.blue}}{host-name}{#}";
          }
          "break"
          (section "SYSTEM" colors.blue)
          ((key "" "OS" colors.blue) // { type = "os"; })
          ((key "" "Kernel" colors.cyan) // { type = "kernel"; })
          ((key "" "Up" colors.green) // { type = "uptime"; })
          ((key "󰏖" "Pkgs" colors.yellow) // { type = "packages"; })
          ((key "" "WM" colors.purple) // { type = "wm"; })
          (
            (key "󰍹" "Display" colors.blue)
            // {
              type = "display";
              compactType = "original-with-refresh-rate";
            }
          )
          (sectionEnd colors.blue)
          "break"
          (section "HARDWARE" colors.purple)
          ((key "" "CPU" colors.cyan) // { type = "cpu"; })
          (
            (key "󰾲" "GPU" colors.green)
            // {
              type = "gpu";
              format = "{vendor} {name}";
            }
          )
          (
            (key "" "Memory" colors.yellow)
            // {
              type = "memory";
              percent.type = 3;
            }
          )
          (
            (key "" "Disk" colors.yellow)
            // {
              type = "disk";
              folders = "/";
              percent.type = 3;
            }
          )
          (
            (key "" "Battery" colors.blue)
            // {
              type = "battery";
              percent.type = 3;
            }
          )
          (sectionEnd colors.purple)
          "break"
          {
            type = "colors";
            symbol = "circle";
          }
        ];
      };
    };

    # The CLI uses the shared One Dark Darker palette. HM remains the single
    # btop.conf renderer; Noctalia integration only supplies its own theme.
    btop = {
      enable = true;
      themes = lib.optionalAttrs (palette != null) {
        "One Dark Darker" = import ./onedark-darker-btop.nix { inherit palette; };
      };
      settings = {
        # Noctalia may select its own theme for the desktop session.
        color_theme = lib.mkDefault (if palette == null then "Default" else "One Dark Darker");
        # Keep the terminal background consistent with other CLI tools.
        theme_background = false;
        vim_keys = true;
      };
    };
  };
}
