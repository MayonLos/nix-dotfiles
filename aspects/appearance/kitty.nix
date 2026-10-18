{ palette }:
{ lib, ... }:
lib.optionalAttrs (palette != null) {
  programs.kitty.settings = {
    background = palette.bg;
    foreground = palette.fg;
    cursor = palette.blue;
    selection_background = palette.selection;
    selection_foreground = palette.fg;
  }
  // lib.listToAttrs (
    lib.imap0 (i: value: lib.nameValuePair "color${toString i}" value) (import ./ansi.nix palette)
  );
}
