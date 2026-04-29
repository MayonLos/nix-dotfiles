{ config, ... }:

let
  terminalLauncher = "${config.home.homeDirectory}/.local/bin/thunar-open-terminal";
in
{
  home.file.".local/bin/thunar-open-terminal" = {
    executable = true;
    text = ''
      #!/usr/bin/env sh
      exec foot
    '';
  };

  home.file.".config/xfce4/helpers.rc".text = ''
    TerminalEmulator=${terminalLauncher}
  '';
}
