{ palette }:
{ pkgs, ... }:
{
  fonts = {
    packages = with pkgs; [
      nerd-fonts.jetbrains-mono
      # Keep the separately named Symbols Nerd Font Mono available for icon
      # fallback as well as the patched monospace family.
      nerd-fonts.symbols-only
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      noto-fonts-color-emoji
    ];
    fontconfig = {
      antialias = true;
      hinting.enable = true;
      defaultFonts = {
        emoji = [ "Noto Color Emoji" ];
        monospace = [ palette.fonts.mono ];
        sansSerif = [ palette.fonts.sans ];
        serif = [ palette.fonts.serif ];
      };
    };
  };
}
