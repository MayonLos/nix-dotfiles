_:
{
  perSystem =
    { pkgs, ... }:
    {
      devShells = {
        cuda = pkgs.mkShell {
          name = "cuda-dev";
          packages = with pkgs; [
            cudaPackages.cudatoolkit
            cudaPackages.cudnn
            linuxKernel.packages.linux_zen.nvidia_x11
          ];
          shellHook = ''
            export CUDA_PATH=${pkgs.cudaPackages.cudatoolkit}
          '';
        };
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
