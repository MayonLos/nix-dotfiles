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
            cargo
            rustc
            rust-analyzer
            clippy
            rustfmt
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
        settings.formatter.statix = {
          command = pkgs.writeShellScriptBin "statix-check" ''
            set -euo pipefail
            for file in "$@"; do
              ${pkgs.statix}/bin/statix check "$file"
            done
          '';
          includes = [ "*.nix" ];
        };
        programs = {
          nixfmt.enable = true;
          deadnix = {
            enable = true;
            # Den dispatches by lambda argument shape, including unused names.
            no-lambda-pattern-names = true;
          };
          # Statix is a lint gate; automatic fixes can alter aspect semantics.
          statix.enable = false;
          stylua.enable = true;
          rustfmt = {
            enable = true;
            edition = "2021";
          };
        };
      };
    };
}
