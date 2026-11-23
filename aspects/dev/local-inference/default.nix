_: {
  den.aspects.local-inference.homeManager =
    { pkgs, ... }:
    let
      # This laptop's RTX 4060 is sm_89. The default CUDA set compiles nine
      # architectures (75 through 121), multiplying nvcc time for GPUs that are
      # not present here.
      cudaPackages = pkgs.cudaPackages.override {
        config = pkgs.config // {
          cudaCapabilities = [ "8.9" ];
        };
      };

      llamaCpp = pkgs.llama-cpp.override {
        cudaSupport = true;
        inherit cudaPackages;
      };
    in
    {
      # A CUDA build is absent from every binary cache, so each nixpkgs pin
      # change rebuilds llama.cpp on this machine. That cost is why the aspect
      # is selected by this laptop account instead of joining a shared bundle.
      home.packages = [ llamaCpp ];
    };
}
