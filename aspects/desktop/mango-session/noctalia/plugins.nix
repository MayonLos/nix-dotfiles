{
  inputs,
  pkgs,
}:
let
  communitySource = import ./community.nix {
    inherit pkgs;
    source = inputs.noctalia-plugins-community;
  };
  localSource = import ./local.nix { inherit pkgs; };
in
{
  # Immutable plugin sources are pinned by flake.lock and available
  # offline. Git sources fetch during startup; update them through Nix.
  plugins = {
    # Enum since noctalia 5: all | official | none. A boolean is still
    # accepted but warns as deprecated at startup.
    auto_update = "none";

    source = [
      {
        name = "official";
        kind = "path";
        location = "${inputs.noctalia-plugins-official}";
        enabled = true;
      }
      {
        name = "community";
        kind = "path";
        # Keep the official community source identity and every untouched
        # plugin; build-time overlay copies only the three customized bar plugins.
        location = "${communitySource}";
        enabled = true;
      }
      {
        name = "nix-dotfiles";
        kind = "path";
        location = "${localSource}";
        enabled = true;
      }
    ];

    # The pre-start ownership handoff removes only declared public
    # override paths, backing up those values before starting the writer.
    # Avoid compositor editor plugins that write the read-only HM config
    # and plugins whose external tools only support Hyprland.
    enabled = [
      "3ri4ng0ld/ip-monitor"
      "8bury/mini-docker"
      "cleboost/jetbrains-provider"
      "dunarand/tmux-provider"
      "noctalia/translator"
      "radimous/prismlauncher-instances"
      "rxtsel/portctl"
      "ezequiel/mango_layouts" # jq + mmsg
      # Markdown notes, todos and /nt launcher entry; AI calls Go directly.
      "fel/quill"
      "gambled23/mangowm-keymode" # mmsg; shows the keymode SUPER,R enters
      "knyrps/nix-search"
      "nix-dotfiles/legion-conservation"
      "nix-dotfiles/launchpad"
      "nix-dotfiles/desktop-menus"

      # Notes/todo plugins were consolidated into Quill. OCR is provided
      # by the native Print bindings; its plugin had no configured entry.
      # The unused DeepSeek balance widget is disabled; its GUI data is
      # left in the runtime state, outside this store configuration.
    ];
  };

  # Plugin-level [[setting]] values belong here; [[widget.setting]]
  # values belong in widget."<plugin-id>:<entry-id>". Keep secrets in
  # runtime state or supported runtime files, never in Nix strings.
  plugin_settings = {
    "nix-dotfiles/launchpad".hidden_apps = [
      "org.fcitx.fcitx5-migrator"
      "org.fcitx.fcitx5-config-qt"
      "thunar-settings"
      "org.xfce.thunar-settings"
      "thunar-bulk-rename"
      "org.xfce.thunar-bulk-rename"
      "thunar-volman-settings"
      "org.xfce.volman"
      "org.fcitx.Fcitx5"
      "rofi"
      "rofi-theme-selector"
      "org.fcitx.fcitx5-configtool"
      "fcitx5-configtool"
      "kbd-layout-viewer5"
      "libreoffice-base"
      "libreoffice-draw"
      "libreoffice-math"
      "libreoffice-startcenter"
      "base"
      "draw"
      "math"
      "startcenter"
      "qt6ct"
      "xterm"
      "vim"
      "gvim"
      "nixos-manual"
      "mark-shot-edit"
    ];
    # These are pictures only: neither user's desktop files nor app launch
    # commands change. Missing override resources fall back to native lookup.
    "nix-dotfiles/launchpad".icon_overrides = [
      "nvim=${pkgs.unstable.neovim-unwrapped}/share/icons/hicolor/128x128/apps/nvim.png"
      "workspace-task-terminal=${../resources/terminal-clock.svg}"
      "Dead by Daylight=${../resources/dead-by-daylight.jpg}"
    ];
    "nix-dotfiles/desktop-menus" = {
      system_placement = "floating";
      system_position = "top_left";
      system_open_near_click = true;
    };
    # Explicit /tr queries use the selected online provider; ordinary launcher
    # searches never go through the translation service.
    "noctalia/translator" = {
      provider = "google";
      target_lang = "zh-CN";
    };
    # Noctalia injects generic panel settings for non-persistent entries.
    "ezequiel/mango_layouts" = {
      panel_placement = "attached";
      panel_position = "auto";
      panel_open_near_click = true;
    };
    # Call Go directly without the removed CLI. Use its raw model ID;
    # the locked plugin still defaults to the older Zen endpoint/model.
    "fel/quill" = {
      ai_backend = "opencode-go";
      ai_model = "deepseek-v4.1-flash";
      ai_base_url = "https://opencode.ai/inference/go/openai/v1";
    };
  };
}
