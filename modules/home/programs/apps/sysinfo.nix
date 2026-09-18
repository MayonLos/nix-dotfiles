_:

{
  programs = {
    # `fastfetch` is run by hand, not on shell start, so it is allowed to be a
    # showpiece rather than something to scroll past.
    #
    # The hex below is deliberate and is the exception, not the rule: unlike
    # tmux or fzf, fastfetch draws its own colours rather than reading the
    # terminal palette, so it cannot follow a noctalia theme change. It is in
    # the same bucket as nvim, Emacs and fcitx5 -- pinned to Tokyo Night by
    # hand, retheme costs a rebuild. Values are the night variant, matching
    # ~/.config/foot/themes/noctalia.
    fastfetch = {
      enable = true;
      settings = {
        logo = {
          source = "nixos_small";
          padding.right = 2;
          color = {
            "1" = "#7aa2f7";
            "2" = "#7dcfff";
          };
        };
        display = {
          separator = "    ";
          color = {
            output = "#c0caf5";
            separator = "#414868";
          };
        };
        # One line per thing worth knowing about *this* machine: an Intel +
        # NVIDIA laptop, so both GPUs matter; mango rather than a desktop
        # environment, so `wm` is the interesting field and `de` is not.
        modules = [
          {
            type = "title";
            format = "{#BB9AF7}{user-name}{#565F89}@{#7AA2F7}{host-name}";
          }
          {
            type = "separator";
            string = "──────────────";
          }
          {
            type = "os";
            key = "OS";
            keyColor = "#7aa2f7";
          }
          {
            type = "kernel";
            key = "Kernel";
            keyColor = "#7dcfff";
          }
          {
            type = "uptime";
            key = "Uptime";
            keyColor = "#9ece6a";
          }
          {
            type = "packages";
            key = "Packages";
            keyColor = "#e0af68";
          }
          {
            type = "wm";
            key = "Compositor";
            keyColor = "#bb9af7";
          }
          {
            type = "display";
            key = "Display";
            keyColor = "#7aa2f7";
            compactType = "original-with-refresh-rate";
          }
          {
            type = "cpu";
            key = "CPU";
            keyColor = "#7dcfff";
          }
          {
            type = "gpu";
            key = "GPU";
            keyColor = "#9ece6a";
          }
          {
            type = "memory";
            key = "Memory";
            keyColor = "#e0af68";
          }
          {
            type = "disk";
            key = "Disk";
            keyColor = "#ff9e64";
            folders = "/";
          }
          {
            type = "battery";
            key = "Battery";
            keyColor = "#f7768e";
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
