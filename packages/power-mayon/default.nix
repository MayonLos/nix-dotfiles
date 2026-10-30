{ pkgs }:
pkgs.rustPlatform.buildRustPackage {
  pname = "power-mayon";
  version = "0.1.0";
  src = pkgs.lib.fileset.toSource {
    root = ../.;
    fileset = pkgs.lib.fileset.unions [
      (pkgs.lib.fileset.fileFilter (
        file:
        builtins.elem file.name [
          "Cargo.toml"
          "Cargo.lock"
          "backend.py"
          "test_backend.py"
        ]
      ) ./.)
      ./src
      ../mayon-tui/crates/ui
      ../mayon-tui/Cargo.toml
    ];
  };
  cargoRoot = "power-mayon";
  buildAndTestSubdir = "power-mayon";
  cargoLock.lockFile = ./Cargo.lock;
  MAYON_TUI_PALETTE = builtins.toJSON (import ../../aspects/appearance/appearance/onedark.nix);
  nativeBuildInputs = [
    pkgs.clippy
    pkgs.rustfmt
    pkgs.makeWrapper
    pkgs.python3
  ];
  doCheck = true;
  preCheck = ''
    cargo fmt --manifest-path power-mayon/Cargo.toml -- --check
    cargo clippy --offline --manifest-path power-mayon/Cargo.toml --all-targets -- -D warnings
    python3 -m unittest discover -s power-mayon -p 'test_*.py' -v
  '';
  postInstall = ''
    install -Dm644 power-mayon/backend.py "$out/share/power-mayon/backend.py"
    wrapProgram "$out/bin/power-mayon" \
      --set POWER_MAYON_BACKEND "$out/share/power-mayon/backend.py" \
      --set POWER_MAYON_PYTHON ${pkgs.python3}/bin/python3 \
      --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.power-profiles-daemon ]}
  '';
  passthru.profilePolicy = builtins.readFile ./profile-policy.rules;
  meta = {
    description = "Legion battery telemetry and PPD profile controls with One Dark TUI";
    license = pkgs.lib.licenses.mit;
    mainProgram = "power-mayon";
    platforms = pkgs.lib.platforms.linux;
  };
}
