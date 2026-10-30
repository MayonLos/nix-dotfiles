{ pkgs }:
let
  dictionarySource = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/skywind3000/ECDICT/ab22ad36302cafc6349a050e2b60894855208055/ecdict.csv";
    hash = "sha256-0ey9+e4rkgr7b0MMpra7n1WViM8N/4bgS9JV+TkIQ8w=";
  };
  dictionary = pkgs.runCommand "study-ecdict.sqlite3" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    python3 ${./scripts/build_dictionary.py} ${dictionarySource} "$out"
  '';
in
pkgs.rustPlatform.buildRustPackage {
  pname = "study-mayon";
  version = "0.1.0";
  src = pkgs.lib.cleanSourceWith {
    src = ../..;
    filter =
      path: type:
      let
        rel = pkgs.lib.removePrefix "${toString ../..}/" (toString path);
        allowed = [
          "packages/study-mayon"
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
  cargoRoot = "packages/study-mayon";
  buildAndTestSubdir = "packages/study-mayon";
  cargoLock.lockFile = ./Cargo.lock;
  MAYON_TUI_PALETTE = builtins.toJSON (import ../../aspects/appearance/appearance/onedark.nix);
  nativeBuildInputs = [
    pkgs.clippy
    pkgs.rustfmt
    pkgs.makeWrapper
  ];
  doCheck = true;
  preCheck = ''
    (cd packages/study-mayon && cargo fmt --check && cargo clippy --offline --all-targets -- -D warnings)
  '';
  postInstall = ''
    mkdir -p "$out/share/study" "$out/share/licenses/study-mayon"
    cp ${dictionary} "$out/share/study/dictionary.sqlite3"
    cp ${./data/ECDICT-LICENSE} "$out/share/licenses/study-mayon/ECDICT-MIT"
    wrapProgram "$out/bin/study-mayon" \
      --set STUDY_EXECUTABLE "$out/bin/study-mayon" \
      --set STUDY_DICTIONARY "$out/share/study/dictionary.sqlite3" \
      --prefix PATH : ${
        pkgs.lib.makeBinPath [
          pkgs.coreutils
          pkgs.wl-clipboard
          pkgs.espeak-ng
          pkgs.mpv
          pkgs.libnotify
          pkgs.systemd
          pkgs.kitty
        ]
      }
    ln -s "$out/bin/study-mayon" "$out/bin/study"
  '';
  meta = {
    description = "FSRS vocabulary learning and university timetable in a One Dark TUI";
    license = pkgs.lib.licenses.mit;
    platforms = pkgs.lib.platforms.linux;
    mainProgram = "study-mayon";
  };
}
