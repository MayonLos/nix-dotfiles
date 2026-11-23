# Local inference

Installs a CUDA build of [llama.cpp](https://github.com/ggml-org/llama.cpp) so this laptop can run GGUF models on the discrete NVIDIA GPU instead of the CPU or a container.

The feature has no inputs. Its only output is one `home.packages` entry built with `cudaSupport = true` against the pinned `cudaPackages`, which provides `llama-cli`, `llama-server` and the other upstream binaries. Model files are user data: pass any `.gguf` path, for example `llama-cli -m ~/models/qwen.gguf -ngl 99 -cnv`. Nothing here downloads or manages models, and no service is started.

The build is the cost that shapes the placement. CUDA-enabled llama.cpp is not in any configured binary cache, so changing the nixpkgs pin rebuilds it along with the CUDA toolkit closure; the CPU default package in nixpkgs is cached and would not. The CUDA package set is narrowed to the single compute capability `8.9` of this laptop's RTX 4060: the default set compiles nine architectures (75 through 121), which multiplies nvcc time for hardware that is not here. A different GPU needs that list in `default.nix` updated. The aspect therefore stays out of `bundles/` and is selected directly by the desktop account, and a server role must not inherit it.

Running the binaries needs the NVIDIA kernel modules from the hardware feature. PRIME offload does not have to be requested for CUDA, but the GPU must be powered and visible: check with `nvidia-smi -L` before blaming the model or the build. Containers get the same GPU through `hardware.nvidia-container-toolkit` in the hardware feature, not through this aspect.

`default.nix` is the only file this feature owns. Removing the selection withdraws the packages on the next Home Manager activation; downloaded models, caches and configuration stay where the user put them.
