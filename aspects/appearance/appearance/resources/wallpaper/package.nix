# Public factory for the retained cool-toned wallpaper set; see ../../README.md.
{ pkgs, ... }:
let
  wallpapers =
    map
      (id: {
        name = "wallpaper-${id}.png";
        path = ./. + "/wallpaper-${id}.png";
      })
      [
        "002"
        "005"
        "008"
        "009"
        "011"
      ];
in
{
  inherit wallpapers;
  # Restored on 2026-10-25 at the user's request.
  default = "${./wallpaper-005.png}";
  directory = pkgs.linkFarm "astra-cool-wallpapers" wallpapers;
}
