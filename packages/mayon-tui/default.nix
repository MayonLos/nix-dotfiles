{ pkgs }:
pkgs.rustPlatform.buildRustPackage {
  pname = "mayon-tui";
  version = "0.2.0";
  src = pkgs.lib.cleanSourceWith {
    src = ./.;
    filter = path: type: builtins.baseNameOf path != "target" && pkgs.lib.cleanSourceFilter path type;
  };
  cargoLock.lockFile = ./Cargo.lock;
  MAYON_TUI_PALETTE = builtins.toJSON (import ../../aspects/appearance/appearance/onedark.nix);
  outputs = [
    "out"
    "clash"
    "docker"
    "ports"
  ];
  nativeBuildInputs = [ pkgs.clippy ];
  doCheck = true;
  preCheck = ''
    cargo clippy --offline --workspace --all-targets -- -D warnings
  '';
  postInstall = ''
    for pair in "clash clashtui-mayon" "docker dockertui-mayon" "ports portstui-mayon"; do
      read -r output binary <<< "$pair"
      destination="''${!output}"
      mkdir -p "$destination/bin"
      mv "$out/bin/$binary" "$destination/bin/$binary"
      ln -s "$destination/bin/$binary" "$out/bin/$binary"
    done
  '';
  meta = {
    description = "Mayon's shared Rust terminal tools for Clash, Docker and listening ports";
    license = pkgs.lib.licenses.mit;
    platforms = pkgs.lib.platforms.linux;
  };
}
