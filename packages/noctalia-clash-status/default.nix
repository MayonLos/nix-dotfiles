{ pkgs }:
(pkgs.writeScriptBin "noctalia-clash-status" ''
  #!${pkgs.python3}/bin/python3
  ${builtins.readFile ./status.py}
'').overrideAttrs
  (_: {
    passthru.tests.status = pkgs.runCommand "noctalia-clash-status-check" { } ''
      export TMPDIR="$PWD/tmp" PYTHONPATH=${./.}
      mkdir -p "$TMPDIR"
      ${pkgs.python3}/bin/python3 ${./test_status.py}
      touch "$out"
    '';
  })
