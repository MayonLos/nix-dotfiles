{
  config,
  pkgs,
  niri,
  ...
}:
let
  dotfiles = "${config.home.homeDirectory}/nixos-dotfiles/home/dwm/config";
  create_symlink = path: config.lib.file.mkOutOfStoreSymlink path;

  configs = {
    picom = "picom";
    dunst = "dunst";
  };
in
{
  imports = [
    niri.homeModules.niri
    ../home/dwm/suckless.nix
    ../home/niri/default.nix
    ../home/service/default.nix
    ../home/program/default.nix
    ../home/shell/default.nix
    ./packages.nix
    ./scripts/X11/default.nix
  ];

  home.username = "mayon";
  home.homeDirectory = "/home/mayon";
  home.stateVersion = "25.11";

  

  home.sessionVariables = {
    XMODIFIERS = "@im=fcitx";
  };

  i18n.inputMethod = {
    type = "fcitx5";
    enable = true;
    fcitx5.waylandFrontend = true;
    fcitx5.addons = with pkgs; [
      fcitx5-gtk
      libsForQt5.fcitx5-qt
      qt6Packages.fcitx5-chinese-addons
    ];
  };

  home.pointerCursor = {
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Ice";
    size = 16;
    x11.defaultCursor = "Bibata-Modern-Ice";
    gtk.enable = true;
    x11.enable = true;
  };

  xdg.configFile = builtins.mapAttrs (name: subpath: {
    source = create_symlink "${dotfiles}/${subpath}";
    recursive = true;
  }) configs;

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "inode/directory" = [ "thunar.desktop" ];
      "text/plain" = [ "code.desktop" ];
      "text/markdown" = [ "code.desktop" ];
      "application/x-shellscript" = [ "code.desktop" ];
      "video/mp4" = [ "mpv.desktop" ];
      "video/x-matroska" = [ "mpv.desktop" ];
      "video/webm" = [ "mpv.desktop" ];
      "video/quicktime" = [ "mpv.desktop" ];
      "text/html" = [ "firefox.desktop" ];
      "x-scheme-handler/http" = [ "firefox.desktop" ];
      "x-scheme-handler/https" = [ "firefox.desktop" ];
      "x-scheme-handler/about" = [ "firefox.desktop" ];
      "x-scheme-handler/unknown" = [ "firefox.desktop" ];
      "x-scheme-handler/terminal" = [ "kitty.desktop" ];
    };
  };
  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
  };
  dconf.settings = {
  "org/gnome/desktop/interface" = {
    color-scheme = "prefer-dark";
  };
};
}
