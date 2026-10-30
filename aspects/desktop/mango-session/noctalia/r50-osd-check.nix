{
  pkgs,
  noctalia,
  palette,
}:
let
  python = pkgs.python3.withPackages (p: [ p.pillow ]);
  paletteFile = pkgs.writeText "onedark-osd-palette.json" (builtins.toJSON palette);
  fontconfig = pkgs.makeFontsConf {
    fontDirectories = [ pkgs.inter ];
    impureFontDirectories = [ ];
  };
in
pkgs.runCommand "noctalia-osd-pixels"
  {
    nativeBuildInputs = [ python ];
  }
  ''
    mkdir -p "$out"
    python3 ${./r50-check-osd.py} \
      --noctalia ${noctalia}/bin/noctalia \
      --sway ${pkgs.sway-unwrapped}/bin/sway \
      --grim ${pkgs.grim}/bin/grim \
      --coreutils ${pkgs.coreutils}/bin \
      --dbus-run-session ${pkgs.dbus}/bin/dbus-run-session \
      --palette ${paletteFile} \
      --fontconfig ${fontconfig} \
      --egl-vendor ${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json \
      --out "$out"
  ''
