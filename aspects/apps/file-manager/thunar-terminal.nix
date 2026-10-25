{ config, pkgs, ... }:

let
  terminal = config.home.sessionVariables.TERMINAL;
  terminalLauncher = pkgs.writeShellApplication {
    name = "thunar-open-terminal";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      target="''${1:-$PWD}"
      if [ -d "$target" ]; then
        directory="$target"
      else
        directory="$(dirname -- "$target")"
      fi
      exec ${terminal} --directory="$directory"
    '';
  };
in
{
  home.packages = [ terminalLauncher ];

  home.file.".config/xfce4/helpers.rc".text = ''
    TerminalEmulator=${terminalLauncher}/bin/thunar-open-terminal
  '';
}
