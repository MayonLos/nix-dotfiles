{ pkgs }:
pkgs.stdenv.mkDerivation {
  pname = "mayon-voice-fcitx-bridge";
  version = "0.1.0";
  src = ./.;

  nativeBuildInputs = [
    pkgs.cmake
    pkgs.pkg-config
  ];
  buildInputs = [ pkgs.fcitx5 ];

  meta = {
    description = "Fcitx5 D-Bus text commit bridge for mayon-voice";
    platforms = pkgs.lib.platforms.linux;
  };
}
