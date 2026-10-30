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
        muted = "light_black";
        green = "green";
        yellow = "yellow";
        red = "red";
      }
    else
      palette;
  key = label: {
    key = label;
    keyColor = colors.fg;
  };
  section = name: {
    type = "custom";
    format = "{#${colors.blue}}${name}{#${colors.border}} ${
      builtins.concatStringsSep "" (builtins.genList (_: "─") (32 - builtins.stringLength name))
    }{#}";
  };
in

{
  programs = {
    fastfetch = {
      enable = true;
      settings = {
        logo = {
          source = "nixos";
          color = {
            "1" = colors.blue;
            "2" = colors.cyan;
            "3" = colors.blue;
            "4" = colors.cyan;
            "5" = colors.blue;
            "6" = colors.cyan;
          };
          padding = {
            top = 1;
            right = 3;
          };
        };
        display = {
          hideCursor = true;
          disableLinewrap = true;
          brightColor = false;
          separator = "  ";
          size.binaryPrefix = "iec";
          bar = {
            width = 12;
            color.total = colors.border;
            border = {
              left = "";
              right = "";
            };
            char = {
              elapsed = "━";
              total = "━";
            };
          };
          percent = {
            type = 3;
            color = {
              inherit (colors) green yellow red;
            };
          };
          key = {
            width = 13;
            paddingLeft = 2;
          };
          color = {
            output = colors.brightFg;
            separator = colors.border;
          };
        };
        modules = [
          {
            type = "title";
            format = "{#${colors.brightFg}}{user-name}{#${colors.muted}}@{#${colors.blue}}{host-name}{#}";
          }
          (section "System")
          ((key "OS") // { type = "os"; })
          ((key "Host") // { type = "host"; })
          ((key "Kernel") // { type = "kernel"; })
          ((key "Uptime") // { type = "uptime"; })
          ((key "Packages") // { type = "packages"; })
          (section "Desktop")
          ((key "WM") // { type = "wm"; })
          ((key "Shell") // { type = "shell"; })
          ((key "Terminal") // { type = "terminal"; })
          ((key "Font") // { type = "terminalfont"; })
          ((key "Theme") // { type = "theme"; })
          ((key "Icons") // { type = "icons"; })
          (
            (key "Display")
            // {
              type = "display";
              compactType = "original-with-refresh-rate";
            }
          )
          (section "Hardware")
          ((key "CPU") // { type = "cpu"; })
          (
            (key "GPU")
            // {
              type = "gpu";
              # PCI detection only: asking the NVIDIA driver would wake the dGPU.
              detectionMethod = "pci";
              temp = false;
            }
          )
          ((key "Memory") // { type = "memory"; })
          ((key "Swap") // { type = "swap"; })
          (
            (key "Disk")
            // {
              type = "disk";
              folders = "/";
            }
          )
          ((key "Battery") // { type = "battery"; })
          (section "Network")
          (
            (key "Wi-Fi")
            // {
              type = "wifi";
              percent.type = 1;
            }
          )
          (
            (key "Local IP")
            // {
              type = "localip";
              # Not the Clash TUN's reserved address.
              namePrefix = "wlp";
              defaultRouteOnly = false;
            }
          )
          "break"
          {
            type = "colors";
            paddingLeft = 2;
            symbol = "circle";
          }
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
