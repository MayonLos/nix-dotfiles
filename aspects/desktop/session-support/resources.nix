{
  pkgs,
  package,
  palette,
}:
let
  fontTemplate =
    path:
    pkgs.writeText (baseNameOf path) (
      pkgs.lib.replaceStrings
        [ "@fontSans@" "@fontMono@" ]
        [ (builtins.toJSON palette.fonts.sans) (builtins.toJSON palette.fonts.mono) ]
        (builtins.readFile path)
    );
in

pkgs.runCommand "noctalia-onedark-assets" { } ''
  mkdir -p "$out"
  cp -a ${package}/share/noctalia/assets/. "$out/"
  chmod -R u+w "$out"
  install -m 0444 ${fontTemplate ./resources/gtk/gtk3.css} "$out/templates/gtk/gtk3.css"
  install -m 0444 ${fontTemplate ./resources/gtk/gtk4.css} "$out/templates/gtk/gtk4.css"
  install -m 0444 ${./resources/qt/qtct.conf} "$out/templates/qt/qtct.conf"
''
