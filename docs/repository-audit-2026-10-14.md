# 仓库审核：2026-10-14

本轮在既有 flake 升级、Antigravity 移除和桌面插件安装之后，对仓库做静态审查、资料核对、清理及相关运行验证。保留开始时已有改动，没有提交或推送。

## 已确认并处理的发现

| 位置 | 证据及处理 |
|---|---|
| `nixvim/plugins/appearance/lua/math_preview.lua` | 原异步回调只检查当前 buffer，公式 A 晚于公式 B 完成时可能覆盖 B。增加请求代次，光标变化、文本变化、关闭与离开窗口时使旧请求失效；正常结果与错误结果都经过检查。 |
| `aspects/file-manager/thunar-actions.nix` | 图像转换或剪贴板读取失败时，原临时文件没有统一退出清理。两条操作补上 EXIT trap，失败注入验证无残留。 |
| `aspects/ai-workbench/ai-agents.nix` | 旧 Codex 包布局限制已被锁定 llm-agents 源码修复。原包 0.162.1 在隔离配置目录冷启动共享 daemon，`packages/app-server-daemon/current` 指向 Nix store，未下载 release。移除强制 `--no-daemon` 包装；保留仍有依据的 dsh 与 OpenCode 包装。 |
| `aspects/languages/support.nix`、`python.nix` | nvim-dap 已移除，仓库没有剩余 CodeLLDB/debugpy 消费配置。移除这两项全局依赖，保留 IPython、语言工具链与 GDB；同步开发技能说明。 |
| `aspects/interactive-session/noctalia.nix` | 已启用的 OCR 和 DeepSeek balance 插件没有配置 bar/control-center 入口，且没有 service/launcher 入口。移除这两个闲置插件；原生 Print OCR 快捷键保留，用户运行时数据未删除。 |
| 同上 | 未安装 Cava，但启用了 Cava 主题模板。删除模板，保留 Noctalia 原生 PipeWire 频谱。 |
| 同上 | 空 calculator `prefix` 实际恢复默认 `calc`，不是禁用开关。删去无效字段并纠正说明；calculator-plus 插件已移除，内置计算器不参与普通搜索，但显式 `/calc` 仍可用。 |
| `README.md`、`inventory/hosts/nixos-btw/facts.nix`、技能索引 | 修正 Noctalia 状态文件路径、Mango 配色输出文件名、fcitx 重启指引、libtexprintf 包名，补上共享本地模型清单索引。 |

同时压缩了 Noctalia、AI 工具及字体配置中的旧版本流水和已失效注释，保留输入 pin、只读配置、运行时覆盖层和仍需保留的 workaround 理由。

## 桌面美化

保留 Tokyo Night 配色与胶囊分组：全局阴影透明度 0.55 → 0.30，状态栏高度 30 → 32，端部边距 10 → 14，组间间距 6 → 8。媒体标题最大长度设为 180，悬停时滚动，减少播放长标题时挤占空间。Bongo Cat 和原生频谱仍在原来的时钟、媒体分组。

这些字段已核对锁定 Noctalia 5.2.1 源码与官方 [状态栏文档](https://docs.noctalia.dev/noctalia/bar/)、[媒体 widget 文档](https://docs.noctalia.dev/noctalia/bar/widgets/media/) 和 [原生频谱文档](https://docs.noctalia.dev/noctalia/bar/widgets/audio-visualizer/)。运行时合并配置和截图确认新布局已生效，两个 Bongo evtest 输入读取进程均在运行。

## 审核覆盖

| 范围 | 实际检查 |
|---|---|
| flake、主机入口、共享 lib、自定义包 | 输入接线与 follows 约束、递归模块导入、通道选择、共享模型及工具链消费者、包表达式位置与构建接线。 |
| 系统模块 | 内核/NVIDIA/Intel、网络与代理、音频、输入设备、虚拟化、游戏栈、电源、桌面会话、Nix 和 sops 的配置与理由。 |
| Home Manager | shell/终端、开发工具与 AI CLI、IDE、主题/MIME/输入法、媒体/通信应用、Firefox helper、截图/OCR、Thunar、Yazi 与桌面服务。 |
| Neovim | 模块导入、惰性触发、工具 PATH、LSP/格式化、AI、编辑/导航/Git/外观与 Lua helper；定点修复公式预览竞态。 |
| 文档与技能 | 本地链接、配置路径、共享 helper 索引、移除记录和当前源码一致性。 |

人工审查和原生子代理分别承担上述范围；全仓格式/静态检查及 NixOS 求值覆盖声明式模块。没有把硬件、代理、秘密、手动应用数据或有明确用途的包当作无用配置删除。JetBrains、dsh 等其他 workaround 没有获得足够的删除证据，继续保留。

资料核对还包括官方 [Noctalia 配置优先级说明](https://docs.noctalia.dev/noctalia/configuration/)、[debugpy 文档](https://github.com/microsoft/debugpy)、[sops-nix 运行时模板说明](https://github.com/Mic92/sops-nix) 和 [Codex CLI 命令参考](https://learn.chatgpt.com/docs/developer-commands?surface=cli)。发行版包装行为以当前锁定 llm-agents 源码及实际启动结果为准。

## 验证结果

- `git diff --check` 通过，本地 Markdown 链接检查通过。
- `nix flake check --no-build --no-write-lock-file` 通过。
- `checks.x86_64-linux.treefmt` 构建通过，包含 nixfmt、deadnix、statix。
- NixOS toplevel 构建通过，`nixos-rebuild switch` 成功。当前系统为 `/nix/store/i5jl4jfk5x2lrkjmb1plj1yy62x87cr9-nixos-system-nixos-btw-26.05.20261012.7993f34`。
- Noctalia 生成配置校验通过，重载成功；合并配置确认边距、间距、阴影和插件清理实际生效。
- 新构建的 Neovim headless 启动与 `math_preview.setup()` 通过；Lua mock 覆盖回调逆序、离开数学内容、切换 buffer、陈旧/当前错误、正常结果和缓存命中。
- Thunar 实际构建脚本的图像转换失败、剪贴板读取失败注入测试通过，没有残留临时文件；测试没有写入用户剪贴板。
- 新 Python 环境可导入 IPython，未包含全局 debugpy。
- Home Manager 单元 active，系统与用户 failed unit 列表为空。当前运行内核为 7.2.9-zen1，Mango 报告 0.18.0。

构建途中缓存连接出现 TLS/超时重试，最终构建成功。Noctalia 校验另有未启用第三方插件的 setting 同名告警，未影响配置校验。

## 外部审核和边界

用户指定的 OpenCode DS4.1F、Grok 调用在隔离 worktree、只读权限下执行。DS4.1F 首次返回 HTTP 402（余额不足），同模型 OpenCode Go 通道单次重试 600 秒后超时，没有最终报告。Grok 返回 `invalid_grant`，OAuth refresh token 无效，没有模型报告。原生子代理的独立发现与这两次外部调用严格区分，没有冒称外部审核通过。

没有逐个启动全部 GUI/IDE，也未测试多显示器、探针刷写、实际音乐播放时的频谱或真实终端图形协议下的公式预览。对这些部分，构建成功和静态检查不能替代完整运行验证。所有已修复代码路径的验证范围如上。
