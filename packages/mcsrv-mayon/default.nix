{ pkgs }:
let
  java = import ../../lib/java.nix { inherit pkgs; };
  javaMap = builtins.mapAttrs (_: jdk: "${jdk}/bin/java") java.jdks;
in
pkgs.rustPlatform.buildRustPackage {
  pname = "mcsrv-mayon";
  version = "0.1.0";
  src = pkgs.lib.cleanSourceWith {
    src = ./.;
    filter = path: type: builtins.baseNameOf path != "target" && pkgs.lib.cleanSourceFilter path type;
  };
  cargoLock.lockFile = ./Cargo.lock;
  MAYON_TUI_PALETTE = builtins.toJSON (import ../../aspects/appearance/appearance/onedark.nix);
  doCheck = true;
  nativeCheckInputs = [
    pkgs.restic
    pkgs.bash
    pkgs.coreutils
  ];
  nativeBuildInputs = [
    pkgs.clippy
    pkgs.rustfmt
    pkgs.makeWrapper
  ];
  preCheck = ''
    cargo fmt --all -- --check
    cargo clippy --offline --workspace --all-targets -- -D warnings
  '';
  postInstall = ''
    wrapProgram "$out/bin/mcsrv-mayon" \
      --prefix PATH : ${
        pkgs.lib.makeBinPath [
          pkgs.restic
          pkgs.systemd
          pkgs.iproute2
          pkgs.tailscale
        ]
      } \
      --set MCSRV_JAVA_MAP ${pkgs.lib.escapeShellArg (builtins.toJSON javaMap)} \
      --set MCSRV_SELF "$out/bin/mcsrv-mayon"
  '';
  meta = {
    description = "Minecraft server manager TUI and CLI";
    license = pkgs.lib.licenses.mit;
    platforms = pkgs.lib.platforms.linux;
    mainProgram = "mcsrv-mayon";
  };
}
