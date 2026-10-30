{ pkgs }:
let
  source = pkgs.lib.fileset.toSource {
    root = ../..;
    fileset = pkgs.lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./src
      ./tests/fixtures.py
      ./tests/benchmark.py
      ../mayon-tui/Cargo.toml
      ../mayon-tui/crates/ui
      ../../aspects/appearance/appearance/onedark.nix
    ];
  };
in
pkgs.rustPlatform.buildRustPackage {
  pname = "seek";
  version = "0.1.0";
  src = source;
  cargoRoot = "packages/seek";
  buildAndTestSubdir = "packages/seek";
  cargoLock.lockFile = ./Cargo.lock;
  MAYON_TUI_PALETTE = builtins.toJSON (import ../../aspects/appearance/appearance/onedark.nix);
  nativeBuildInputs = [
    pkgs.clippy
    pkgs.rustfmt
    pkgs.makeWrapper
  ];
  nativeCheckInputs = [
    pkgs.poppler-utils
    pkgs.python3
  ];
  preCheck = ''
    cargo fmt --manifest-path packages/seek/Cargo.toml --package seek --check
    cargo clippy --manifest-path packages/seek/Cargo.toml --offline --all-targets -- -D warnings
  '';
  postCheck = ''
    python3 packages/seek/tests/fixtures.py "$TMPDIR/corpus"
    export HOME="$TMPDIR/home" XDG_CONFIG_HOME="$TMPDIR/home/.config" XDG_DATA_HOME="$TMPDIR/home/.local/share"
    mkdir -p "$HOME"
    python3 packages/seek/tests/benchmark.py --binary target/''${CARGO_BUILD_TARGET:-x86_64-unknown-linux-gnu}/release/seek --root "$TMPDIR/corpus" --output "$TMPDIR/report.json" --lexical
  '';
  postInstall = ''
    wrapProgram "$out/bin/seek" \
      --prefix PATH : ${
        pkgs.lib.makeBinPath [
          pkgs.poppler-utils
          pkgs.xdg-utils
        ]
      } \
      --set ORT_DYLIB_PATH ${pkgs.onnxruntime}/lib/libonnxruntime.so
  '';
  meta = {
    description = "Private local document search with explicit cited question answering";
    license = pkgs.lib.licenses.mit;
    platforms = pkgs.lib.platforms.linux;
    mainProgram = "seek";
  };
}
