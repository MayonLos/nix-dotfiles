_: {
  den.aspects.cpp-support = {
    homeManager = { pkgs, ... }: {
      imports = [ ./cpp-tools.nix ];
      home.packages = [ pkgs.llvmPackages.clang-tools ];
    };
    editorLanguages = [ (import ./cpp-data.nix) ];
  };
}
