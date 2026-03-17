{
  pkgs,
  ...
}:

{
  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    lshw
    btop
  ];

  fonts = {
    packages = with pkgs; [
      lmodern
      nerd-fonts.jetbrains-mono
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      noto-fonts-color-emoji
      wqy_zenhei
    ];
    fontconfig = {
      antialias = true;
      hinting.enable = true;
      defaultFonts = {
        emoji = [ "Noto Color Emoji" ];
        monospace = [ "JetBrains Mono Nerd Font" ];
        sansSerif = [ "Noto Sans CJK SC" ];
        serif = [ "Noto Serif CJK SC" ];
      };
    };
  };
}
