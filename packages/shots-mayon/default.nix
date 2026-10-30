{ pkgs }:
let
  source = pkgs.lib.fileset.toSource {
    root = ../..;
    fileset = pkgs.lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./src
      ./tests
      ../mayon-tui/Cargo.toml
      ../mayon-tui/crates/ui
      ../../aspects/appearance/appearance/onedark.nix
    ];
  };
  ocr = pkgs.tesseract5.override {
    enableLanguages = [
      "eng"
      "chi_sim"
    ];
  };
in
pkgs.rustPlatform.buildRustPackage {
  pname = "shots-mayon";
  version = "0.1.0";
  src = source;
  cargoRoot = "packages/shots-mayon";
  buildAndTestSubdir = "packages/shots-mayon";
  cargoLock.lockFile = ./Cargo.lock;
  MAYON_TUI_PALETTE = builtins.toJSON (import ../../aspects/appearance/appearance/onedark.nix);
  nativeBuildInputs = [
    pkgs.clippy
    pkgs.rustfmt
    pkgs.makeWrapper
  ];
  doCheck = true;
  nativeCheckInputs = [
    pkgs.python3
    pkgs.coreutils
    pkgs.util-linux
  ];
  preCheck = ''
    cargo fmt --manifest-path packages/shots-mayon/Cargo.toml --package shots-mayon --check
    cargo clippy --manifest-path packages/shots-mayon/Cargo.toml --offline --all-targets -- -D warnings
  '';
  postCheck = ''
    python3 packages/shots-mayon/tests/runtime.py target/''${CARGO_BUILD_TARGET:-x86_64-unknown-linux-gnu}/release/shots-mayon
  '';
  postInstall = ''
    wrapProgram "$out/bin/shots-mayon" \
      --set SHOTS_SELF "$out/bin/shots-mayon" \
      --prefix PATH : ${
        pkgs.lib.makeBinPath [
          pkgs.ffmpeg
          pkgs.wf-recorder
          pkgs.slurp
          pkgs.wl-clipboard
          pkgs.libnotify
          pkgs.pulseaudio
          pkgs.glib
          pkgs.xdg-utils
          pkgs.trash-cli
          pkgs.coreutils
          pkgs.util-linux
          ocr
        ]
      }
  '';
  meta = {
    description = "Private screenshot and recording library with local OCR and Kitty previews";
    license = pkgs.lib.licenses.mit;
    platforms = pkgs.lib.platforms.linux;
    mainProgram = "shots-mayon";
  };
}
