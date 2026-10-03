{ pkgs, ... }:

let
  toolchains = import ../../../../lib/toolchains.nix { inherit pkgs; };
in

{
  # clangd and clang-format live in toolchain.nix and come from the same
  # llvmPackages set (lib/toolchains.nix) — they are what the editors start,
  # not what builds code.
  home.packages = with pkgs; [
    toolchains.llvm.clang
    toolchains.llvm.lld
    cmake
    ninja
    pkg-config
    ccache
    meson
    gdb
  ];
}
