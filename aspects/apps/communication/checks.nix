{ pkgs, home, ... }:
let
  thunderbird = home.programs.thunderbird.package;
in
{
  communication-portal-config = pkgs.runCommand "communication-portal-config-check" { } ''
    grep -Fq 'widget.use-xdg-desktop-portal.file-picker", 1' \
      ${thunderbird}/lib/thunderbird/mozilla.cfg
    touch "$out"
  '';
}
