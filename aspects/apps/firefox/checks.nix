{ pkgs, home, ... }:
let
  python = pkgs.python3.withPackages (pythonPackages: [ pythonPackages.tinycss2 ]);
  activation = pkgs.writeText "firefox-ui-seed-activation" home.home.activation.seedFirefoxProfileUi.data;
in
{
  firefox-ui =
    pkgs.runCommand "firefox-ui-check"
      {
        nativeBuildInputs = [ python ];
      }
      ''
        fallback_css="$(${python}/bin/python3 - ${activation} <<'PY'
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
        ${python}/bin/python3 ${./resources}/test_firefox_ui.py "$fallback_css"
        touch "$out"
      '';
}
