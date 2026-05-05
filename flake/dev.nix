_: {
  perSystem =
    { pkgs, ... }:
    {
      devShells = {
        default = pkgs.mkShell {
          name = "default-dev";
          packages = with pkgs; [
            git
            gnumake
            clang-tools
          ];
        };
      };

      treefmt = {
        projectRootFile = "flake.nix";
        programs = {
          nixfmt.enable = true;
          deadnix.enable = true;
          statix.enable = true;
        };
      };
    };
}
