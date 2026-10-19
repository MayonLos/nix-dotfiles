{
  pkgs,
  lib ? pkgs.lib,
  palette,
  profileDirectory,
  x11Dpi ? 96,
}:

let
  inherit (pkgs) stdenv fetchFromGitHub python3;
  configure = pkgs.writeText "configure-dwm.py" (builtins.readFile ./configure.py);
  colors = {
    inherit (palette) bg;
    fg = palette.brightFg;
    inherit (palette) blue;
    inherit (palette) muted;
    inherit (palette) red;
    inherit (palette) deep;
  };
  src = fetchFromGitHub {
    owner = "bakkeby";
    repo = "dwm-flexipatch";
    rev = "4c963b33681b277a0ff4d3bf39a27b2feab68950";
    hash = "sha256-xYspDyPPBqTkO4SrB2+u1mUPTbWI52asXWjU0NFd2AU=";
  };
in
stdenv.mkDerivation {
  pname = "dwm-mayon";
  version = "6.8-flexipatch-4c963b3";
  inherit src;
  nativeBuildInputs = [
    python3
    pkgs.pkg-config
  ];
  buildInputs = with pkgs; [
    libX11
    libXinerama
    libXft
    libXrender
    freetype
    fontconfig
  ];
  postPatch = ''
    python ${configure} \
      --profile ${lib.escapeShellArg (toString profileDirectory)} \
      --dpi ${toString x11Dpi} \
      --bg ${lib.escapeShellArg colors.bg} \
      --fg ${lib.escapeShellArg colors.fg} \
      --blue ${lib.escapeShellArg colors.blue} \
      --muted ${lib.escapeShellArg colors.muted} \
      --red ${lib.escapeShellArg colors.red} \
      --deep ${lib.escapeShellArg colors.deep}
  '';
  preBuild = ''
    makeFlagsArray+=("PREFIX=$out" "CC=$CC")
  '';
  postInstall = ''
    install -D -m 0644 config.h "$out/share/dwm/config.h"
    install -D -m 0644 patches.h "$out/share/dwm/patches.h"
    cat > "$out/share/dwm/source-revision.txt" <<'EOF'
    Source: bakkeby/dwm-flexipatch
    Commit: 4c963b33681b277a0ff4d3bf39a27b2feab68950
    Baseline: dwm 6.8
    Reason: the required systray, vanitygaps and scratchpads patch combination does not apply cleanly to stable dwm 6.6.
    EOF
  '';
  meta = {
    description = "dwm 6.8 flexipatch with a focused Xorg configuration";
    homepage = "https://github.com/bakkeby/dwm-flexipatch/tree/4c963b33681b277a0ff4d3bf39a27b2feab68950";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "dwm";
  };
}
