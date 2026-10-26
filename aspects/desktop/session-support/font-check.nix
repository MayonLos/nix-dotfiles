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
  # Exercise the exact value NixOS writes to /etc/fonts/local.conf. Wrapping
  # this fragment here would hide a missing document root in localConf.
  aliases = pkgs.writeText "office-font-aliases.conf" nixos.fonts.fontconfig.localConf;
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
    OFFICE_FONT_ALIASES = aliases;
  }
  ''
    export HOME="$TMPDIR/home" XDG_CACHE_HOME="$TMPDIR/cache"
    mkdir -p "$HOME" "$XDG_CACHE_HOME" "$out"
    python3 - <<'PY' > "$out/matches.txt"
    import os
    import subprocess
    import xml.etree.ElementTree as ET

    root = ET.parse(os.environ["OFFICE_FONT_ALIASES"]).getroot()
    assert root.tag == "fontconfig", root.tag
    expected = {"Calibri": "Carlito", "Cambria": "Caladea", "Arial": "Liberation Sans", "Times New Roman": "Liberation Serif", "Courier New": "Liberation Mono", "SimSun": "Noto Serif CJK SC", "Microsoft YaHei": "Noto Sans CJK SC", "Source Han Sans SC": "Source Han Sans SC", "Source Han Serif SC": "Source Han Serif SC"}
    for requested, family in expected.items():
        result = subprocess.run(
            ["fc-match", "-f", "%{family}", requested],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )
        assert not result.stderr, (requested, result.stderr)
        actual = result.stdout
        assert family in actual.split(","), (requested, family, actual)
        print(f"{requested} -> {actual}")
    PY
  ''
