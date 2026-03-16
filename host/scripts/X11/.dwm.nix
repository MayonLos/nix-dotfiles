{
  config,
  pkgs,
  ...
}:

{
  home.file.".dwm/autostart.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash

      WALLPAPER_DIR="${config.home.homeDirectory}/nixos-dotfiles/home/wallpaper"
      WALLPAPER_INTERVAL_SEC=300

      change_wallpaper() {
        local next_wallpaper

        next_wallpaper="$(${pkgs.findutils}/bin/find "$WALLPAPER_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) | ${pkgs.coreutils}/bin/shuf -n 1)"
        [ -n "$next_wallpaper" ] || return 0

        ${pkgs.feh}/bin/feh --bg-fill "$next_wallpaper"
      }

      slstatus &
      change_wallpaper
      (
        while true; do
          ${pkgs.coreutils}/bin/sleep "$WALLPAPER_INTERVAL_SEC"
          change_wallpaper
        done
      ) &
      ${pkgs.picom}/bin/picom -b &
      ${pkgs.dunst}/bin/dunst &
      export GTK_IM_MODULE=fcitx
      export QT_IM_MODULE=fcitx
      export XMODIFIERS=@im=fcitx
      ${pkgs.qt6Packages.fcitx5-with-addons}/bin/fcitx5 &
    '';
  };
}
