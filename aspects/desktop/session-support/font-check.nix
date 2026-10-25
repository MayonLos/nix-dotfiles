{ pkgs, nixos, ... }:
let
  fonts = with pkgs; [
    carlito
    caladea
    liberation_ttf
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    source-han-sans
    source-han-serif
  ];
  aliases = pkgs.writeText "office-font-aliases.conf" ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>${nixos.fonts.fontconfig.localConf}</fontconfig>
  '';
  fontconfig = pkgs.makeFontsConf {
    fontDirectories = fonts;
    impureFontDirectories = [ ];
    includes = [ aliases ];
  };
in
assert builtins.all (font: builtins.elem font nixos.fonts.packages) fonts;
pkgs.runCommand "office-fonts-check"
  {
    nativeBuildInputs = [
      pkgs.fontconfig
      pkgs.python3
    ];
    FONTCONFIG_FILE = fontconfig;
  }
  ''
    export HOME="$TMPDIR/home" XDG_CACHE_HOME="$TMPDIR/cache"
    mkdir -p "$HOME" "$XDG_CACHE_HOME" "$out"
    python3 - <<'PY' > "$out/matches.txt"
    import subprocess
    expected = {"Calibri": "Carlito", "Cambria": "Caladea", "Arial": "Liberation Sans", "Times New Roman": "Liberation Serif", "Courier New": "Liberation Mono", "SimSun": "Noto Serif CJK SC", "Microsoft YaHei": "Noto Sans CJK SC", "Source Han Sans SC": "Source Han Sans SC", "Source Han Serif SC": "Source Han Serif SC"}
    for requested, family in expected.items():
        actual = subprocess.check_output(["fc-match", "-f", "%{family}", requested], text=True)
        assert family in actual.split(","), (requested, family, actual)
        print(f"{requested} -> {actual}")
    PY
  ''
