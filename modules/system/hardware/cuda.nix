{ pkgs, lib, ... }:
{
  nix.settings = {
    substituters = lib.mkAfter [
      "https://cache.nixos-cuda.org"
    ];
    trusted-public-keys = lib.mkAfter [
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    ];
  };

  environment.systemPackages = with pkgs.cudaPackages; [
    cudatoolkit
    cudnn
    cuda_nvcc
  ];

  environment.variables.CUDA_PATH = "${pkgs.cudaPackages.cudatoolkit}";
}
