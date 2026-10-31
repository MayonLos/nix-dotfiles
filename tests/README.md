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
| `checks.desktop-composition` | `composition/desktop.nix` | 两 host/two user 的 Mango 与独立 Xorg 选择、共享支持、未选绑定隔离与移除行为；palette/动效偏好及减少动画分支的锁定 Mango/Noctalia 解析检查 |
| `checks.local-services-composition` | `composition/local-services.nix` | 本地容器/VM daemon 与远程 client 的隔离、宿主资源去重和撤销行为 |
| `checks.embedded-composition` | `composition/embedded.nix` | 嵌入式工具、权限组、udev host provider 的选择/共享/移除边界 |

根 flake 还导出以下功能与运行 checks；实现分布在 `nix/` 的 flake-parts 模块、对应
aspect 和嵌入式组合 fixture 中：

| 根 check | 实现入口 | 覆盖范围 |
|---|---|---|
| `checks.project-workbench` | `aspects/workspace/project-workbench/checks.nix` | 临时项目目录中的 cwd、argv、缺目录与 direnv 拒绝 |
| `checks.interactive-session-config` | `aspects/desktop/mango-session/checks.nix` | 主机与 Home Manager 交互会话生成配置检查 |
| `checks.rime-technical-runtime` | `aspects/desktop/session-support/rime-checks.nix` | 见下方 Rime 运行检查说明 |
| `checks.xorg-session-runtime` | `aspects/desktop/xorg-session/checks.nix` | 见下方 Xorg/dmenu 隔离运行检查说明 |
| `checks.command-line-runtime` | `aspects/cli/shell/checks.nix` | 生成的命令行配置、解析器及工具运行检查 |
| `checks.neovim` | `nix/outputs.nix` | 见下方 Neovim headless 检查说明 |
| `checks.embedded-home`, `checks.embedded-udev`, `checks.embedded-tools` | `tests/composition/embedded.nix` 与 `aspects/dev/embedded/checks.nix` | 嵌入式 Home Manager、udev 规则和工具产物检查 |
| `checks.treefmt` | `nix/default.nix` 导入 `treefmt-nix.flakeModule`；工具配置在 `nix/dev.nix` | nixfmt、deadnix、statix 与 stylua |

根检查键由 `nix/checks.nix`、`treefmt-nix.flakeModule` 在
`nix/default.nix` 中共同导出；上表列出对应实现入口，不把所有输出归到单个文件。

`checks.neovim` 使用固定插件和临时 XDG 目录运行配置内的 headless Lua 检查：

| 脚本 | 检查范围 |
|---|---|
| `startup.lua` | 完整生产配置能启动；One Dark 背景、常用命令、插件和 parser 可用；入口幂等；Snacks picker SQLite 可读写。 |
| `completion.lua` | Blink 从仓库片段目录发现真实 C++ 片段，提供补全并可展开、跳转原生 snippet 占位符。 |
| `integration.lua` | 真实 Conform/StyLua 接收生成的语言 formatter 配置并格式化隔离临时文件。 |
| `workflow.lua` | 长 Markdown 的折行、宽度变化时状态栏/标签栏不溢出、侧栏和未保存内容保护、临时草稿保存及 palette 背景。 |
| `fileops.lua` | 隔离临时目录中的重命名、buffer 更新、外部修改保护、保存钩子失败时阻止退出、目录移动，以及真实 Explorer 调用链中未保存子文件保护和回收站工具缺失场景。该脚本覆盖配置内防护逻辑，不代替用户文件上的交互验收。 |
| `lsp.lua` | 以 `nvim --clean` 启动并显式装载 LSP 配置；检查服务器设置、生成参数、诊断和并行进度处理，并运行真实 CSSLS 的临时文档诊断。 |
| `lua_workspace.lua` | 真实 LuaLS 附着临时项目、保留根探测、仅按 require 补充库，检查祖先 JSON/JSONC 配置与全局 opt-out 不被 lazydev 接管。 |

同一 derivation 还检查 reduced-motion 包分支关闭 Snacks 滚动与 Dim 动画，并检查开发 wrapper 的工作树配置覆盖和普通 wrapper 对无效覆盖路径的处理。这些是隔离 headless 检查，不代表 GUI 帧率、桌面字体观感、终端图像预览或真实项目 LSP 已验收。脚本和包接线分别见
[`config/tests/`](../aspects/dev/neovim/config/tests/) 与 [`nix/outputs.nix`](../nix/outputs.nix)。

`project-workbench` 使用临时目录和 spy 命令检查 cwd、argv、缺目录拒绝与 direnv 拒绝；
`protocols-composition` 另检查项目选择/撤销不跨用户或主机。它们不启动真实项目，不在开机
或后台运行。Neovim 旧版 `layout.lua` 专属检查已随界面重做移除；其职责现在由
`workflow.lua` 中的真实插件组合布局检查和 reduced-motion 包分支检查承接，其他 UI 组件
不再按旧手写 widget 的内部语义单独断言。

`rime-technical-runtime` 用真实 librime 编译生成的 Rime 配置，在临时用户目录验证普通中文、
专业词、错拼和英文候选可达，以及现有学习库名称仍为 `rime_ice`。它不打开个人词库，不验证
个人排名或学习持久化；曾实际拒绝错误的非递归词表组合。词表维护见
[Rime 说明](../aspects/desktop/session-support/rime/README.md)。

`xorg-session-runtime` 在 Xvfb 中运行实际 dwm 与生产 launcher/menu：它用隔离的 `.desktop`
条目检查 j4+dmenu 的选择与 `Exec` 参数，用 Escape 检查生产桌面菜单可取消，并提交任意输入
确认其不会被当作命令执行。该检查覆盖隔离 X11/XRender 冒烟行为，不代表真实 Xorg、GLX、PAM
或原生窗口捕获验收。

## 证据范围

`nix flake check --no-build --no-write-lock-file` 只求值 checks，不代表 derivation 构建通过。
在 x86_64-linux 构建 root checks 和 `nixosConfigurations.nixos-btw.config.system.build.toplevel`
后，才记录对应产物构建通过。ARM fixture 仅在 x86_64 checks 的求值中检查目标平台约束；`system-boundaries` 与
`remote-workspace-composition` 都会求值 aarch64 组合，但不构建 ARM 系统，也不表示存在 ARM
服务器。多 host/user fixture 只是组合输入，不输出额外可部署主机。

配置构建不会运行 HM activation、切换系统或停止旧服务。headless/parser 检查不能证明 Mango、
Noctalia、输入法、显示器、NVIDIA、音频、USB、休眠或游戏的实机行为。需要图形/设备的验收项
按应用后记录；未运行的项目保持未验证状态，不因静态检查通过标记完成。

检查实际运行结果和限制见[Den 执行记录](../docs/history/den-execution.md)及
[后续桌面优化记录](../docs/history/desktop-polish-execution.md)。本文件描述检查职责，不替代当次
构建日志或应用后证据。

## v2.1 求值与源码边界

`nix/checks.nix` 显式登记各功能公开 `checks.nix`，统一传入真实 `nixos`、`home`、
`appearance`、`pkgs`、`lib`、`system`，不会再次实例化真实主机。跨功能 fixture 只通过
公开入口、契约和测试钩子组合，隔离的 fixture 不是可部署 inventory。

`architecture` 在求值时执行，内置负例证明各规则会拒绝违规；`statix` 只检查，
`deadnix` 带 `--no-lambda-pattern-names`。检查结果必须区分求值、构建和应用。

`tests/docs/` 由 `checks.docs` 运行，校验 `docs/` 顶层文档的 front matter、路由表登记和本地链接。
