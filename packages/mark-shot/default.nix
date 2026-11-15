{
  pkgs,
  rustc,
  cargo,
}:
let
  # rust-toolchain.toml in this tree pins 1.99.1. Stable nixpkgs rustc is older.
  rustPlatform = pkgs.makeRustPlatform { inherit rustc cargo; };
in
rustPlatform.buildRustPackage {
  pname = "mark-shot";
  version = "0.2.0";
  src = pkgs.lib.cleanSource ./.;
  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = with pkgs; [
    pkg-config
    clang
    nasm
    makeWrapper
  ];
  buildInputs = with pkgs; [
    libclang
    wayland
    libxkbcommon
    libxcb
    pipewire
    openssl
    fontconfig
    libva
    libdrm
    libgbm
    libpulseaudio
  ];
  LIBCLANG_PATH = "${pkgs.lib.getLib pkgs.libclang}/lib";

  # Upstream tests need private fonts, a media library and a display.
  # The Mango rectangle tests live in window_detection::mango and are not
  # executed by this package build.
  doCheck = false;

  postInstall = ''
    wrapProgram "$out/bin/mark-shot" --prefix PATH : ${
      pkgs.lib.makeBinPath [
        pkgs.fontconfig
      ]
    }
  '';

  meta = {
    description = "Local Rust screenshot, annotation and scrolling capture tool";
    homepage = "https://github.com/jswysnemc/mark-shot";
    license = with pkgs.lib.licenses; [
      mit
      asl20
    ];
    mainProgram = "mark-shot";
    platforms = pkgs.lib.platforms.linux;
  };
}
