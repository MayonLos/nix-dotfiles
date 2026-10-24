# STM32 / Cortex-M 完整功能

`default.nix` 注册 `den.aspects.embedded-workbench`。在 `user@host` binding 的 `includes` 中
选择一次，即为该账号配置工具和 `dialout` 组，并通过具名 provider 给目标宿主贡献探针规则。
多个账号共用 host support 时规则只加入一次。

| 文件 | 职责 |
|---|---|
| `default.nix` | 完整 Den aspect 与定向 host provider |
| `home.nix` | ARM GCC/GDB、OpenOCD、ST-Link、probe-rs、DFU/UART、CubeMX、CubeProgrammer、tio |
| `host.nix`、`rules.nix` | OpenOCD/ST-Link 权限规则、空 `plugdev` 组与 STM32 DFU `0483:df11` uaccess 规则 |
| `package.nix` | 固定版本 CubeProgrammer GUI/CLI 配方及 FHS/启动适配 |
| `checks.nix` | 最终规则权限/别名与工具运行检查 |

入口显式提供 CMake、Ninja、pkg-config 和 host GDB，不依赖旧布局的隐式 LLVM 模块，也不安装
整套 LLVM。ARM 工具链保留 `lowPrio`，让 host GDB 的同名数据文件优先；两个 GDB 使用各自的
store 数据目录。项目 flake 继续拥有项目版本，不修改项目文件。

host support 是具名 `embedded-host-support` aspect，通过
`provides.${host.name}.includes` 去重；不要改成每个用户重复输出宿主模块。该 aspect 只向选择者
授予 `dialout`，不撤销其他配置授予的组。匹配 USB 探针由 logind 给当前活动本地 seat 用户动态
ACL；OpenOCD 上游规则还引用 `plugdev`，本功能声明该组仅让规则可解析，不添加任何成员，设备
访问仍由 `uaccess` 提供。未选择者也可能经活动 seat
获得访问，不能称为按 binding 隔离 USB；也不承诺所有 probe-rs 设备或无 seat 远程使用免 sudo。
[probe-rs 官方设置说明](https://probe.rs/docs/getting-started/probe-setup/)同样将 udev 规则列为
Linux 普通用户访问设备的前提。

当前 ST-Link 1.8 锁定规则原为 `MODE:="0666"`，既没有 uaccess，又因 `:=` 最终赋值无法由后续
OpenOCD mode 覆盖。`rules.nix` 将四份规则改成 `MODE:="0660", TAG+="uaccess"` 并保留设备
别名；若上游规则变化导致转换失效，构建会失败，需重新核对。仅规则包被转换，工具二进制不变。

根检查 `checks.embedded-composition` 覆盖选择隔离、共享 host provider 去重、权限和移除行为；
`checks.embedded-home`、`checks.embedded-udev`、`checks.embedded-tools` 检查实际 HM、规则与
工具产物。现有 x86_64-linux 构建不等于真实设备 ACL、GUI 或烧写验证；CubeProgrammer 配方仅
支持 x86_64-linux，且调用方需允许非自由软件。旧测试子 flake 已删除，实际检查位于根
`tests/composition/embedded.nix` 与本目录 `checks.nix`。

移除 aspect 只撤销声明，不清理生成项目、固件、应用偏好或设备状态。没有切换系统或执行
activation；硬件 ACL/设备使用需要应用配置后实测。每批记录见[执行记录](../../docs/history/den-execution.md)。
