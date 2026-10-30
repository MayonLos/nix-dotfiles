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
      # Generic serif, which reading views resolve to. SimSun stays Noto below.
      lxgw-wenkai-screen
      # Metric-compatible Office fallbacks, shared by both office suites.
      carlito
      caladea
      liberation_ttf
    ];
    fontconfig = {
      antialias = true;
      hinting.enable = true;
      localConf = ''
        <fontconfig>
          <alias binding="same"><family>Calibri</family><prefer><family>Carlito</family></prefer></alias>
          <alias binding="same"><family>Cambria</family><prefer><family>Caladea</family></prefer></alias>
          <alias binding="same"><family>Arial</family><prefer><family>Liberation Sans</family></prefer></alias>
          <alias binding="same"><family>Times New Roman</family><prefer><family>Liberation Serif</family></prefer></alias>
          <alias binding="same"><family>Courier New</family><prefer><family>Liberation Mono</family></prefer></alias>
          <alias binding="same"><family>SimSun</family><prefer><family>Noto Serif CJK SC</family></prefer></alias>
          <alias binding="same"><family>Source Han Sans SC</family><prefer><family>Noto Sans CJK SC</family></prefer></alias>
          <alias binding="same"><family>Source Han Serif SC</family><prefer><family>Noto Serif CJK SC</family></prefer></alias>
          <alias binding="same"><family>Microsoft YaHei</family><prefer><family>Noto Sans CJK SC</family></prefer></alias>
        </fontconfig>
      '';
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
