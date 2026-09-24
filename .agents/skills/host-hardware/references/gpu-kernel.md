# GPU 与内核

以下模块路径以 `modules/system/` 为前缀。
2026-09-24 核对：`core/boot.nix` 选 `linuxPackages_zen`；`hardware/nvidia.nix`
从 unstable 导入驱动 recipe，通过当前 `kernelPackages.callPackage` 构建。
引入原因是 stable 的旧驱动调用了新内核移除的 `strncpy` API。
版本会随 lock 改变，重新切换任一方时必须构建实际内核模块。

保留有运行时依据的设置，除非任务要求改变并有对应验证：

- PRIME **offload**，不是全时 dGPU；`nvidia-offload` 是显式选择 GPU 的入口。
- `powerManagement.finegrained = false`：此机 RTD3 teardown 曾触发关机 oops。
- `nvidiaPersistenced = true`：避免 `nv_drm_master_drop` / ReleaseOwnership 空指针路径。
- `open = true` 与 modesetting；`NVreg_PreserveVideoMemoryAllocations=1` 配合挂起恢复。
- mango 应用 profile 的 `GLVidHeapReuseRatio` 限制是显存复用 workaround。
- `legion_laptop force=1` 和 `lenovo-legion-module` 配套，此机 DMI 需 force。

检查目标版本可求值：

```sh
nix eval --raw .#nixosConfigurations.nixos-btw.config.boot.kernelPackages.kernel.version
nix eval --raw .#nixosConfigurations.nixos-btw.config.hardware.nvidia.package.version
```

这些命令不编译。涉及 ABI 的最终构建检查使用 AGENTS.md 的 toplevel build。
运行中的内核用 `uname -r`，不能把它当成待构建配置的内核版本。

Intel 视频解码依赖 `hardware/intel-video.nix` 的 `intel-media-driver` 和 `vpl-gpu-rt`。
曾观测 renderD128=NVIDIA、renderD129=i915；节点编号不是固定接口，使用
`/sys/class/drm/renderD*/device/driver` 识别后再做 VAAPI 测试。
CUDA 见 `hardware/cuda.nix` 与 `nix develop .#cuda`。
