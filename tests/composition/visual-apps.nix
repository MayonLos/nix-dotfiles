{
  pkgs,
  home,
  appearance,
  ...
}:
let
  python = pkgs.python3.withPackages (p: [ p.tinycss2 ]);
  palette = pkgs.writeText "visual-apps-palette.json" (builtins.toJSON appearance);
  mpv = home.programs.mpv.finalPackage;
in
pkgs.runCommand "visual-apps-config"
  {
    nativeBuildInputs = [
      python
      pkgs.lua
    ];
  }
  ''
    export HOME="$TMPDIR/home" XDG_CONFIG_HOME="$TMPDIR/config" XDG_DATA_HOME="$TMPDIR/data"
    mkdir -p "$HOME" "$XDG_CONFIG_HOME/mpv/script-opts" "$XDG_DATA_HOME" "$out"
    cp ${home.xdg.configFile."mpv/mpv.conf".source} "$XDG_CONFIG_HOME/mpv/mpv.conf"
    cp ${
      home.xdg.configFile."mpv/script-opts/uosc.conf".source
    } "$XDG_CONFIG_HOME/mpv/script-opts/uosc.conf"
    ${mpv}/bin/mpv --config-dir="$XDG_CONFIG_HOME/mpv" --scripts= --load-scripts=no --vo=null --ao=null --frames=1 "av://lavfi:color=s=16x16:d=0.1" \
      > "$out/mpv-parser.log" 2>&1
    if grep -iE 'error parsing|invalid value|option.*not found|error setting option' "$out/mpv-parser.log"; then exit 1; fi
    python3 - ${palette} ${
      home.xdg.configFile."swayimg/config".source
    } "$XDG_CONFIG_HOME/mpv/script-opts/uosc.conf" "$out" <<'PY'
    import configparser, json, pathlib, sys
    p = json.loads(pathlib.Path(sys.argv[1]).read_text())
    sway = configparser.ConfigParser()
    sway.read(sys.argv[2])
    assert sway['gallery']['select'] == p['selection'] + 'ff'
    assert sway['gallery']['border_color'] == p['blue'] + 'ff'
    assert sway['font']['background'] == p['deep'] + 'ff'
    assert sway['font']['color'] == p['brightFg'] + 'ff'
    opts = dict(line.split('=', 1) for line in pathlib.Path(sys.argv[3]).read_text().splitlines() if '=' in line)
    colors = dict(pair.split('=') for pair in opts['color'].split(','))
    assert colors['selection'] == p['selection'][1:]
    assert colors['foreground'] == p['brightFg'][1:]
    assert colors['foreground_text'] == p['deep'][1:]
    assert colors['match'] == p['blue'][1:]
    def luminance(value):
        rgb = [int(value[i:i+2], 16) / 255 for i in (1, 3, 5)]
        linear = [c/12.92 if c <= .04045 else ((c+.055)/1.055)**2.4 for c in rgb]
        return sum(c*w for c,w in zip(linear, (.2126, .7152, .0722)))
    def contrast(fg, bg):
        a, b = sorted((luminance(p[fg]), luminance(p[bg])))
        return (b+.05)/(a+.05)
    pairs = [(fg, bg) for fg in ('brightFg', 'fg', 'blue') for bg in ('bg', 'deep', 'surface', 'selection')]
    report = {f'{fg}/{bg}': round(contrast(fg,bg), 3) for fg,bg in pairs}
    assert min(report.values()) >= 4.5
    # Firefox 158's shadow placeholder has a fixed native .54 opacity.
    composite = []
    for i in (1, 3, 5):
        composite.append(round(int(p['brightFg'][i:i+2], 16) * .54 + int(p['surface'][i:i+2], 16) * .46))
    p['firefoxPlaceholder'] = '#' + "".join(f'{c:02x}' for c in composite)
    report['nativeFirefoxPlaceholder/surface'] = round(contrast('firefoxPlaceholder', 'surface'), 3)
    pathlib.Path(sys.argv[4], 'contrast.json').write_text(json.dumps(report, indent=2) + '\n')
    PY
    # Compile the actual selected Lua files, including the bounded theme adaptation.
    ${pkgs.lib.concatMapStringsSep "\n" (
      script:
      pkgs.lib.optionalString (script.pname == "uosc") ''
        find ${script}/share/mpv/scripts/uosc -name '*.lua' -print0 | xargs -0 -n1 luac -p
      ''
    ) home.programs.mpv.scripts}
  ''
