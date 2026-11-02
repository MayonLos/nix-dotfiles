# Renders the shared appearance palette as C++ constants for src/view.cpp.
palette:
let
  entry = name: value: "constexpr uint32_t k${name} = 0x${builtins.substring 1 6 value};\n";
in
"// Generated from aspects/appearance/appearance/onedark.nix; do not edit.\n"
+ entry "Bg" palette.bg
+ entry "Surface" palette.surface
+ entry "Selection" palette.selection
+ entry "Border" palette.border
+ entry "Fg" palette.fg
+ entry "BrightFg" palette.brightFg
+ entry "Muted" palette.muted
+ entry "Blue" palette.blue
+ entry "Green" palette.green
+ entry "Yellow" palette.yellow
+ entry "Red" palette.red
