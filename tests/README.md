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
| `checks.protocols-composition` | `composition/protocols.nix` | 外观/默认工具的数据边界、类型与冲突负例、两绑定 palette/Kitty 动效偏好和固定参数 argv |
| `checks.workspace-composition` | `composition/workspace.nix` | 多 host/user 的命令行选择、共享/移除、CLI/桌面隔离和账号权限 |
| `checks.editing-composition` | `composition/editing.nix` | 编辑器与所选语言组合、数据冲突、未选择工具隔离、实际 clangd 工作负载 |
| `checks.desktop-composition` | `composition/desktop.nix` | 两 host/two user 的交互会话、palette、动效偏好隔离、共享 host provider 与移除行为；减少动画分支的锁定 Mango/Noctalia 解析检查 |
| `checks.local-services-composition` | `composition/local-services.nix` | 本地容器/VM daemon 与远程 client 的隔离、宿主资源去重和撤销行为 |
| `checks.embedded-composition` | `composition/embedded.nix` | 嵌入式工具、权限组、udev host provider 的选择/共享/移除边界 |

根 feature checks 另有 `hyprland-session`、`interactive-session-config`、`command-line-runtime`、`neovim`、
`embedded-home`、`embedded-udev`、`embedded-tools` 和 `treefmt`。这些检查验证当前锁定输入
下的生成配置、解析器、工具产物或隔离工作负载；名称以 `nix/checks.nix` 实际接线为准。

`checks.hyprland-session` 使用真实 Hyprland `--verify-config` 解析生成 Lua，并验证
Noctalia 会话变体、默认登录项、portal 和 target 接线；隔离 fake launcher/systemctl 验证信号转发、退出码与 target 清理，真实 Noctalia merged 导出验证 Hyprland 变体不覆盖 Mango。它不启动图形会话，不证明登录或设备表现。

`checks.neovim` 使用固定插件和临时 XDG 目录运行配置内的 headless Lua 检查：

| 脚本 | 检查范围 |
|---|---|
| `startup.lua` | 完整生产配置能启动；One Dark Darker 背景、常用命令、插件和 parser 可用；入口幂等；Snacks picker SQLite 可读写。 |
| `completion.lua` | Blink 从仓库片段目录发现真实 C++ 片段，提供补全并可展开、跳转原生 snippet 占位符。 |
| `integration.lua` | 真实 Conform/StyLua 接收生成的语言 formatter 配置并格式化隔离临时文件。 |
| `workflow.lua` | 长 Markdown 的折行、宽度变化时状态栏/标签栏不溢出、侧栏和未保存内容保护、临时草稿保存及 palette 背景。 |
| `fileops.lua` | 隔离临时目录中的重命名、buffer 更新、外部修改保护、保存钩子失败时阻止退出、目录移动，以及真实 Explorer 调用链中未保存子文件保护和回收站工具缺失场景。该脚本覆盖配置内防护逻辑，不代替用户文件上的交互验收。 |
| `lsp.lua` | 以 `nvim --clean` 启动并显式装载 LSP 配置；检查服务器设置、生成参数、诊断和并行进度处理，并运行真实 CSSLS 的临时文档诊断。 |
| `lua_workspace.lua` | 真实 LuaLS 附着临时项目、保留根探测、仅按 require 补充库，检查祖先 JSON/JSONC 配置与全局 opt-out 不被 lazydev 接管。 |

同一 derivation 还检查 reduced-motion 包分支关闭 Snacks 滚动与 Dim 动画，并检查开发 wrapper 的工作树配置覆盖和普通 wrapper 对无效覆盖路径的处理。这些是隔离 headless 检查，不代表 GUI 帧率、桌面字体观感、终端图像预览或真实项目 LSP 已验收。脚本和包接线分别见
[`config/tests/`](../aspects/editing/neovim/config/tests/) 与 [`nix/neovim.nix`](../nix/neovim.nix)。

`project-workbench` 使用临时目录和 spy 命令检查 cwd、argv、缺目录拒绝与 direnv 拒绝；
`protocols-composition` 另检查项目选择/撤销不跨用户或主机。它们不启动真实项目，不在开机
或后台运行。Neovim 旧版 `layout.lua` 专属检查已随界面重做移除；其职责现在由
`workflow.lua` 中的真实插件组合布局检查和 reduced-motion 包分支检查承接，其他 UI 组件
不再按旧手写 widget 的内部语义单独断言。

`rime-technical-runtime` 用真实 librime 编译生成的 Rime 配置，在临时用户目录验证普通中文、
专业词、错拼和英文候选可达，以及现有学习库名称仍为 `rime_ice`。它不打开个人词库，不验证
个人排名或学习持久化；曾实际拒绝错误的非递归词表组合。词表维护见
[Rime 说明](../aspects/interactive-session/rime/README.md)。

## 证据范围

`nix flake check --no-build --no-write-lock-file` 只求值 checks，不代表 derivation 构建通过。
在 x86_64-linux 构建 root checks 和 `nixosConfigurations.nixos-btw.config.system.build.toplevel`
后，才记录对应产物构建通过。ARM fixture 仅在 x86_64 checks 的求值中检查目标平台约束；`system-boundaries` 与
`remote-workspace-composition` 都会求值 aarch64 组合，但不构建 ARM 系统，也不表示存在 ARM
服务器。多 host/user fixture 只是组合输入，不输出额外可部署主机。

配置构建不会运行 HM activation、切换系统或停止旧服务。headless/parser 检查不能证明 Mango、
Noctalia、输入法、显示器、NVIDIA、音频、USB、休眠或游戏的实机行为。需要图形/设备的验收项
按应用后记录；未运行的项目保持未验证状态，不因静态检查通过标记完成。

检查实际运行结果和限制见[Den 执行记录](../docs/den-execution.md)及
[后续桌面优化记录](../docs/desktop-polish-execution.md)。本文件描述检查职责，不替代当次
构建日志或应用后证据。
