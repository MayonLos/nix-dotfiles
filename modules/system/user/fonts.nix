{ pkgs, ... }:
{
  fonts = {
    packages = with pkgs; [
      lmodern
      nerd-fonts.jetbrains-mono
      # nerd-icons (and doom-modeline through it) looks up "Symbols Nerd Font
      # Mono" by name rather than falling back to whatever Nerd Font is
      # installed, so the patched JetBrainsMono above does not satisfy it.
      nerd-fonts.symbols-only
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
