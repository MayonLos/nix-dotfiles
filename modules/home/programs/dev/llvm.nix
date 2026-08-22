{ pkgs, ... }:
{
  # clangd and clang-format live in toolchain.nix — they are what the editors
  # start, not what builds code.
  home.packages = with pkgs; [
    clang
    lld
    cmake
    ninja
    pkg-config
    ccache
    meson
    gdb
  ];
}
