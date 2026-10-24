{ pkgs, package }:

pkgs.runCommand "noctalia-onedark-assets" { } ''
  mkdir -p "$out"
  cp -a ${package}/share/noctalia/assets/. "$out/"
  chmod -R u+w "$out"
  install -m 0444 ${./resources/gtk/gtk3.css} "$out/templates/gtk/gtk3.css"
  install -m 0444 ${./resources/gtk/gtk4.css} "$out/templates/gtk/gtk4.css"
  install -m 0444 ${./resources/qt/qtct.conf} "$out/templates/qt/qtct.conf"
''
