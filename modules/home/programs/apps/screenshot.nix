{ pkgs, ... }:

let
  # Screenshot script for niri.
  # Usage: screenshot <mode>
  #
  #   region      — select region → satty annotate → save + clipboard  (default)
  #   fullscreen  — full display → save + clipboard
  screenshot = pkgs.writeShellScriptBin "screenshot" ''
    set -euo pipefail

    GRIM="${pkgs.grim}/bin/grim"
    SLURP="${pkgs.slurp}/bin/slurp"
    SATTY="${pkgs.satty}/bin/satty"
    WL_COPY="${pkgs.wl-clipboard}/bin/wl-copy"
    DATE="${pkgs.coreutils}/bin/date"
    MKDIR="${pkgs.coreutils}/bin/mkdir"

    SHOTS_DIR="$HOME/Pictures/Screenshots"
    "$MKDIR" -p "$SHOTS_DIR"
    FILEPATH="$SHOTS_DIR/$("$DATE" +%Y%m%d-%H%M%S).png"

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
        # Full display → save + copy to clipboard
        "$GRIM" "$FILEPATH"
        "$WL_COPY" < "$FILEPATH"
        ;;

    esac
  '';
in
{
  home.packages = [ screenshot ];
}
