{ pkgs, ... }:

let
  screenshot-region = pkgs.writeShellScriptBin "screenshot-region" ''
    set -euo pipefail

    SLURP="${pkgs.slurp}/bin/slurp"
    GRIM="${pkgs.grim}/bin/grim"
    SATTY="${pkgs.satty}/bin/satty"
    WL_COPY="${pkgs.wl-clipboard}/bin/wl-copy"
    DATE="${pkgs.coreutils}/bin/date"
    MKDIR="${pkgs.coreutils}/bin/mkdir"

    SCREENSHOTS_DIR="$HOME/Pictures/Screenshots"
    "$MKDIR" -p "$SCREENSHOTS_DIR"

    TIMESTAMP=$("$DATE" "+%Y%m%d-%H%M%S")
    FILENAME="$SCREENSHOTS_DIR/screenshot-$TIMESTAMP.png"

    GEOMETRY=$("$SLURP" -d) || exit 0
    "$GRIM" -g "$GEOMETRY" - |
      "$SATTY" --filename - \
        --output-filename "$FILENAME" \
        --copy-command "$WL_COPY" \
        --early-exit
  '';

  screenshot-pin = pkgs.writeShellScriptBin "screenshot-pin" ''
    set -euo pipefail

    SLURP="${pkgs.slurp}/bin/slurp"
    GRIM="${pkgs.grim}/bin/grim"
    SATTY="${pkgs.satty}/bin/satty"
    WL_COPY="${pkgs.wl-clipboard}/bin/wl-copy"
    SWAYIMG="${pkgs.swayimg}/bin/swayimg"
    DATE="${pkgs.coreutils}/bin/date"
    MKDIR="${pkgs.coreutils}/bin/mkdir"

    PIN_DIR="/tmp/niri-pins"
    "$MKDIR" -p "$PIN_DIR"

    TIMESTAMP=$("$DATE" "+%Y%m%d-%H%M%S")
    FILE="$PIN_DIR/pin-$TIMESTAMP.png"

    GEOMETRY=$("$SLURP" -d) || exit 0
    "$GRIM" -g "$GEOMETRY" - |
      "$SATTY" --filename - \
        --output-filename "$FILE" \
        --copy-command "$WL_COPY" \
        --early-exit

    if [ -f "$FILE" ]; then
      "$SWAYIMG" "$FILE"
    fi
  '';
in
{
  home.packages = [ screenshot-region screenshot-pin ];
}
