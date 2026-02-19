{
  config,
  ...
}:

{
    home.file.".dwm/autostart.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      slstatus &
      feh --bg-scale ${config.home.homeDirectory}/nixos-dotfiles/home/wallpaper/wallpaper.jpg &
      picom -b &
      dunst &
      fcitx5 &
      greenclip daemon &
    '';
  };
}