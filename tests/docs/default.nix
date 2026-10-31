{ pkgs, source }:
pkgs.runCommand "docs-check" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 ${./check.py} ${source}
  touch $out
''
