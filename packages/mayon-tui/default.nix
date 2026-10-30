{ pkgs }:
pkgs.rustPlatform.buildRustPackage {
  pname = "mayon-tui";
  version = "0.2.0";
  src = pkgs.lib.cleanSourceWith {
    src = ../..;
    filter =
      path: type:
      let
        rel = pkgs.lib.removePrefix "${toString ../..}/" (toString path);
        allowed = [
          "packages/mayon-tui"
          "packages/mayon-voice"
          "aspects/appearance/appearance/onedark.nix"
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
  cargoRoot = "packages/mayon-tui";
  buildAndTestSubdir = "packages/mayon-tui";
  cargoLock.lockFile = ./Cargo.lock;
  MAYON_TUI_PALETTE = builtins.toJSON (import ../../aspects/appearance/appearance/onedark.nix);
  outputs = [
    "out"
    "clash"
    "tools"
  ];
  nativeBuildInputs = [
    pkgs.clippy
    pkgs.makeWrapper
  ];
  doCheck = true;
  MAYON_TEST_SHELL = pkgs.runtimeShell;
  SERIAL_MAYON_SHELL = pkgs.runtimeShell;
  preCheck = ''
    (cd packages/mayon-tui && cargo clippy --offline --workspace --all-targets -- -D warnings)
  '';
  postInstall = ''
    for pair in "clash clashtui-mayon" "tools mayon-tools"; do
      read -r output binary <<< "$pair"
      destination="''${!output}"
      mkdir -p "$destination/bin"
      mv "$out/bin/$binary" "$destination/bin/$binary"
      if [ "$output" = clash ]; then
        wrapProgram "$destination/bin/$binary" \
          --prefix PATH : ${
            pkgs.lib.makeBinPath [
              pkgs.mihomo
              pkgs.systemd
            ]
          } \
          --set-default MAYON_CLASH_GEOIP ${pkgs.v2ray-geoip}/share/v2ray/geoip.dat \
          --set-default MAYON_CLASH_GEOSITE ${pkgs.v2ray-domain-list-community}/share/v2ray/geosite.dat \
          --set-default MAYON_CLASH_MMDB ${pkgs.dbip-country-lite.mmdb}
      else
        wrapProgram "$destination/bin/$binary" \
          --set SERIAL_MAYON_SHELL ${pkgs.runtimeShell} \
          --prefix PATH : ${
            pkgs.lib.makeBinPath [
              pkgs.docker
              pkgs.libvirt
              pkgs.wl-clipboard
              pkgs.xdg-utils
            ]
          }
      fi
      ln -s "$destination/bin/$binary" "$out/bin/$binary"
    done
    install -Dm644 packages/mayon-tui/scripts/clash-preflight.py "$clash/share/mayon-tui/clash-preflight.py"
    makeWrapper ${pkgs.python3}/bin/python3 "$clash/bin/mayon-clash-preflight" \
      --add-flags "$clash/share/mayon-tui/clash-preflight.py"
  '';
  meta = {
    description = "Mayon's independent Clash TUI and lazy terminal toolbox";
    license = pkgs.lib.licenses.mit;
    platforms = pkgs.lib.platforms.linux;
  };
}
