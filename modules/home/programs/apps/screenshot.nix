{ pkgs, ... }:

let
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
    FILENAME="$("$DATE" +%Y%m%d-%H%M%S).png"
    FILEPATH="$SHOTS_DIR/$FILENAME"

    g=$("$SLURP" -d) || exit 0
    "$GRIM" -g "$g" - \
      | "$SATTY" \
          --filename - \
          --output-filename "$FILEPATH" \
          --copy-command "$WL_COPY" \
          --early-exit
  '';
in
{
  home.packages = [ screenshot ];
}
