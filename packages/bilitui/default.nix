{ pkgs }:
let
  source = pkgs.lib.cleanSourceWith {
    src = ../..;
    filter =
      path: type:
      let
        relative = pkgs.lib.removePrefix (toString ../.. + "/") (toString path);
      in
      !(builtins.elem (builtins.baseNameOf path) [
        "target"
        ".git"
        ".work"
        "result"
      ])
      && (
        builtins.elem relative [
          "packages"
          "aspects"
          "aspects/appearance"
          "aspects/appearance/appearance"
          "aspects/appearance/appearance/onedark.nix"
        ]
        || pkgs.lib.hasPrefix "packages/bilitui" relative
        || pkgs.lib.hasPrefix "packages/mayon-tui" relative
        || pkgs.lib.hasPrefix "packages/mayon-voice" relative
        || type == "directory" && toString path == toString ../..
      );
  };
in
pkgs.rustPlatform.buildRustPackage {
  pname = "bilitui-mayon";
  version = "0.1.0";
  src = source;
  sourceRoot = "${source.name}/packages/bilitui";
  cargoLock.lockFile = ./Cargo.lock;
  nativeBuildInputs = with pkgs; [
    clippy
    rustfmt
    makeWrapper
  ];
  MAYON_TUI_PALETTE = builtins.toJSON (import ../../aspects/appearance/appearance/onedark.nix);
  preCheck = ''
    cargo fmt --all -- --check
    cargo clippy --offline --all-targets -- -D warnings
  '';
  postInstall = ''
    wrapProgram "$out/bin/bilitui-mayon" --suffix PATH : ${
      pkgs.lib.makeBinPath [
        pkgs.mpv
        pkgs.ffmpeg
      ]
    }
    install -Dm644 ${./bilitui-mayon.desktop} "$out/share/applications/bilitui-mayon.desktop"
  '';
  meta = {
    description = "Bilibili terminal browser with mpv, ASS danmaku and downloads";
    license = pkgs.lib.licenses.mit;
    mainProgram = "bilitui-mayon";
    platforms = pkgs.lib.platforms.linux;
  };
}
