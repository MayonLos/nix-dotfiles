{ palette }:
{ lib, pkgs, ... }:
let
  package = import ./package.nix { inherit pkgs; };
  launcher = pkgs.writeShellScriptBin "herdr-terminal" ''
    exec ${lib.getExe pkgs.kitty} --class=mayon-herdr --title=herdr ${lib.getExe package} "$@"
  '';
  toml = pkgs.formats.toml { };
in
{
  home.packages = [
    package
    launcher
  ];
  # The GUI settings editor must not become a second config writer.
  xdg.configFile."herdr/config.toml".source = toml.generate "herdr-config.toml" {
    onboarding = false;
    theme = {
      name = "one-dark";
      auto_switch = false;
      custom = {
        accent = palette.blue;
        panel_bg = palette.bg;
        sidebar_bg = palette.deep;
        active_row_bg = palette.selection;
        selection_bg = palette.selection;
        surface0 = palette.deep;
        surface1 = palette.surface;
        surface_dim = palette.deep;
        overlay0 = palette.muted;
        overlay1 = palette.fg;
        text = palette.brightFg;
        subtext0 = palette.fg;
        inherit (palette)
          green
          yellow
          red
          blue
          ;
        mauve = palette.purple;
        teal = palette.cyan;
        peach = palette.orange;
      };
    };
    ui = {
      accent = palette.blue;
      tab_bar_position = "bottom";
      hide_tab_bar_when_single_tab = false;
      pane_borders = "auto";
      pane_outer_borders = false;
      pane_gaps = false;
      status_indicators = "symbols";
      tab_bar_right = [
        {
          type = "datetime";
          format = "%H:%M";
        }
      ];
      tab_bar_right_separator = " · ";
    };
    update = {
      version_check = false;
      manifest_check = false;
    };
  };
  xdg.desktopEntries.herdr = {
    name = "herdr";
    genericName = "Agent terminal workspaces";
    comment = "Independent agent workspaces; tmux remains available";
    exec = "${launcher}/bin/herdr-terminal";
    icon = "utilities-terminal";
    terminal = false;
    categories = [
      "Development"
      "System"
      "TerminalEmulator"
    ];
    startupNotify = false;
    settings.StartupWMClass = "mayon-herdr";
  };
}
