{
  pkgs,
  lib,
  nixos,
  appearance,
  ...
}:
let
  greetd = nixos.services.greetd;
  command = greetd.settings.default_session.command;
  css = nixos.environment.etc."greetd/gtkgreet.css".text;
  sway = nixos.environment.etc."greetd/sway.conf".text;
  session = lib.removeSuffix "\n" nixos.environment.etc."greetd/environments".text;
  commandFile = pkgs.writeText "greetd-command.txt" command;
  cssFile = pkgs.writeText "gtkgreet.css" css;
  swayFile = pkgs.writeText "greetd-sway.conf" sway;
in
{
  greeter-tech = pkgs.runCommand "greeter-tech-check" { } ''
    test ${if greetd.enable then "1" else "0"} = 1
    test ${if greetd.greeterManagesPlymouth then "1" else "0"} = 0
    gtkgreet_bin=$(sed -n "s/^exec '\([^ ]*\/bin\/gtkgreet\) .*/\1/p" ${swayFile})
    test -n "$gtkgreet_bin"
    test -x "$gtkgreet_bin"
    test -x ${lib.getExe pkgs.sway}
    test -x ${lib.getExe' pkgs.sway "swaymsg"}
    test ${toString (builtins.stringLength session)} -lt 128
    test -x ${session}
    case ${session} in
      *' '*) echo "gtkgreet login command must be one path" >&2; exit 1 ;;
    esac
    grep -Fq 'XDG_SESSION_TYPE=wayland' ${session}
    grep -Fq 'XDG_CURRENT_DESKTOP=mango:wlroots' ${session}
    grep -Fq 'XDG_SESSION_DESKTOP=mango' ${session}
    grep -Fq 'exec ' ${session}
    grep -Fq '${lib.getExe pkgs.sway} --config /etc/greetd/sway.conf' ${commandFile}
    grep -Fq 'XCURSOR_THEME=${appearance.cursor.name}' ${commandFile}
    grep -Fq 'XCURSOR_SIZE=${toString appearance.cursor.size}' ${commandFile}
    grep -Fq '${pkgs.bibata-cursors}/share/icons' ${commandFile}
    test -f ${pkgs.bibata-cursors}/share/icons/${appearance.cursor.name}/cursors/left_ptr
    grep -Fq 'output eDP-1 scale 1.5' ${swayFile}
    grep -Fq -- '-l -s /etc/greetd/gtkgreet.css -c ${session}' ${swayFile}
    grep -Fq 'background-size: cover' ${cssFile}
    grep -Fq '${appearance.fonts.sans}' ${cssFile}
    grep -Fq '${appearance.bg}' ${cssFile}
    wallpaper=$(sed -n 's/.*url("file:\/\/\(\/nix\/store\/[^"]*\)").*/\1/p' ${cssFile})
    test -n "$wallpaper"
    test -f "$wallpaper"
    touch "$out"
  '';
}
