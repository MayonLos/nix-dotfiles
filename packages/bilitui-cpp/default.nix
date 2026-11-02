{ pkgs }:
let
  palette = pkgs.writeText "palette.inc" (
    import ./tools/palette.nix (import ../../aspects/appearance/appearance/onedark.nix)
  );
in
pkgs.stdenv.mkDerivation {
  pname = "bilitui-next";
  version = "0.1.0";
  src = pkgs.lib.cleanSourceWith {
    src = ./.;
    filter =
      path: _:
      !(builtins.elem (baseNameOf path) [
        "build"
        "result"
      ]);
  };
  nativeBuildInputs = with pkgs; [
    meson
    ninja
    pkg-config
    makeWrapper
  ];
  buildInputs = with pkgs; [
    curl
    doctest
    ftxui
    libjpeg_turbo
    nlohmann_json
    qrencode
  ];
  postPatch = ''
    cp ${palette} src/ui/palette.inc
  '';
  doCheck = true;
  # The search path stays a suffix so a user's own mpv and ffmpeg win.
  postInstall = ''
    wrapProgram "$out/bin/bilitui-next" --suffix PATH : ${
      pkgs.lib.makeBinPath [
        pkgs.mpv
        pkgs.ffmpeg
        pkgs.xdg-utils
      ]
    }
  '';
  meta = {
    description = "Search-first Bilibili terminal player for learning, built around mpv";
    license = pkgs.lib.licenses.mit;
    mainProgram = "bilitui-next";
    platforms = pkgs.lib.platforms.linux;
  };
}
