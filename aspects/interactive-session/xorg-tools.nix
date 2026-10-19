{ pkgs, lib, ... }:
let
  screenshot = pkgs.writeShellApplication {
    name = "xorg-screenshot";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      usage() {
        echo "usage: xorg-screenshot screen|region" >&2
        exit 2
      }

      [ "$#" -eq 1 ] || usage
      mode="$1"
      case "$mode" in
        screen|region) ;;
        *) usage ;;
      esac

      image="$(mktemp --suffix=.png)"
      trap 'rm -f "$image"' EXIT

      if [ "$mode" = region ]; then
        # slop exits nonzero when the user cancels; that is a normal no-op.
        if ! geometry="$(${lib.getExe pkgs.slop} -f '%x %y %w %h')"; then
          exit 0
        fi
        read -r x y width height extra <<< "$geometry"
        [ -n "''${x:-}" ] && [ -n "''${y:-}" ] \
          && [ -n "''${width:-}" ] && [ -n "''${height:-}" ] \
          && [ -z "''${extra:-}" ] || exit 1
        case "$x" in -*) xoffset="$x" ;; *) xoffset="+$x" ;; esac
        case "$y" in -*) yoffset="$y" ;; *) yoffset="+$y" ;; esac
        ${lib.getExe pkgs.maim} -g "''${width}x''${height}''${xoffset}''${yoffset}" "$image"
      else
        ${lib.getExe pkgs.maim} "$image"
      fi

      ${lib.getExe pkgs.xclip} -selection clipboard -t image/png -i "$image"
      ${pkgs.libnotify}/bin/notify-send "Screenshot copied" \
        "$([ "$mode" = region ] && echo 'Selected region' || echo 'Full screen')" || true
    '';
  };

  audio = pkgs.writeShellApplication {
    name = "xorg-audio";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
    ];
    text = ''
      usage() {
        echo "usage: xorg-audio up|down|mute [step-percent]" >&2
        exit 2
      }
      [ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage
      action="$1"
      step="''${2:-5}"
      case "$step" in
        ""|*[!0-9]*) usage ;;
      esac
      [ "$step" -ge 1 ] && [ "$step" -le 25 ] || usage

      case "$action" in
        up) ${lib.getExe' pkgs.wireplumber "wpctl"} set-volume --limit 1.0 @DEFAULT_AUDIO_SINK@ "''${step}%+" ;;
        down) ${lib.getExe' pkgs.wireplumber "wpctl"} set-volume @DEFAULT_AUDIO_SINK@ "''${step}%-" ;;
        mute) ${lib.getExe' pkgs.wireplumber "wpctl"} set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
        *) usage ;;
      esac

      status="$(${lib.getExe' pkgs.wireplumber "wpctl"} get-volume @DEFAULT_AUDIO_SINK@)"
      if [[ "$status" =~ ^Volume:\ ([0-9]+(\.[0-9]+)?)(\ \[MUTED\])?$ ]]; then
        percent="$(awk -v volume="''${BASH_REMATCH[1]}" 'BEGIN { printf "%d", volume * 100 + 0.5 }')"
        if [[ "$status" == *'[MUTED]'* ]]; then
          ${lib.getExe pkgs.libnotify} "Audio muted" "$percent%"
        else
          ${lib.getExe pkgs.libnotify} "Audio volume" "$percent%"
        fi
      fi
    '';
  };

  brightness = pkgs.writeShellApplication {
    name = "xorg-brightness";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      usage() {
        echo "usage: xorg-brightness up|down [step-percent]" >&2
        exit 2
      }
      [ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage
      action="$1"
      step="''${2:-5}"
      case "$step" in
        ""|*[!0-9]*) usage ;;
      esac
      [ "$step" -ge 1 ] && [ "$step" -le 25 ] || usage

      case "$action" in
        up) ${lib.getExe pkgs.brightnessctl} set "''${step}%+" >/dev/null ;;
        down) ${lib.getExe pkgs.brightnessctl} set "''${step}%-" >/dev/null ;;
        *) usage ;;
      esac

      percent="$(${lib.getExe pkgs.brightnessctl} -m | cut -d, -f4 | tr -d '%')"
      case "$percent" in
        ""|*[!0-9]*) exit 1 ;;
      esac
      ${lib.getExe pkgs.libnotify} "Brightness" "$percent%"
    '';
  };

  media = pkgs.writeShellApplication {
    name = "xorg-media";
    text = ''
      [ "$#" -eq 1 ] || {
        echo "usage: xorg-media play-pause|next|previous|stop" >&2
        exit 2
      }
      case "$1" in
        play-pause|next|previous|stop) exec ${lib.getExe pkgs.playerctl} "$1" ;;
        *) echo "usage: xorg-media play-pause|next|previous|stop" >&2; exit 2 ;;
      esac
    '';
  };
in
{
  home.packages = [
    pkgs.brightnessctl
    pkgs.maim
    pkgs.playerctl
    pkgs.slop
    pkgs.wireplumber
    pkgs.xclip
    screenshot
    audio
    brightness
    media
  ];
}
