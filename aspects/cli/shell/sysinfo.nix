{
  palette,
}:
{ lib, pkgs, ... }:
let
  # An absent optional appearance keeps portable CLI consumers on ANSI roles.
  colors =
    if palette == null then
      {
        blue = "blue";
        cyan = "cyan";
        fg = "default";
        brightFg = "default";
        border = "light_black";
      }
    else
      palette;
  key = label: {
    key = label;
    keyColor = colors.fg;
  };
in

{
  programs = {
    fastfetch = {
      enable = true;
      settings = {
        logo.type = "none";
        display = {
          hideCursor = true;
          disableLinewrap = true;
          brightColor = false;
          separator = "  ";
          key = {
            width = 10;
            paddingLeft = 0;
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
          ((key "System") // { type = "os"; })
          ((key "Kernel") // { type = "kernel"; })
          ((key "Terminal") // { type = "terminal"; })
          (
            (key "Memory")
            // {
              type = "memory";
            }
          )
        ];
      };
    };

    # Home Manager is the sole btop.conf renderer, using the shared palette.
    btop = {
      enable = true;
      package = import ./btop-package.nix { inherit pkgs; };
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
        shown_boxes = "cpu mem proc";
        presets = "cpu:0:default,mem:0:default,proc:0:default cpu:0:default,mem:0:default,net:0:default,proc:0:default";
        show_cpu_cores = false;
        cpu_single_graph = true;
        check_temp = false;
        show_coretemp = false;
        show_cpu_watts = false;
        show_cpu_freq = false;
        show_gpu_info = "Off";
        show_battery = false;
        show_disks = false;
        clock_format = "";
      };
    };
  };
}
