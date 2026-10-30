{
  pkgs,
  home,
  lib,
  ...
}:
let
  data = home.xdg.configFile."keys-mayon/bindings.json".source;
  mango = home.xdg.configFile."mango/config.conf".source;
in
{
  keys-mayon =
    assert lib.assertMsg (builtins.elem pkgs.mayonTui.tools.outPath (
      map (package: package.outPath) home.home.packages
    )) "keys-mayon must be installed by the selected feature";
    pkgs.mayonTui.tools;
  keys-mayon-bindings =
    pkgs.runCommand "keys-mayon-bindings-check"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        ${pkgs.mayonTui.tools}/bin/mayon-tools keys --data ${data} list --json > listed.json
        python3 ${../../../packages/mayon-tui/crates/keys/check_bindings.py} ${data} ${mango} listed.json
        mkdir "$out"
        cp ${data} "$out/bindings.json"
        cp listed.json "$out/listed.json"
      '';
}
