{ pkgs, ... }:
let
  powermenu = pkgs.writeShellScriptBin "powermenu" ''
    #!${pkgs.bash}/bin/bash
    FUZZEL="${pkgs.fuzzel}/bin/fuzzel"
    SWAYLOCK="${pkgs.swaylock-effects}/bin/swaylock"

    choice=$(printf ' Lock\n Suspend\n Reboot\n Poweroff\n Logout' \
      | "$FUZZEL" --dmenu \
          --prompt=' ' \
          --lines=5 \
          --width=20 \
          --anchor=center) || exit 0

    case "$choice" in
      *Lock*)     "$SWAYLOCK" ;;
      *Suspend*)  systemctl suspend ;;
      *Reboot*)   systemctl reboot ;;
      *Poweroff*) systemctl poweroff ;;
      *Logout*)   pkill -x mango ;;
    esac
  '';
in
{
  home.packages = [ powermenu ];
}
