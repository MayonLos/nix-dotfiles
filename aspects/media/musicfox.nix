{ pkgs, ... }:
{
  home.packages = [ pkgs.go-musicfox ];

  xdg.desktopEntries.musicfox = {
    name = "Musicfox";
    genericName = "网易云音乐";
    icon = "multimedia-player";
    exec = "${pkgs.kitty}/bin/kitty --class musicfox --title Musicfox ${pkgs.go-musicfox}/bin/musicfox";
    terminal = false;
    categories = [
      "Audio"
      "Music"
      "Player"
    ];
  };
}
