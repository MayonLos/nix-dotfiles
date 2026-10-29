{ pkgs, palette }:
pkgs.rustPlatform.buildRustPackage {
  pname = "clashtui-mayon";
  version = "0.1.0";
  src = pkgs.lib.cleanSourceWith {
    src = ./.;
    filter = path: type: (builtins.baseNameOf path != "target") && pkgs.lib.cleanSourceFilter path type;
  };
  cargoLock.lockFile = ./Cargo.lock;
  CLASHTUI_PALETTE = builtins.toJSON palette;
  nativeBuildInputs = [ pkgs.clippy ];
  doCheck = true;
  preCheck = ''
    cargo clippy --offline --all-targets -- -D warnings
  '';
  meta = {
    description = "Mihomo Unix controller TUI with read-only Clash Verge subscription viewing";
    mainProgram = "clashtui-mayon";
    license = pkgs.lib.licenses.mit;
    platforms = pkgs.lib.platforms.linux;
  };
}
