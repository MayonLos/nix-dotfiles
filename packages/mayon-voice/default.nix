{ pkgs }:
let
  python = pkgs.python3.withPackages (ps: [
    ps.sherpa-onnx
    ps.numpy
    ps.webrtcvad
    ps.setuptools
  ]);
  addon = import ./fcitx { inherit pkgs; };
in
pkgs.rustPlatform.buildRustPackage {
  pname = "mayon-voice";
  version = "0.1.0";
  # The shared UI is a public path dependency with its own workspace metadata.
  src = pkgs.lib.cleanSourceWith {
    src = ../..;
    filter =
      path: type:
      let
        rel = pkgs.lib.removePrefix "${toString ../..}/" (toString path);
      in
      (
        type == "directory"
        || pkgs.lib.hasPrefix "packages/mayon-voice/" rel
        || pkgs.lib.hasPrefix "packages/mayon-tui/" rel
      )
      && !(builtins.elem (builtins.baseNameOf path) [
        ".git"
        ".work"
        ".worktrees"
        "target"
        "__pycache__"
      ])
      && pkgs.lib.cleanSourceFilter path type;
  };
  cargoRoot = "packages/mayon-voice";
  buildAndTestSubdir = "packages/mayon-voice";
  cargoLock.lockFile = ./Cargo.lock;
  MAYON_TUI_PALETTE = builtins.toJSON (import ../../aspects/appearance/appearance/onedark.nix);
  nativeBuildInputs = [
    pkgs.makeWrapper
    pkgs.clippy
    pkgs.rustfmt
    pkgs.python3
  ];
  doCheck = true;
  preCheck = ''
    cargo clippy --offline --manifest-path packages/mayon-voice/Cargo.toml --all-targets -- -D warnings
    cargo fmt --manifest-path packages/mayon-voice/Cargo.toml --all --check
    python3 packages/mayon-voice/engine/test_worker.py
    python3 packages/mayon-voice/engine/test_polish.py
    python3 packages/mayon-voice/engine/test_models.py
    python3 packages/mayon-voice/tests/daemon.py target/${pkgs.stdenv.hostPlatform.rust.rustcTarget}/release/mayon-voice
  '';
  postInstall = ''
    mkdir -p "$out/lib/mayon-voice"
    cp packages/mayon-voice/engine/{worker,models,polish}.py "$out/lib/mayon-voice/"
    wrapProgram "$out/bin/mayon-voice" \
      --set MAYON_VOICE_ENGINE_DIR "$out/lib/mayon-voice" \
      --prefix PATH : ${
        pkgs.lib.makeBinPath [
          python
          pkgs.pipewire
          pkgs.systemd
          pkgs.libnotify
          pkgs.wl-clipboard
          pkgs.wtype
        ]
      }
  '';
  passthru.fcitxAddon = addon;
  meta = {
    description = "Socket-activated local Chinese voice input with focus-safe Fcitx submission";
    license = pkgs.lib.licenses.mit;
    platforms = pkgs.lib.platforms.linux;
    mainProgram = "mayon-voice";
  };
}
