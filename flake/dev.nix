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
            cuda_nvcc
          ];
          CUDA_PATH = "${pkgs.cudaPackages.cudatoolkit}";
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
