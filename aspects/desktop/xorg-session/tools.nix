{ palette }:
{
  pkgs,
  lib,
  config,
  ...
}:
let
  wallpapers = import ../../appearance/appearance/resources/wallpaper/package.nix {
    inherit pkgs palette;
  };
  wallpaper = pkgs.writeShellApplication {
    name = "xorg-wallpaper";
    runtimeInputs = [ pkgs.feh ];
    text = ''
      exec ${pkgs.python3}/bin/python3 ${./resources/wallpaper.py} "$@" \
        --root ${lib.escapeShellArg "${config.home.homeDirectory}/Pictures/Wallpapers"} \
        --fallback ${wallpapers.directory} --default ${wallpapers.default}
    '';
  };
  idle = pkgs.writeShellApplication {
    name = "xorg-idle";
    text = ''
      [[ "''${XDG_CURRENT_DESKTOP:-}" == dwm ]] && \
        ${pkgs.systemd}/bin/systemctl --user is-active --quiet xorg-session.target || exit 1
      [[ "''${1:-}" == toggle && "$#" == 1 ]] || exit 2
      if ${pkgs.systemd}/bin/systemctl --user is-active --quiet xorg-idle.service; then
        ${pkgs.systemd}/bin/systemctl --user stop xorg-idle.service
        ${pkgs.libnotify}/bin/notify-send -a xorg-idle '防休眠已开启' '自动锁屏、熄屏与空闲休眠已暂停；合盖/系统休眠仍会锁屏'
      else
        ${pkgs.systemd}/bin/systemctl --user start xorg-idle.service
        ${pkgs.libnotify}/bin/notify-send -a xorg-idle '自动空闲策略已恢复' '15 分钟锁屏 · 30 分钟熄屏 · 60 分钟休眠'
      fi
    '';
  };
  outputs = pkgs.writeShellApplication {
    name = "xorg-outputs";
    runtimeInputs = [ pkgs.xrandr ];
    text = ''
      exec ${pkgs.python3}/bin/python3 ${./resources/outputs.py} \
        --x11 ${pkgs.libX11}/lib/libX11.so.6 --randr ${pkgs.libXrandr}/lib/libXrandr.so.2
    '';
  };
  display = pkgs.writeShellApplication {
    name = "xorg-display";
    text = ''
      [[ "$#" == 1 ]] || exit 2
      case "$1" in
        off) exec ${pkgs.xset}/bin/xset dpms force off ;;
        on) exec ${pkgs.xset}/bin/xset dpms force on ;;
        *) exit 2 ;;
      esac
    '';
  };
  screenshot = pkgs.writeShellApplication {
    name = "xorg-screenshot";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      usage() {
        echo "usage: xorg-screenshot screen|region|ocr-screen|ocr-region" >&2
        exit 2
      }

      [ "$#" -eq 1 ] || usage
      mode="$1"
      case "$mode" in
        screen|region|ocr-screen|ocr-region) ;;
        *) usage ;;
      esac

      image="$(mktemp --suffix=.png)"
      trap 'rm -f "$image"' EXIT

      if [[ "$mode" == *region ]]; then
        # slop exits nonzero when the user cancels; that is a normal no-op.
        if ! geometry="$(${lib.getExe pkgs.slop} -f '%x %y %w %h')"; then
          exit 0
        fi
        read -r x y width height extra <<< "$geometry"
        [ -n "''${x:-}" ] && [ -n "''${y:-}" ] \
          && [ -n "''${width:-}" ] && [ -n "''${height:-}" ] \
          && [ -z "''${extra:-}" ] || exit 1
        [[ "$x" =~ ^-?[0-9]+$ && "$y" =~ ^-?[0-9]+$ \
          && "$width" =~ ^[1-9][0-9]*$ && "$height" =~ ^[1-9][0-9]*$ ]] || exit 1
        case "$x" in -*) xoffset="$x" ;; *) xoffset="+$x" ;; esac
        case "$y" in -*) yoffset="$y" ;; *) yoffset="+$y" ;; esac
        ${lib.getExe pkgs.maim} -g "''${width}x''${height}''${xoffset}''${yoffset}" "$image"
      else
        ${lib.getExe pkgs.maim} "$image"
      fi

      if [[ "$mode" == region ]]; then
        # Match Mango's select → annotate → copy/save workflow using an X11
        # capture plus the GTK editor; mark-shot's capture surface is Wayland.
        mkdir -p "$HOME/Pictures/Screenshots"
        ${pkgs.satty}/bin/satty --filename "$image" \
          --copy-command ${lib.escapeShellArg "${pkgs.xclip}/bin/xclip -selection clipboard -t image/png -i"} \
          --output-filename "$HOME/Pictures/Screenshots/Screenshot-%Y%m%d-%H%M%S.png" \
          --actions-on-enter save-to-clipboard,exit
        exit 0
      fi
      if [[ "$mode" == ocr-* ]]; then
        export LC_ALL=C.UTF-8
        text="$(${
          pkgs.tesseract5.override {
            enableLanguages = [
              "eng"
              "chi_sim"
            ];
          }
        }/bin/tesseract "$image" - -l eng+chi_sim --psm 6 2>/dev/null)"
        if [[ -z "$text" ]]; then
          ${pkgs.libnotify}/bin/notify-send 'OCR' '没有识别到文字'
          exit 1
        fi
        printf '%s' "$text" | ${lib.getExe pkgs.xclip} -selection clipboard -in
        ${pkgs.libnotify}/bin/notify-send 'OCR 已复制' '识别结果已放入剪贴板'
        exit 0
      fi
      ${lib.getExe pkgs.xclip} -selection clipboard -t image/png -i "$image"
      ${pkgs.libnotify}/bin/notify-send "Screenshot copied" \
        "$([[ "$mode" == *region ]] && echo 'Selected region' || echo 'Full screen')" || true
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
        echo "usage: xorg-audio up|down|mute|mic-mute [step-percent]" >&2
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
        mic-mute)
          ${lib.getExe' pkgs.wireplumber "wpctl"} set-mute @DEFAULT_AUDIO_SOURCE@ toggle
          ${lib.getExe pkgs.libnotify} -a xorg-osd -h string:x-dunst-stack-tag:microphone '麦克风静音切换'
          exit 0
          ;;
        *) usage ;;
      esac

      status="$(${lib.getExe' pkgs.wireplumber "wpctl"} get-volume @DEFAULT_AUDIO_SINK@)"
      if [[ "$status" =~ ^Volume:\ ([0-9]+(\.[0-9]+)?)(\ \[MUTED\])?$ ]]; then
        percent="$(awk -v volume="''${BASH_REMATCH[1]}" 'BEGIN { printf "%d", volume * 100 + 0.5 }')"
        if [[ "$status" == *'[MUTED]'* ]]; then
          ${lib.getExe pkgs.libnotify} -a xorg-osd -h string:x-dunst-stack-tag:volume -h int:value:"$percent" -t 1400 "Audio muted" "$percent%"
        else
          ${lib.getExe pkgs.libnotify} -a xorg-osd -h string:x-dunst-stack-tag:volume -h int:value:"$percent" -t 1400 "Audio volume" "$percent%"
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
      ${lib.getExe pkgs.libnotify} -a xorg-osd -h string:x-dunst-stack-tag:brightness -h int:value:"$percent" -t 1400 "Brightness" "$percent%"
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
    wallpaper
    idle
    display
    outputs
    screenshot
    audio
    brightness
    media
  ];
}
