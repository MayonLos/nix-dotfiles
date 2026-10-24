{ palette }:
{ lib, pkgs, ... }:
{
  # The host appearance owns TTY colors; hardware boot policy stays independent.
  console.colors = map (lib.removePrefix "#") (
    import ../../../appearance/appearance/ansi.nix palette
  );

  fonts = {
    packages = with pkgs; [
      maple-mono.NF-CN
      inter
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
        sansSerif = [
          palette.fonts.sans
          palette.fonts.cjk
        ];
        serif = [ palette.fonts.serif ];
      };
    };
  };
}
