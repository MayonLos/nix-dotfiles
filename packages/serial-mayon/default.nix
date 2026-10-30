{ pkgs }:
pkgs.rustPlatform.buildRustPackage {
  pname = "serial-mayon";
  version = "0.1.0";
  src = pkgs.lib.cleanSourceWith {
    src = ../..;
    filter =
      path: type:
      let
        rel = pkgs.lib.removePrefix "${toString ../..}/" (toString path);
        allowed = [
          "packages/serial-mayon"
          "packages/mayon-tui/crates/ui"
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
  cargoRoot = "packages/serial-mayon";
  buildAndTestSubdir = "packages/serial-mayon";
  cargoLock.lockFile = ./Cargo.lock;
  MAYON_TUI_PALETTE = builtins.toJSON (import ../../aspects/appearance/appearance/onedark.nix);
  SERIAL_MAYON_SHELL = pkgs.runtimeShell;
  nativeBuildInputs = [
    pkgs.clippy
    pkgs.rustfmt
    pkgs.makeWrapper
  ];
  doCheck = true;
  preCheck = ''
    (cd packages/serial-mayon && cargo fmt --check && cargo clippy --offline --all-targets -- -D warnings)
  '';
  postInstall = ''
    wrapProgram "$out/bin/serial-mayon" --set SERIAL_MAYON_SHELL ${pkgs.runtimeShell}
  '';
  meta = {
    description = "STM32 serial monitor with searchable capture, braille plots and flash handoff";
    mainProgram = "serial-mayon";
    license = pkgs.lib.licenses.mit;
    platforms = pkgs.lib.platforms.linux;
  };
}
