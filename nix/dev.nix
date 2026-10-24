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
            sops
            age
            ssh-to-age
          ];
        };

        cuda = pkgs.mkShell {
          name = "cuda-dev";
          packages = with pkgs.cudaPackages; [
            cudatoolkit
            cudnn
            # cudatoolkit already includes this pinned cuda_nvcc output.
          ];
          CUDA_PATH = "${pkgs.cudaPackages.cudatoolkit}";
        };
      };

      treefmt = {
        projectRootFile = "flake.nix";
        programs = {
          nixfmt.enable = true;
          deadnix = {
            enable = true;
            # Den dispatches by lambda argument shape, including unused names.
            no-lambda-pattern-names = true;
          };
          statix.enable = true;
          stylua.enable = true;
        };
      };
    };
}
