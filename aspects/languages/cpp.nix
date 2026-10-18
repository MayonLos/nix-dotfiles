_: {
  den.aspects.cpp-support = {
    homeManager = { pkgs, ... }: {
      home.packages = with pkgs.llvmPackages; [
        clang
        lld
        clang-tools
      ];
    };
    editorLanguages = [ (import ./cpp-data.nix) ];
  };
}
