{ pkgs }:
# This host has an RTX 4060 (Ada, compute capability 8.9).
# Avoid compiling kernels for unrelated GPUs and exhausting desktop memory.
(pkgs.llama-cpp.override { cudaSupport = true; }).overrideAttrs (old: {
  cmakeFlags =
    builtins.filter (flag: !(pkgs.lib.hasPrefix "-DCMAKE_CUDA_ARCHITECTURES" flag)) old.cmakeFlags
    ++ [ "-DCMAKE_CUDA_ARCHITECTURES=89" ];
  enableParallelBuilding = true;
  preBuild = (old.preBuild or "") + ''
    export NIX_BUILD_CORES=2
  '';
})
