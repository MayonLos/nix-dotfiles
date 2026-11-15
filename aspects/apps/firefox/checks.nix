{ pkgs, home, ... }:
let
  python = pkgs.python3.withPackages (pythonPackages: [ pythonPackages.tinycss2 ]);
  activation = pkgs.writeText "firefox-ui-seed-activation" home.home.activation.seedFirefoxProfileUi.data;
in
{
  # The browser chrome stylesheet is rendered at build time from the declared
  # palette and seeded into the profile by activation. This check exercises the
  # real seed script against a temporary profile and parses the seeded CSS.
  firefox-ui = pkgs.runCommand "firefox-ui-check" { nativeBuildInputs = [ python ]; } ''
    fallback_css="$(python3 - ${activation} <<'PY'
    import shlex
    import sys
    from pathlib import Path
    activation = Path(sys.argv[1]).read_text(encoding="utf-8")
    for line in reversed(activation.splitlines()):
        try:
            words = shlex.split(line)
        except ValueError:
            continue
        for index, word in enumerate(words[:-1]):
            if Path(word).name == "seed-firefox-ui.py":
                print(words[index + 1].rstrip(";"))
                raise SystemExit(0)
    raise SystemExit("seed-firefox-ui.py invocation not found in Home Manager activation")
    PY
    )"
    test -f "$fallback_css"
    python3 ${./resources}/test_firefox_ui.py "$fallback_css"
    touch "$out"
  '';
}
