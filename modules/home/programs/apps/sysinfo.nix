_:

let
  # Named ANSI colours follow Noctalia's terminal palette without text effects.
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
            keyColor = "red";
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

    # btop's palette comes from noctalia, which renders
    # themes/noctalia.theme. What is declared here is only which theme
    # btop *selects*, and that selection lives in btop.conf -- a file btop
    # itself rewrites on exit, which is why it was unmanaged and drifting.
    #
    # This does not fight noctalia even though noctalia's template does touch
    # btop.conf: its post_hook (assets/templates/btop/apply.sh) starts with
    # `grep -qE '^color_theme\s*=\s*"noctalia"'` and returns immediately when
    # the value is already right. Home Manager pins it to exactly that value,
    # so the hook always takes the no-op branch. Same arrangement as kitty's
    # `include` in programs/terminal/kitty.nix, and it breaks the same way if
    # the value here ever stops being "noctalia".
    btop = {
      enable = true;
      settings = {
        color_theme = "noctalia";
        # Use Kitty's background so Mango's blur remains visible behind panels.
        theme_background = false;
        vim_keys = true;
      };
    };
  };
}
