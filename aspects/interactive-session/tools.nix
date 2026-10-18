{ pkgs, ... }: {
  home.packages = with pkgs; [
    qt6Packages.qt6ct
    wl-clipboard
    xclip
    grim
    slurp
    brightnessctl
    ddcutil
    playerctl
    libdecor
  ];
}
