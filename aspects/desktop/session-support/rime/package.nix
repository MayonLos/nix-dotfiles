{ pkgs }:
let
  # LTS is upstream's named model release (not /latest or a rolling branch).
  # Asset snapshot: 2026-10-19, 398497836 bytes. The hash pins its exact bytes
  # even if upstream replaces the asset under its long-lived LTS tag.
  model = pkgs.fetchurl {
    url = "https://github.com/amzxyz/rime-wanxiang-data/releases/download/LTS/wanxiang-lts-zh-hans.gram";
    hash = "sha256-nu2sHYNvP9r7YbFiA1yJNyU67cEGvkCyuVfZq2Tp7Yk=";
  };
  grammarData = pkgs.runCommand "rime-wanxiang-lts-2026-10-19" { } ''
    mkdir -p "$out/share/rime-data"
    ln -s ${model} "$out/share/rime-data/wanxiang-lts-zh-hans.gram"
  '';
  # nixpkgs 26.05 merges both plugins into librime.so, rather than installing
  # separate plugin .so files. Keep Lua explicit: Rime-Ice uses Lua processors.
  engine = pkgs.librime.override {
    plugins = [
      pkgs.librime-lua
      pkgs.librime-octagram
    ];
  };
in
(pkgs.fcitx5-rime.override {
  librime = engine;
  rimeDataPkgs = [
    pkgs.rime-ice
    grammarData
  ];
}).overrideAttrs
  (old: {
    passthru = (old.passthru or { }) // {
      inherit engine model;
    };
  })
