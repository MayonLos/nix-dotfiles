{ pkgs, home, ... }:
let
  python = pkgs.python3.withPackages (pythonPackages: [ pythonPackages.tinycss2 ]);
  activation = pkgs.writeText "firefox-ui-seed-activation" home.home.activation.seedFirefoxProfileUi.data;
  customColors = (pkgs.formats.toml { }).generate "firefox-custom-colors.toml" {
    config.custom_colors = home.programs.noctalia.settings.theme.templates.custom_colors;
  };
  theme = pkgs.writeText "firefox-theme.json" (
    builtins.toJSON {
      dark = home.programs.noctalia.customPalettes.onedark.dark;
    }
  );
in
{
  firefox-ui = pkgs.runCommand "firefox-ui-check" { nativeBuildInputs = [ python ]; } ''
    fallback_css="$(python3 - ${activation} <<'PY'
    import shlex
    import sys
    from pathlib import Path
    activation = Path(sys.argv[1]).read_text(encoding="utf-8")
    candidates = []
    for line in activation.splitlines():
        try:
            words = shlex.split(line)
        except ValueError:
            continue
        for index, word in enumerate(words[:-1]):
            if Path(word).name == "seed-firefox-ui.py":
                candidates.append(words[index + 1].rstrip(";"))
    if not candidates:
        raise SystemExit("seed-firefox-ui.py invocation not found in Home Manager activation")
    fallback = Path(candidates[-1])
    if not fallback.is_file():
        raise SystemExit(f"Firefox fallback CSS from activation is missing: {fallback}")
    print(fallback)
    PY
    )"
    python3 ${./resources}/test_firefox_ui.py "$fallback_css"
    # Render with the runtime engine: _value is exact; the unsuffixed role
    # becomes a Material tonal derivative even when blend is false.
    export HOME="$TMPDIR/home" XDG_CONFIG_HOME="$TMPDIR/config"
    mkdir -p "$HOME" "$XDG_CONFIG_HOME"
    unset DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS
    ${pkgs.lib.getExe home.programs.noctalia.package} theme --theme-json ${theme} --config ${customColors} \
      --render "${./resources/noctalia-userChrome.css}:$TMPDIR/rendered.css" > "$TMPDIR/render.log" 2>&1
    python3 - "$fallback_css" "$TMPDIR/rendered.css" <<'PY'
    from pathlib import Path
    import sys
    assert Path(sys.argv[1]).read_text().strip() == Path(sys.argv[2]).read_text().strip(), "runtime Firefox colors differ from its seed"
    PY
    touch "$out"
  '';
}
