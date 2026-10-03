{ pkgs }:

# Version source for the language modules: each language's compiler or
# interpreter and the editor-side tools built against it come from the same set
# here, so a bump cannot leave clangd on a different LLVM than clang, or
# pylatexenc on a different Python than the profile's `python3`.
# Java is the exception: its multi-version Temurin set lives in lib/java.nix.
{
  # C/C++: clang, lld and clang-tools (clangd + clang-format).
  llvm = pkgs.llvmPackages;

  # Python: the interpreter, its package set (`<python>.pkgs.*`) and the bare
  # `python3` nvim-dap starts from PATH.
  python = pkgs.python3;

  # Lua 5.4: interpreter and package set (luarocks, luacheck). nixpkgs names
  # the package set after the version, so change both lines together.
  lua = pkgs.lua5_4;
  luaPackages = pkgs.lua54Packages;
}
