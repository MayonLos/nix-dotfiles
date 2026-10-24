# 第四轮：LTS 内核、stable NVIDIA 与 sched-ext

日期：2026-10-24。范围：`nixos-btw` 的 legion-laptop 硬件策略、组合检查和文档。
本轮只构建，不激活配置；没有执行 sudo、nixos-rebuild 或 Git stage/commit/push。

## 背景与依据

原声明使用 linux-zen 7.2.11。stable NVIDIA 595.71.05 的内核源码使用已在 Linux 7.2
移除的 `strncpy`，因此先前借用 nixpkgs-unstable 的 nvidia-x11 配方（595.104.02），
再用本机内核和 stable 依赖构建。社区同类报错见
[Nixpkgs #554125](https://github.com/NixOS/nixpkgs/issues/554125)。

锁定 stable nixpkgs 为 `da6dc0e`（完整 revision 见 `flake.lock`）：默认
`linuxPackages` 为 6.18.57，`nvidiaPackages.stable` 为 595.71.05；
`lenovo-legion-module` 可用，scx Rust schedulers 为 1.1.2。
配置依据锁定源码 `nixos/modules/services/scheduling/scx.nix` 和
`pkgs/os-specific/linux/scx/scx_rustscheds.nix`，没有更新 lock。

[Nixpkgs #555996](https://github.com/NixOS/nixpkgs/issues/555996) 将 lavd 卡顿/冻结回归
定位到 1.1.3，并记录回退至 1.1.2；[上游 #3750](https://github.com/sched-ext/scx/issues/3750)
也有 1.1.3 卡顿、1.1.2 正常的用户报告。
[PR #574970](https://github.com/NixOS/nixpkgs/pull/574970) 将 1.1.2 升至 1.1.4，
称后者修复该回归。因此已报告的这次 1.1.3 回归不涵盖当前锁定的 1.1.2；
这不证明 1.1.2 没有其他问题，也不代替本机运行验证。

[OmerFarukOruc/nixos-config #208](https://github.com/OmerFarukOruc/nixos-config/pull/208)
在另一台 AMD ROG / KWin 机器上报告：power-saver 下使用 `--autopower`，
合成器线程最坏唤醒延迟约 101 ms，固定 performance 时约 0.9 ms。
该短时单机测量支持规避 autopower；不能推断 Intel/NVIDIA + Mango 的本机延迟或收益。

## 决定与实现

- `aspects/system/legion-laptop/boot.nix` 改为 `pkgs.linuxPackages`，
  NVIDIA 使用 `config.boot.kernelPackages.nvidiaPackages.stable`；清除跨 channel 配方
  和不再使用的 `inputs` 参数。保留 open、persistenced、PRIME offload 和 Mango profile。
- stable 内核与驱动来自同一 package set，减少 API 不匹配；sched_ext 自 6.12 起可用，
  本轮由 scx 提供调度策略，不再选择 zen。保留 legion 模块、`split_lock_detect=off`、
  i915 early KMS、systemd initrd 和 Plymouth bgrt。
- `aspects/system/legion-laptop/power.nix` 启用 `services.scx`，scheduler 为
  `scx_lavd`，`extraArgs = []`。实际构建出的 1.1.2 `--help` 确认：无参数默认
  **autopilot**，按负载选择 performance/powersave/balanced，并非固定 balanced；
  `--autopower` 则跟随电源 profile。本轮保留无参数默认，不启用 autopower，
  也不固定 performance/powersave/balanced。
- 官方模块把 scx 包加入系统，unit 随 `multi-user.target` 启动，以
  `/sys/kernel/sched_ext` 目录为条件，`Restart=on-failure`，30 秒最多启动 2 次；
  `SCX_SCHEDULER=scx_lavd`、`SCX_FLAGS` 为空。构建不会启动该服务。
- `tests/composition/system.nix` 与 `nix/checks.nix` 验证真实 host 的内核 derivation
  等于 stable 默认内核、NVIDIA 等于同一 kernelPackages 的 stable 包，且 lavd 启用、
  参数不含 autopower；无头 fixture 同时断言不启用 scx，防止硬件策略泄漏。

## 验证

参数依据命令（实际运行，退出 0；帮助输出写入 stderr，故合并后截取）：

```sh
/nix/store/72q6ba4s23gn8d89kizdy146izbhyzdp-scx_full-1.1.2/bin/scx_lavd --help 2>&1 | head -60
```

`nix eval --json --no-write-lock-file .#nixosConfigurations.nixos-btw.config --apply
'c: { kernel = c.boot.kernelPackages.kernel.version; nvidia = c.hardware.nvidia.package.version;
scheduler = c.services.scx.scheduler; extraArgs = c.services.scx.extraArgs;
extraModulePackages = map (p: p.name) c.boot.extraModulePackages; }'` 实际返回：

```json
{"kernel":"6.18.57","nvidia":"595.71.05","scheduler":"scx_lavd","extraArgs":[],"extraModulePackages":["lenovo-legion-module-0.0.20-unstable-2025-07-11","nvidia-open-595.71.05-6.18.57"]}
```

实际验证命令及结果：

1. `git diff --check`、`nix fmt` 后再次 `git diff --check`：退出 0。
2. `nix flake check --no-build --no-write-lock-file`：退出 0，全部求值通过。
   仅有既有 `unknown flake output 'denful'` 警告；求值本身不证明构建或运行成功。
3. 构建全部 `checks.x86_64-linux` 和 toplevel，以下命令退出 0 并打印 19 个输出路径
   （18 项 checks + 系统）：

   ```sh
   nix build --no-link --no-write-lock-file --print-out-paths --impure --expr \
     'let f = builtins.getFlake (toString ./.); in builtins.attrValues f.checks.x86_64-linux ++ [ f.nixosConfigurations.nixos-btw.config.system.build.toplevel ]'
   ```

   其中 `system-boundaries` 的 `stableDefaultKernel`、`matchingStableNvidia`、
   `lavdWithoutAutopower` 均为 true，产物为
   `/nix/store/5kfnhm0w5bk36r6q82793mzj0ix16f4z-den-system-boundaries.json`。
   内核、legion 和 NVIDIA 模块使用二进制缓存，系统模块集合、initrd 和 toplevel
   成功构建；没有把缓存取得描述为本机源码重新编译。
4. 再以真实 Git flake 入口执行
   `nix build --no-link --no-write-lock-file --print-out-paths .#nixosConfigurations.nixos-btw.config.system.build.toplevel`，
   退出 0，路径与上述结果一致：

   ```text
   /nix/store/b62ckg0pnj6s2fd6bf4fmf9iwwnr6l24-nixos-system-nixos-btw-26.05.20261021.da6dc0e
   ```

5. `nix build --no-link --no-write-lock-file --print-out-paths .#nixosConfigurations.nixos-btw.config.boot.kernelPackages.kernel.configfile`：
   退出 0。产物
   `/nix/store/6p7i4nkc80krhk9f4a4cz7prqji5a3lb-linux-config-6.18.57`
   确认 `CONFIG_SCHED_CLASS_EXT=y`、`CONFIG_DEBUG_INFO_BTF=y`，
   `CONFIG_DRM_I915=m`、`CONFIG_IWLWIFI=m`、`CONFIG_IWLMVM=m`。
   `modinfo -F vermagic` 对 legion-laptop.ko 与 nvidia.ko.xz 均返回
   `6.18.57 SMP preempt mod_unload`。求值确认 initrd 模块为 `dm_mod`、`i915`，
   保留 `split_lock_detect=off` 与 Plymouth；实际 initrd 构建成功。
   以上证明配置和构建产物兼容，不证明真实硬件已加载或启动成功。
6. 检查新 toplevel 的 `etc/systemd/system/scx.service`，确认 scheduler、空参数、
   目录条件、重启策略和 multi-user wants 与锁定模块一致。
7. 修改文档的本地相对链接检查通过；独立 reviewer 只读复核未发现阻断问题。
   本文件按任务要求新增并保持未 stage；Git flake 不包含该未跟踪文档，
   本文件链接与内容单独核验。另以 `git status --short --ignored` 确认未发现忽略文件，
   没有使用 `path:.` 或引入运行时秘密。

## Closure 摘要

`nix store diff-closures /run/current-system /nix/store/b62ckg0pnj6s2fd6bf4fmf9iwwnr6l24-nixos-system-nixos-btw-26.05.20261021.da6dc0e`
实际退出 0。对比基线为
`/nix/store/7znxsgz6hldwy7n3521lhcim4991jsz1-nixos-system-nixos-btw-26.05.20261021.da6dc0e`，
这是运行系统的 closure，不据此推断当前正在运行的内核版本。

| 项目 | 基线 → 新产物 |
|---|---|
| 内核 / initrd | linux-zen 7.2.11 → linux 6.18.57 |
| NVIDIA open 模块 | 595.104.02-7.2.11 → 595.71.05-6.18.57 |
| NVIDIA 用户态 / persistenced / settings | 595.104.02 → 595.71.05 |
| scx | 新增 scx_full / scx_rustscheds 1.1.2、scx_cscheds 0-unstable-2026-01-13、unit-scx.service |
| 总 closure NAR 大小 | 65,890,199,504 → 66,123,743,664 字节；增加 233,544,160 字节，约 222.7 MiB |

总大小由 `nix path-info --json --closure-size` 核验。diff-closures 显示 Rust schedulers
新增约 212.8 MiB、C schedulers 约 6.1 MiB；完整 scx 包是锁定 NixOS 模块的默认选择。
这些是 store 产物变化，不是运行时内存或性能测量。

## 回退与实机验收

若后续应用并重启后出现启动、驱动或调度问题，可在开机 systemd-boot 菜单选择上一代。
当前菜单超时 1 秒，可在启动时按住 Space 显示菜单；不清理旧 generation。
源码回退可恢复 `boot.kernelPackages = pkgs.linuxPackages_zen`，并同时在 nvidia.nix
恢复 `inputs` 参数及下面的旧配方，然后重新求值、构建，再由有授权者应用：

```nix
package =
  (config.boot.kernelPackages.callPackage (
    inputs.nixpkgs-unstable + "/pkgs/os-specific/linux/nvidia-x11"
  ) { }).stable;
```

若只需撤回 sched-ext，可关闭 `services.scx.enable`；回退源码时还须同步调整本轮新增的
策略断言，避免预期不同而失败。以上是回退方法，本轮没有执行应用或回退操作。

重启后待验：`uname -r`、`nvidia-smi` 与 PRIME offload、`legion_laptop` 模块加载、
CNVi Wi-Fi/以太网、i915/Plymouth 启动画面、`systemctl status scx`、
`cat /sys/kernel/sched_ext/state` 与当前调度器名称，以及不同供电/profile 下的指针、
窗口交互和休眠恢复。尚无同条件性能/续航测量，不宣称交互或功耗已经改善。

## 重启后实机验证（2026-10-24 18:11 启动）

- `uname -r` = 6.18.57；`nvidia-smi` 识别 RTX 4060 Laptop，驱动 595.71.05。
- `/sys/kernel/sched_ext/state` = enabled，ops = `lavd_1.1.2`；`scx.service` active；legion 模块已加载；Wi-Fi 已连接。
- Plymouth 启动服务已运行；无失败的系统/用户单元。
- loader 阶段仍为 5.7s：EFI 变量 `LoaderConfigTimeout` = 5 覆盖了 `loader.conf` 的 `timeout 1`。已用 `bootctl set-timeout ''` 清除，下次启动生效（未再次重启验证）。
