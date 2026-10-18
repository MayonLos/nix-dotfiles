# STM32 / Cortex-M 完整功能

`default.nix` 注册 `den.aspects.embedded-workbench`。在某个 `user@host` 绑定的 `includes` 中选择一次，即配置该账号的工具、`dialout` 串口组和目标宿主的探针规则。

| 文件 | 职责 |
|---|---|
| `default.nix` | 完整 Den 入口，明确投递 HM、user 和定向宿主支持 |
| `home.nix` | ARM GCC/GDB、OpenOCD、ST-Link、probe-rs、DFU/UART、CubeMX、CubeProgrammer、tio |
| `host.nix`、`rules.nix` | OpenOCD 规则、收紧权限后的 ST-Link 规则及 STM32 DFU `0483:df11` 的 uaccess 规则 |
| `package.nix` | 固定版本的 CubeProgrammer GUI/CLI 配方，保留原有 FHS 和启动适配 |
| `checks.nix` | 最终规则权限/别名与工具运行检查，由测试组合显式传入 profile 和规则 |

完整入口另提供 CMake、Ninja、pkg-config、host GDB，显式补上旧布局依赖 `llvm.nix` 的公共工具；不会顺带选择整个 LLVM 或 Zsh 功能。ARM 工具链保留 `lowPrio`，让 host GDB 的同名数据文件优先；两个 GDB 仍使用各自的 store 数据目录。项目 flake 继续拥有项目版本，不修改项目文件。

共享宿主支持是具名的 `embedded-host-support` aspect，通过 `provides.${host.name}.includes` 引用，多个账号选择时只贡献一次规则。不要将它改成参数化功能内联的重复 class 输出。

授权边界：此 aspect 只向选择者授予 `dialout`；不撤销其他配置已经授予的组。匹配 USB 探针由 logind 给当前活动的本地 seat 用户动态 ACL；OpenOCD 上游规则还包含 `plugdev`，此功能不创建或授权这个组。未选择功能的本地用户仍可能通过活动 seat 获得探针访问，不能称为按绑定隔离 USB。当前不增加 probe-rs 自带的更广规则清单，也不承诺所有 probe-rs 设备或无 seat 的远程使用都可免 sudo。[probe-rs 官方设置说明](https://probe.rs/docs/getting-started/probe-setup/)也将 udev 作为 Linux 普通用户访问的前提。

本次核验发现旧注释不符合实际产物：锁定的 ST-Link 1.8 规则是 `MODE:="0666"`，既没有 uaccess，又因 `:=` 最终赋值不能被后续 OpenOCD 的 mode 覆盖。`rules.nix` 将这四份规则改为 `MODE:="0660", TAG+="uaccess"`，保留所有设备别名；仅规则包经过转换，工具二进制不变。这个权限修正同时经兼容入口进入现有笔记本的下一次构建，切换系统后才生效。测试检查最终规则的 mode/tag 与原有别名，不再仅以包的存在推断权限。上游更新导致原匹配不再成立时，转换会明确构建失败，需重新核对。

当前验证平台为 x86_64-linux，CubeProgrammer 配方也仅支持该平台。调用方需允许所选的非自由软件；官方安装 ZIP 仍按原有固定 hash 预置，不自动下载不同版本。生成项目、固件、应用偏好和设备状态不归此功能删除；移除选择只撤销该绑定的声明，共享宿主规则在最后一个使用者移除后消失。

主 flake 尚未引入 Den。现有 HM、hardware 和 pkgs 路径暂为兼容入口，引用本目录原实现；`mayon` 的旧账号模块仍保留原有 `dialout`，没有双重启用 Den。新入口目前由 [测试子 flake](../../tests/den/README.md)直接引用和验证。

已验证组合隔离、规则去重、实际 HM/udev 构建、ARM 目标编译、两个 GDB 及几个 CLI 的无设备启动。没有切换系统、执行 activation、启动 GUI、验证设备 ACL 或烧写开发板。
