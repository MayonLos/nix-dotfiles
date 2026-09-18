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
        # The installed family is spelled `JetBrainsMono Nerd Font`, no space.
        # The space here is harmless and was measured, not assumed: fontconfig
        # normalises whitespace in family matching, so `fc-list ":family=..."`
        # returns the same 7 faces either way. The calibration that makes that
        # conclusive is that an actually-unknown family falls back to
        # `Noto Sans CJK SC` (the sansSerif default), not to JetBrainsMono --
        # so the match above is a real one, not a fallback that happens to
        # land in the right place. Spelled the installed way regardless, so
        # nobody has to re-derive this.
        monospace = [ "JetBrainsMono Nerd Font" ];
        sansSerif = [ "Noto Sans CJK SC" ];
        serif = [ "Noto Serif CJK SC" ];
      };
    };
  };
}
