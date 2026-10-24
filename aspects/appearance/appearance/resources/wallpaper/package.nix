# Public palette-parameterized wallpaper factory; see ../../README.md.
{ pkgs, palette }:
let
  colors = pkgs.writeText "astra-wallpaper-palette.json" (builtins.toJSON palette);
  python = pkgs.python3.withPackages (p: [
    p.pillow
    p.numpy
  ]);
  generated =
    pkgs.runCommand "astra-wallpapers-2560x1600"
      {
        nativeBuildInputs = [
          python
          pkgs.librsvg
          pkgs.imagemagick
        ];
      }
      ''
        python3 ${./render.py} ${colors} "$out"
        for image in "$out"/*.png; do
          test "$(magick identify -format '%wx%h' "$image")" = 2560x1600
        done
      '';
  photo = name: id: hash: {
    inherit name;
    path = pkgs.fetchurl {
      inherit name hash;
      url = "https://images.unsplash.com/photo-${id}?fit=crop&crop=${
        if name == "15-mountain-night.jpg" then "bottom" else "entropy"
      }&w=2560&h=1600&q=90&fm=jpg";
    };
  };
  wallpapers =
    map
      (name: {
        inherit name;
        path = "${generated}/${name}";
      })
      [
        "01-quiet-bay.png"
        "02-strata.png"
        "03-orbit.png"
        "04-night-paper.png"
      ]
    ++ [
      (photo "13-blue-city.jpg" "1760421131154-f884a2e26b7e"
        "sha256-m5W1GA2MfrxS+KRrSce68gTEQnFqZ1WKhULOYDNKGx4="
      )
      (photo "14-night-coast.jpg" "1701497574685-1115c4ba215e"
        "sha256-GVn1X9CqKgli+7L1Ylhe6jQoqIr+pSWwz1Pu6RLklJc="
      )
      (photo "15-mountain-night.jpg" "1713769920897-eef95e8717f5"
        "sha256-Lq9QQTB0grdf8Ol/I3DL8jzf4unwMJTvx5HRnVWGcU0="
      )
    ]
    ++
      map
        (id: {
          name = "existing-${id}.png";
          path = ./. + "/wallpaper-${id}.png";
        })
        [
          "002"
          "005"
          "008"
          "009"
          "011"
        ];
in
{
  inherit generated wallpapers;
  # The user chose 005 as the default on 2026-10-24.
  default = "${./wallpaper-005.png}";
  directory = pkgs.linkFarm "astra-cool-wallpapers" wallpapers;
}
