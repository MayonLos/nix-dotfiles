{ pkgs, ... }:
{
  home.packages = with pkgs; [
    clang
    clang-tools
    lld
    cmake
    ninja
    pkg-config
    ccache
    meson
    gdb
  ];
}
