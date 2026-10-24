{
  pkgs,
  name,
  initial,
  palette,
}:
pkgs.runCommand "${name}-avatar.png"
  {
    nativeBuildInputs = [ pkgs.librsvg ];
    FONTCONFIG_FILE = pkgs.makeFontsConf { fontDirectories = [ pkgs.inter ]; };
  }
  ''
    cat > avatar.svg <<'SVG'
    <svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">
      <rect width="512" height="512" rx="112" fill="${palette.blue}"/>
      <text x="256" y="272" text-anchor="middle" dominant-baseline="central"
        fill="${palette.black}" font-family="${palette.fonts.sans}" font-size="328" font-weight="700">${initial}</text>
    </svg>
    SVG
    rsvg-convert --width 512 --height 512 --output "$out" avatar.svg
  ''
