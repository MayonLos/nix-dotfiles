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
  nativeBuildInputs = [
    pkgs.clippy
    pkgs.makeWrapper
  ];
  doCheck = true;
  MAYON_TEST_SHELL = pkgs.runtimeShell;
  preCheck = ''
    cargo clippy --offline --workspace --all-targets -- -D warnings
  '';
  postInstall = ''
    for pair in "clash clashtui-mayon" "docker dockertui-mayon" "ports portstui-mayon"; do
      read -r output binary <<< "$pair"
      destination="''${!output}"
      mkdir -p "$destination/bin"
      mv "$out/bin/$binary" "$destination/bin/$binary"
      if [ "$output" = clash ]; then
        wrapProgram "$destination/bin/$binary" \
          --prefix PATH : ${
            pkgs.lib.makeBinPath [
              pkgs.mihomo
              pkgs.yq-go
              pkgs.systemd
            ]
          } \
          --set-default MAYON_CLASH_GEOIP ${pkgs.v2ray-geoip}/share/v2ray/geoip.dat \
          --set-default MAYON_CLASH_GEOSITE ${pkgs.v2ray-domain-list-community}/share/v2ray/geosite.dat \
          --set-default MAYON_CLASH_MMDB ${pkgs.dbip-country-lite.mmdb}
      fi
      ln -s "$destination/bin/$binary" "$out/bin/$binary"
    done
    install -Dm644 scripts/clash-preflight.py "$clash/share/mayon-tui/clash-preflight.py"
    makeWrapper ${pkgs.python3}/bin/python3 "$clash/bin/mayon-clash-preflight" \
      --add-flags "$clash/share/mayon-tui/clash-preflight.py"
  '';
  meta = {
    description = "Mayon's shared Rust terminal tools for Clash, Docker and listening ports";
    license = pkgs.lib.licenses.mit;
    platforms = pkgs.lib.platforms.linux;
  };
}
