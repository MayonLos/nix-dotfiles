_:

{
  programs = {
    # `fastfetch` is run by hand, not on shell start, so it is allowed to be a
    # showpiece rather than something to scroll past.
    #
    # Colours are ANSI indices, not hex, for two reasons. The first is that hex
    # in a `{#...}` format string is not reliably accepted: fastfetch 2.63.1
    # rejected `{#BB9AF7}` with `invalid color code found: BB9AF7`. The second
    # is the one that matters more -- an index is resolved by foot from the
    # palette noctalia renders, so this follows a theme change for free. An
    # earlier version of this file used hex and claimed in a comment that
    # fastfetch "draws its own colours rather than reading the terminal
    # palette". That was simply wrong: it emits ANSI escapes like anything else.
    #
    # Index -> Tokyo Night, straight out of ~/.config/foot/themes/noctalia:
    #   1 red #f7768e   2 green #9ece6a   3 yellow #e0af68   4 blue #7aa2f7
    #   5 magenta #bb9af7   6 cyan #7dcfff   8 bright0 #414868   15 #c0caf5
    fastfetch = {
      enable = true;
      settings = {
        logo = {
          source = "nixos_small";
          padding.right = 2;
          color = {
            "1" = "4";
            "2" = "6";
          };
        };
        display = {
          separator = "    ";
          color = {
            output = "15";
            separator = "8";
          };
        };
        # One line per thing worth knowing about *this* machine: an Intel +
        # NVIDIA laptop, so both GPUs matter; mango rather than a desktop
        # environment, so `wm` is the interesting field and `de` is not.
        modules = [
          {
            type = "title";
            format = "{#5}{user-name}{#8}@{#4}{host-name}";
          }
          {
            type = "separator";
            string = "──────────────";
          }
          {
            type = "os";
            key = "OS";
            keyColor = "4";
          }
          {
            type = "kernel";
            key = "Kernel";
            keyColor = "6";
          }
          {
            type = "uptime";
            key = "Uptime";
            keyColor = "2";
          }
          {
            type = "packages";
            key = "Packages";
            keyColor = "3";
          }
          {
            type = "wm";
            key = "Compositor";
            keyColor = "5";
          }
          {
            type = "display";
            key = "Display";
            keyColor = "4";
            compactType = "original-with-refresh-rate";
          }
          {
            type = "cpu";
            key = "CPU";
            keyColor = "6";
          }
          {
            type = "gpu";
            key = "GPU";
            keyColor = "2";
          }
          {
            type = "memory";
            key = "Memory";
            keyColor = "3";
          }
          {
            type = "disk";
            key = "Disk";
            keyColor = "3";
            folders = "/";
          }
          {
            type = "battery";
            key = "Battery";
            keyColor = "1";
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
    # so the hook always takes the no-op branch. Same arrangement as foot's
    # `include` in programs/terminal/foot.nix, and it breaks the same way if
    # the value here ever stops being "noctalia".
    btop = {
      enable = true;
      settings.color_theme = "noctalia";
    };
  };
}
