{ pkgs }:
let
  python = pkgs.python3.withPackages (p: [ p.pypinyin ]);
in
pkgs.runCommand "noctalia-plugins" { nativeBuildInputs = [ python ]; } ''
  cp -r ${../resources/noctalia-plugins} "$out"
  chmod -R u+w "$out"
  python3 ${../resources/generate-launchpad-pinyin.py} "$out/launchpad/pinyin-data.luau"
''
