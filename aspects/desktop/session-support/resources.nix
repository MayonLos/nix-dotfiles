{
  pkgs,
  package,
  palette,
}:
let
  # Builtin engines do not receive theme.templates.custom_colors (Noctalia
  # 5.3 TemplateApplyService). Freeze the shared palette here, while keeping
  # Noctalia's builtin file writer, GTK import hooks and undo lifecycle.
  colorNames = [
    "bg"
    "deep"
    "surface"
    "selection"
    "bright_fg"
    "fg"
    "muted"
    "border"
    "blue"
    "black"
    "red"
    "purple"
  ];
  colorValues = [
    palette.bg
    palette.deep
    palette.surface
    palette.selection
    palette.brightFg
    palette.fg
    palette.muted
    palette.border
    palette.blue
    palette.black
    palette.red
    palette.purple
  ];
  paletteTemplate =
    path:
    pkgs.writeText (baseNameOf path) (
      pkgs.lib.replaceStrings
        (
          [
            "@fontSans@"
            "@fontMono@"
          ]
          ++ map (name: "{{ colors.onedark_${name}_value.default.hex }}") colorNames
        )
        (
          [
            (builtins.toJSON palette.fonts.sans)
            (builtins.toJSON palette.fonts.mono)
          ]
          ++ colorValues
        )
        (builtins.readFile path)
    );
in

pkgs.runCommand "noctalia-onedark-assets" { } ''
  mkdir -p "$out"
  cp -a ${package}/share/noctalia/assets/. "$out/"
  chmod -R u+w "$out"
  install -m 0444 ${paletteTemplate ./resources/gtk/gtk3.css} "$out/templates/gtk/gtk3.css"
  install -m 0444 ${paletteTemplate ./resources/gtk/gtk4.css} "$out/templates/gtk/gtk4.css"
  install -m 0444 ${paletteTemplate ./resources/qt/qtct.conf} "$out/templates/qt/qtct.conf"
''
