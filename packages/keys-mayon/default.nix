{ pkgs }:
pkgs.rustPlatform.buildRustPackage {
  pname = "keys-mayon";
  version = "0.1.0";
  src = pkgs.lib.cleanSourceWith {
    src = ../..;
    filter =
      path: type:
      let
        rel = pkgs.lib.removePrefix "${toString ../..}/" (toString path);
        allowed = [
          "packages/keys-mayon"
          "packages/mayon-tui/crates/ui"
          "aspects/appearance/appearance/onedark.nix"
          "packages/mayon-tui/Cargo.toml"
        ];
      in
      pkgs.lib.cleanSourceFilter path type
      && !(builtins.elem (builtins.baseNameOf path) [
        "target"
        ".work"
        "__pycache__"
      ])
      && (
        path == toString ../..
        || builtins.any (
          prefix: pkgs.lib.hasPrefix prefix rel || pkgs.lib.hasPrefix "${rel}/" prefix
        ) allowed
      );
  };
  cargoRoot = "packages/keys-mayon";
  buildAndTestSubdir = "packages/keys-mayon";
  cargoLock.lockFile = ./Cargo.lock;
  MAYON_TUI_PALETTE = builtins.toJSON (import ../../aspects/appearance/appearance/onedark.nix);
  nativeBuildInputs = [
    pkgs.clippy
    pkgs.rustfmt
  ];
  doCheck = true;
  preCheck = ''
    (cd packages/keys-mayon && cargo fmt --check && cargo clippy --offline --all-targets -- -D warnings)
  '';
  meta = {
    description = "Generated Mango shortcut reference in a One Dark terminal UI";
    license = pkgs.lib.licenses.mit;
    platforms = pkgs.lib.platforms.linux;
    mainProgram = "keys-mayon";
  };
}
