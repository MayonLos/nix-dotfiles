{ pkgs, ... }:

let
  toolchains = import ./toolchains.nix { inherit pkgs; };
in

{
  # clangd and clang-format live in the selected language aspect and come from the same
  # llvmPackages set (lib/toolchains.nix) — they are what the editors start,
  # not what builds code. Project-specific extras such as Meson and ccache
  # belong in the project's flake when needed.
  # Lets clangd resolve multi-file CMake projects without a per-project flag.
  home.sessionVariables.CMAKE_EXPORT_COMPILE_COMMANDS = "ON";
  home.packages = with pkgs; [
    toolchains.llvm.clang
    toolchains.llvm.lld
    bear
    cmake
    ninja
    pkg-config
    gdb
  ];
}
