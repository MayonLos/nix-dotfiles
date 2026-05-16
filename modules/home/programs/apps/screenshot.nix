{ pkgs, ... }:

let
  # Unified screenshot script for all compositors.
  # Usage: screenshot <mode>
  #
  #   region    — select region → satty annotate → save + clipboard  (default)
  #   fullscreen — full display → save to file
  #   window    — focused window: uses mmsg under MangoWM, falls back to fullscreen elsewhere
  #   pin       — select region → floating swayimg overlay (stays on screen)
  #   annotate  — full display → satty annotate
  #
  # All paths are Nix store paths so the script is self-contained and
  # works regardless of the user's PATH.
  screenshot = pkgs.writeShellScriptBin "screenshot" ''
    set -euo pipefail

    GRIM="${pkgs.grim}/bin/grim"
    SLURP="${pkgs.slurp}/bin/slurp"
    SATTY="${pkgs.satty}/bin/satty"
    WL_COPY="${pkgs.wl-clipboard}/bin/wl-copy"
    SWAYIMG="${pkgs.swayimg}/bin/swayimg"
    DATE="${pkgs.coreutils}/bin/date"
    MKDIR="${pkgs.coreutils}/bin/mkdir"

    SHOTS_DIR="$HOME/Pictures/Screenshots"
    "$MKDIR" -p "$SHOTS_DIR"
    FILEPATH="$SHOTS_DIR/$("$DATE" +%Y%m%d-%H%M%S).png"
    WM="''${XDG_CURRENT_DESKTOP:-}"

    case "''${1:-region}" in

      region)
        # Interactive region selection → satty annotation → save + clipboard
        g=$("$SLURP" -d) || exit 0
        "$GRIM" -g "$g" - \
          | "$SATTY" \
              --filename - \
              --output-filename "$FILEPATH" \
              --copy-command "$WL_COPY" \
              --early-exit
        ;;

      fullscreen)
        "$GRIM" "$FILEPATH"
        ;;

      window)
        # Focused window capture — compositor-aware.
        # MangoWM: mmsg ships with mango and exposes focused-window geometry.
        # Other compositors: falls back to a full-screen capture.
        case "$WM" in
          mango|Mango)
            g=$(mmsg -x \
              | awk '/x /    {x=$3}
                     /y /    {y=$3}
                     /width / {w=$3}
                     /height /{h=$3}
                     END      {print x","y" "w"x"h}')
            [ -z "$g" ] && exit 1
            "$GRIM" -g "$g" "$FILEPATH"
            ;;
          *)
            "$GRIM" "$FILEPATH"
            ;;
        esac
        ;;

      pin)
        # Select region → copy to clipboard + open as floating swayimg overlay
        PIN_DIR="/tmp/screenshot-pins"
        "$MKDIR" -p "$PIN_DIR"
        FILE="$PIN_DIR/pin-$("$DATE" +%Y%m%d-%H%M%S).png"
        g=$("$SLURP" -d) || exit 0
        "$GRIM" -g "$g" "$FILE"
        "$WL_COPY" < "$FILE"
        "$SWAYIMG" \
          --size=image \
          --config info.show=no \
          --config viewer.window="#00000000" \
          --config general.decoration=no \
          "$FILE"
        ;;

      annotate)
        # Full display capture → open in satty for annotation
        "$GRIM" "$FILEPATH"
        "$SATTY" \
          --filename "$FILEPATH" \
          --output-filename "$FILEPATH" \
          --copy-command "$WL_COPY" \
          --early-exit
        ;;

    esac
  '';
in
{
  home.packages = [ screenshot ];
}
