{ pkgs }:
pkgs.runCommand "project-workbench-check"
  {
    nativeBuildInputs = [ pkgs.python3 ];
  }
  ''
    export PYTHONDONTWRITEBYTECODE=1
    ${pkgs.python3}/bin/python3 ${./.}/tests.py -v
    touch "$out"
  ''
