{ palette }:
{ pkgs, lib, ... }:
let
  roles = [
    "bg"
    "deep"
    "surface"
    "selection"
    "brightFg"
    "fg"
    "muted"
    "border"
    "blue"
  ];
  chrome = pkgs.writeText "thunderbird-userChrome.css" (
    builtins.replaceStrings (map (role: "@${role}@") roles) (map (role: palette.${role}) roles) (
      builtins.readFile ./resources/thunderbird-userChrome.css
    )
  );
in
# Accounts and credentials are configured interactively, not in the Nix store.
{
  programs.thunderbird = {
    enable = true;
    # wrapThunderbird supports autoconfig without claiming any user profile.
    package = pkgs.thunderbird.override {
      extraPrefs = ''
        lockPref("widget.use-xdg-desktop-portal.file-picker", 1);
      '';
    };
  };
  home.activation.seedThunderbirdUi = lib.mkIf (palette != null) (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${pkgs.python3}/bin/python3 ${./resources}/seed-thunderbird-ui.py ${chrome}
    ''
  );
}
