# Public factory for the original wallpaper set; see ./CREDITS.md.
{ pkgs, ... }:
let
  # The 18 images from the first wallpaper commit (553d8b1), restored on
  # 2026-10-29 at the user's request. Two are JPEG, the rest PNG.
  files = [
    "wallpaper-001.jpg"
    "wallpaper-002.jpg"
  ]
  ++ map (n: "wallpaper-${n}.png") [
    "003"
    "004"
    "005"
    "006"
    "007"
    "008"
    "009"
    "010"
    "011"
    "012"
    "013"
    "014"
    "015"
    "016"
    "017"
    "018"
  ];
  wallpapers = map (name: {
    inherit name;
    path = ./. + "/${name}";
  }) files;
in
{
  inherit wallpapers;
  default = "${./wallpaper-005.png}";
  directory = pkgs.linkFarm "original-wallpapers" wallpapers;
}
