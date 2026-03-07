{
  lib,
  ...
}:

{
  # CUDA binary cache maintained by @NixOS/cuda-maintainers.
  nix.settings = {
    substituters = lib.mkAfter [
      "https://cache.nixos-cuda.org"
    ];
    trusted-public-keys = lib.mkAfter [
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    ];
  };

  # Keep heavyweight CUDA-enabled package builds opt-in.
  nixpkgs.config.cudaSupport = lib.mkDefault false;
}
