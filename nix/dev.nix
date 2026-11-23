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
            sccache
            mold
            sops
            age
            ssh-to-age
          ];
          # sccache caches library and proc-macro crates; the final binary crate
          # is linked on every build, which is what mold covers. Incremental
          # output would store the same objects a second time.
          RUSTC_WRAPPER = "${pkgs.sccache}/bin/sccache";
          CARGO_INCREMENTAL = "0";
          # Native target only: wasm and cross builds keep their own linker.
          CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_RUSTFLAGS = "-C link-arg=-fuse-ld=mold";
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
            # Vendored mark-shot is edition 2024 and pins rustfmt 1.99.
            # This formatter is the stable 2021 toolchain and must not rewrite it.
            excludes = [ "packages/mark-shot/**" ];
          };
        };
      };
    };
}
