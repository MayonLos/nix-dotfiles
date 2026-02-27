{ config, ... }:

let
  terminalLauncher = "${config.home.homeDirectory}/.local/bin/thunar-open-terminal";
in
{
  home.file.".local/bin/thunar-open-terminal" = {
    executable = true;
    text = ''
      #!/usr/bin/env sh
      # In Wayland sessions (niri), use foot. In X11 sessions (dwm), use st.
      if [ -n "''${NIRI_SOCKET-}" ] || [ "''${XDG_SESSION_TYPE-}" = "wayland" ]; then
        exec foot
      fi

      exec st
    '';
  };

  home.file.".config/xfce4/helpers.rc".text = ''
    TerminalEmulator=${terminalLauncher}
  '';
}
