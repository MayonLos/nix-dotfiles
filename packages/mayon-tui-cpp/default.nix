{ pkgs }:
let
  palette = pkgs.writeText "palette.inc" (
    import ./tools/palette.nix (import ../../aspects/appearance/appearance/onedark.nix)
  );
  runtimePath = pkgs.lib.makeBinPath [
    pkgs.docker
    pkgs.ffmpeg
    pkgs.libvirt
    pkgs.mihomo
    pkgs.mpv
    pkgs.systemd
    pkgs.wl-clipboard
    pkgs.xdg-utils
  ];
  clashEnvironment = ''
    --set-default MAYON_CLASH_GEOIP ${pkgs.v2ray-geoip}/share/v2ray/geoip.dat \
    --set-default MAYON_CLASH_GEOSITE ${pkgs.v2ray-domain-list-community}/share/v2ray/geosite.dat \
    --set-default MAYON_CLASH_MMDB ${pkgs.dbip-country-lite.mmdb}
  '';
in
pkgs.stdenv.mkDerivation {
  pname = "mayon-tui-next";
  version = "0.2.0";
  src = pkgs.lib.cleanSourceWith {
    src = ./.;
    filter =
      path: _:
      !(builtins.elem (baseNameOf path) [
        "build"
        "build-asan"
        "result"
      ]);
  };
  nativeBuildInputs = with pkgs; [
    meson
    ninja
    pkg-config
    makeWrapper
    # The integration tests drive the crates' Python mock servers and PTYs.
    python3
  ];
  buildInputs = with pkgs; [
    curl
    doctest
    ftxui
    libjpeg_turbo
    nlohmann_json
    qrencode
  ];
  postPatch = ''
    cp ${palette} ui/palette.inc
  '';
  doCheck = true;
  # Only the three real programs are installed; per-tool demo binaries stay out.
  # The search path stays a suffix so a user's own tools win.
  postInstall = ''
    wrapProgram "$out/bin/bilitui-next" --suffix PATH : ${runtimePath}
    wrapProgram "$out/bin/mayon-tools-next" \
      --set SERIAL_MAYON_SHELL ${pkgs.runtimeShell} \
      --suffix PATH : ${runtimePath}
    wrapProgram "$out/bin/clashtui-next" \
      --prefix PATH : ${runtimePath} \
      ${clashEnvironment}
  '';
  meta = {
    description = "C++ rewrite of the Bilibili player, toolbox and Clash terminal UIs";
    license = pkgs.lib.licenses.mit;
    mainProgram = "mayon-tools-next";
    platforms = pkgs.lib.platforms.linux;
  };
}
