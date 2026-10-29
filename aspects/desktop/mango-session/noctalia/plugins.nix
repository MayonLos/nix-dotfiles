{
  pkgs,
}:
let
  localSource = import ./local.nix { inherit pkgs; };
in
{
  # Repository-owned plugin sources are built by Nix and available offline.
  plugins = {
    # Enum since noctalia 5: all | official | none. A boolean is still
    # accepted but warns as deprecated at startup.
    auto_update = "none";

    source = [
      {
        name = "nix-dotfiles";
        kind = "path";
        location = "${localSource}";
        enabled = true;
      }
    ];

    # Only repository-owned plugins are loaded.
    enabled = [
      "nix-dotfiles/legion-conservation"
      "nix-dotfiles/launchpad"
      "nix-dotfiles/desktop-menus"
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
  };
}
