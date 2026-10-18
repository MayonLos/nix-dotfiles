# 自动检查与组合 fixture

检查分两层：功能内的 package/config/parser 检查通常由对应 aspect 的 `checks.nix` 提供；
跨 aspect 的隔离、共享 host provider、binding 选择和移除行为放在 `tests/composition/`，并由
`nix/checks.nix` 接入 flake。测试 fixture 是求值/构建对象，不是 inventory 中可部署的主机，
不会进入真实 `nixosConfigurations`。

当前跨功能组合入口：

| 根 check | 源文件 | 覆盖范围 |
|---|---|---|
| `checks.system-boundaries` | `composition/system.nix` | x86_64 主机策略与 ARM headless 求值 fixture；笔记本 GPU、greeter、代理、用户/秘密权限不泄漏 |
| `checks.remote-workspace-composition` | `composition/remote.nix` | x86_64 与 aarch64 远程 CLI workspace 求值；无桌面、秘密、个人授权或本地 daemon |
| `checks.protocols-composition` | `composition/protocols.nix` | 外观/默认工具的数据边界、类型与冲突负例、两绑定 palette 和固定参数 argv |
| `checks.workspace-composition` | `composition/workspace.nix` | 多 host/user 的命令行选择、共享/移除、CLI/桌面隔离和账号权限 |
| `checks.editing-composition` | `composition/editing.nix` | 编辑器与所选语言组合、数据冲突、未选择工具隔离、实际 clangd 工作负载 |
| `checks.desktop-composition` | `composition/desktop.nix` | 两 host/two user 的交互会话、palette、共享 host provider 与移除行为 |
| `checks.local-services-composition` | `composition/local-services.nix` | 本地容器/VM daemon 与远程 client 的隔离、宿主资源去重和撤销行为 |
| `checks.embedded-composition` | `composition/embedded.nix` | 嵌入式工具、权限组、udev host provider 的选择/共享/移除边界 |

根 feature checks 另有 `interactive-session-config`、`command-line-runtime`、`neovim`、
`embedded-home`、`embedded-udev`、`embedded-tools` 和 `treefmt`。这些检查验证当前锁定输入
下的生成配置、解析器、工具产物或隔离工作负载；名称以 `nix/checks.nix` 实际接线为准。

## 证据范围

`nix flake check --no-build --no-write-lock-file` 只求值 checks，不代表 derivation 构建通过。
在 x86_64-linux 构建 root checks 和 `nixosConfigurations.nixos-btw.config.system.build.toplevel`
后，才记录对应产物构建通过。ARM fixture 仅在 x86_64 checks 的求值中检查目标平台约束；`system-boundaries` 与
`remote-workspace-composition` 都会求值 aarch64 组合，但不构建 ARM 系统，也不表示存在 ARM
服务器。多 host/user fixture 只是组合输入，不输出额外可部署主机。

配置构建不会运行 HM activation、切换系统或停止旧服务。headless/parser 检查不能证明 Mango、
Noctalia、输入法、显示器、NVIDIA、音频、USB、休眠或游戏的实机行为。需要图形/设备的验收项
按应用后记录；未运行的项目保持未验证状态，不因静态检查通过标记完成。

检查实际运行结果和限制见[Den 执行记录](../docs/den-execution.md)。各批与相关产物链接在那里
更新；本文件描述检查职责，不替代当次构建日志或应用后证据。
