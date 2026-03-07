{ pkgs ? import <nixpkgs> { config.allowUnfree = true; } }:

let
  cudaPkgs = pkgs.cudaPackages;
in
pkgs.mkShell {
  name = "cuda-dev-shell";

  packages = with pkgs; [
    git
    gnumake
    cmake
    pkg-config
    python3
  ] ++ (with cudaPkgs; [
    cudatoolkit
    cuda_nvcc
    cudnn
  ]);

  shellHook = ''
    export CUDA_PATH="${cudaPkgs.cudatoolkit}"
    export CUDA_HOME="$CUDA_PATH"
    export CUDNN_PATH="${cudaPkgs.cudnn}"
    base_ld_path="${cudaPkgs.cudatoolkit}/lib:${cudaPkgs.cudatoolkit}/lib64:${cudaPkgs.cudnn}/lib"
    if [ -n "$LD_LIBRARY_PATH" ]; then
      export LD_LIBRARY_PATH="$base_ld_path:$LD_LIBRARY_PATH"
    else
      export LD_LIBRARY_PATH="$base_ld_path"
    fi
    echo "CUDA dev shell ready."
    echo "Tip: for hybrid graphics, run GPU commands via: nvidia-offload <cmd>"
  '';
}
