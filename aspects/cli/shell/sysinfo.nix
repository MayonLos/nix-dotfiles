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
        red = "red";
        green = "green";
        yellow = "yellow";
        purple = "magenta";
        fg = "default";
        brightFg = "default";
        border = "light_black";
      }
    else
      palette;
  key = label: {
    key = label;
    keyColor = colors.blue;
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
            width = 8;
            paddingLeft = 1;
          };
          color = {
            output = colors.brightFg;
            separator = colors.border;
          };
        };
        modules = [
          {
            type = "title";
            format = "{#${colors.brightFg}}{user-name}@{host-name}{#}";
          }
          "break"
          ((key "OS") // { type = "os"; })
          ((key "Kernel") // { type = "kernel"; })
          ((key "WM") // { type = "wm"; })
          ((key "Terminal") // { type = "terminal"; })
          ((key "CPU") // { type = "cpu"; })
          (
            (key "GPU")
            // {
              type = "gpu";
              format = "{vendor} {name}";
            }
          )
          (
            (key "Memory")
            // {
              type = "memory";
            }
          )
          {
            type = "custom";
            format = lib.concatMapStringsSep " " (color: "{#${color}}██{#}") [
              colors.red
              colors.green
              colors.yellow
              colors.blue
              colors.purple
              colors.cyan
            ];
          }
        ];
      };
    };

    # Home Manager is the sole btop.conf renderer, using the shared palette.
    btop = {
      enable = true;
      themes = lib.optionalAttrs (palette != null) {
        "One Dark" = import ./onedark-btop.nix { inherit palette; };
      };
      settings = {
        # Keep btop on its generated palette theme as the sole config writer.
        color_theme = lib.mkDefault (if palette == null then "Default" else "One Dark");
        # Keep the terminal background consistent with other CLI tools.
        theme_background = false;
        rounded_corners = true;
        vim_keys = true;
      };
    };
  };
}
