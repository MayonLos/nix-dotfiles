{ pkgs, ... }:

{
  programs.fuzzel = {
    enable = true;
    package = pkgs.fuzzel;

    settings = {
      main = {
        font = "JetBrains Mono Nerd Font:size=10";
        prompt = "\"Run > \"";
        placeholder = "Search apps or commands...";
        icons-enabled = false;
        terminal = "foot -e";

        layer = "overlay";
        anchor = "center";

        width = 38;
        lines = 8;
        horizontal-pad = 16;
        vertical-pad = 11;
        inner-pad = 7;
        line-height = 18;

        dpi-aware = "yes";
        fields = "name,generic,comment,categories,keywords";
        match-mode = "fzf";
        show-actions = true;
        match-counter = true;
      };

      colors = {
        background = "1b2029e6";
        text = "abb2bfff";
        prompt = "61afefff";
        placeholder = "5c6370ff";
        input = "dcdfe4ff";
        match = "98c379ff";
        selection = "30384af0";
        selection-text = "e6eaf2ff";
        selection-match = "98c379ff";
        counter = "56b6c2ff";
        border = "89b4facc";
      };

      border = {
        width = 1;
        radius = 14;
        selection-radius = 10;
      };
    };
  };

  home.file = {
    ".local/share/applications/system-poweroff.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=System: Power Off
      Comment=Shutdown the computer
      Exec=systemctl poweroff
      Terminal=false
      Categories=System;
    '';

    ".local/share/applications/system-reboot.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=System: Reboot
      Comment=Reboot the computer
      Exec=systemctl reboot
      Terminal=false
      Categories=System;
    '';

    ".local/share/applications/system-suspend.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=System: Suspend
      Comment=Suspend to RAM
      Exec=systemctl suspend
      Terminal=false
      Categories=System;
    '';

    ".local/share/applications/system-lock.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=System: Lock
      Comment=Lock screen
      Exec=swaylock
      Terminal=false
      Categories=System;
    '';

    ".local/share/applications/system-logout.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=System: Logout
      Comment=Exit current session
      Exec=niri msg action quit --skip-confirmation
      Terminal=false
      Categories=System;
    '';
  };
}
