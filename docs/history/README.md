# 执行记录

本目录只保留这份索引，按月记录做过什么。每条的完整原文（含命令输出、截图路径、generation 与当时的“未应用”结论）在 Git 标签 `history-archive-2026-11-06` 里：

```sh
git show history-archive-2026-11-06:docs/history/<文件名>
git show history-archive-2026-11-06 --stat -- docs/history   # 列出全部原文件
```

规则：

- 这里写**过程与结论**，顶层文档写现行事实；同一事实不在两处维护。
- 新记录追加到对应月份的表格末尾：日期、做了什么、结果或证据层级（求值 / 构建 / 应用 / 实机）。需要长篇原文时写进提交说明，而不是新建文件。
- 旧记录里的 generation、store 路径、版本号与“未应用”只对应当时的提交，不代表现状。

2026-10-31 顶层文档改名对照（旧原文中的链接可能失效）：`architecture-design`→`architecture`，`workflow-design`→`keymap`，`visual-design`→`visual`，`desktop-design`→`desktop`，`application-review`→`apps`，`neovim-rebuild-execution`→`neovim`，`obsidian-handwriting`→`obsidian`。dwm/Xorg 会话已于 2026-11-05 移除。

## 2026-10

| 日期 | 内容 | 原文件 |
|---|---|---|
| 2026-10 | 全面重构计划与软件取舍 | `refactor-plan.md` |
| 2026-10 | v2 架构规范取代的旧版全文 | `architecture-design-v1.md` |
| 2026-10-18 | Den 迁移各批实施与检查 | `den-execution.md` |
| 2026-10-18 | Neovim 重构方案 | `neovim-migration-plan.md` |
| 2026-10-18 | 桌面与窗口优化 | `desktop-polish-execution.md` |
| 2026-10-18 | 系统与编辑器优化、首次自主应用 | `system-polish-execution.md` |
| 2026-10-18 | 面板、场景与 Rime | `panel-rime-execution.md` |
| 2026-10-18–19 | CLI、媒体与桌面 | `system-experience-execution.md` |
| 2026-10-19 | 移除 Hyprland | `hyprland-removal-execution.md` |
| 2026-10-19 | 目录归属与会话边界整理 | `repository-organization.md` |
| 2026-10-19–20 | 历次对话交接 | `execution-handoff.md` |
| 2026-10-20 | 可读性、面板分组与项目布局 | `optimization-2026-10-20.md` |
| 2026-10-20 | 配置审核与 DSH 接线 | `repository-audit-2026-10-20.md` |
| 2026-10-23 | 提交已应用改动、归档分支与文档 | `repository-cleanup-2026-10-23.md` |
| 2026-10-24 | 五轮仓库与系统优化：依赖、启动、桌面、内核、登录与头像 | `optimization-2026-10-24.md` |
| 2026-10-24 | 第六轮 Neovim 完全重构、构建验证与此前历史 | `neovim-rebuild-2026-10-24.md` |
| 2026-10-24 | 第七轮输入法语法模型、候选框主题与 CLI 配色 | `im-cli-polish-2026-10-24.md` |
| 2026-10-24 | 第九轮 Noctalia/Mango 标题条、视觉刻度与动效 | `desktop-polish-2026-10-24.md` |
| 2026-10-24 | 第十轮软件替换、Neovim 启动页与 Lua LSP 实测 | `software-swap-2026-10-24.md` |
| 2026-10-24 | 第八轮 v2.1 重构、B0 对照、逐文件清单与验证边界 | `architecture-v2-execution.md` |
| 2026-10-24 | CLI 视觉与配色 | `visual-cli-2026-10-24.md` |
| 2026-10-24 | Mango/Noctalia 桌面视觉 | `visual-desktop-2026-10-24.md` |
| 2026-10-24 | GTK/Qt、输入法与应用视觉 | `visual-apps-2026-10-24.md` |
| 2026-10-24 | Neovim AI 与原生能力集成 | `nvim-ai-2026-10-24.md` |
| 2026-10-25 | 视觉与 Neovim 收尾集成、性能和完整验证 | `finalize-2026-10-25.md` |
| 2026-10-25 | 第十八轮紧凑界面与下划指示 v3 | `ui-v3-2026-10-25.md` |
| 2026-10-25 | 第二十轮 Neovim 视觉对齐与启动页 | `nvim-visual-2026-10-25.md` |
| 2026-10-25 | 第二十一轮 A：桌面细节与窗口规则 | `ui-r21a-2026-10-25.md` |
| 2026-10-25 | 第二十一轮 B：GTK/Qt 与图标主题 | `ui-r21b-2026-10-25.md` |
| 2026-10-25 | 可选 dwm/Xorg 桌面（r24 前） | `xorg-before-r24-2026-10-25.md` |
| 2026-10-25 | 第二十四轮 dwm/Xorg 重写与视觉验收 | `xorg-r24-2026-10-25.md` |
| 2026-10-25 | Neovim R25 极简专注 | `nvim-minimal-2026-10-25.md` |
| 2026-10-25 | Neovim 全面改造 | `nvim-overhaul-2026-10-25.md` |
| 2026-10-25 | 第二十六轮应用、文件管理与主题 | `apps-r26-2026-10-25.md` |
| 2026-10-25 | Neovim 第二十八轮深度精修 | `nvim-r28-2026-10-25.md` |
| 2026-10-25 | Neovim r28b：DAP 与 which-key | `nvim-r28b-2026-10-25.md` |
| 2026-10-25 | Neovim r29：统一界面与普通输入补全 | `nvim-r29-2026-10-25.md` |
| 2026-10-25 | Neovim r30：原生补全交互与浮窗 | `nvim-r30-native-completion-2026-10-25.md` |
| 2026-10-25 | 顶栏 r31 一体式 One Dark | `bar-r31-unified-2026-10-25.md` |
| 2026-10-25 | WeChat IBus portal 修复 | `wechat-ime-2026-10-25.md` |
| 2026-10-25 | 第十九轮终端套件、科技版系统界面、herdr 与壁纸回退 | `ui-v4-2026-10-25.md` |
| 2026-10-26 | 全桌面整理、flake 更新与迁移 | `desktop-polish-r32.md` |
| 2026-10-26 | Thunar 紧凑样式与 SYSTEM/通知避让 | `desktop-polish-r33.md` |
| 2026-10-26 | 自主视觉巡检、中文菜单、实色浮层与应用证据 | `desktop-polish-r34.md` |
| 2026-10-30–31 | TUI 统一搜索、工具箱、删除无用工具 | `tui-r55-2026-10-31.md` |
| 2026-10-31 | 从顶层文档移出的过时状态原文 | `docs-status-cleanup-2026-10-31.md` |

## 2026-11

| 日期 | 内容 | 原文件 |
|---|---|---|
| 2026-11-03 | Neovim 接入 probe-rs DAP，STM32H562 实机调试 | `nvim-probe-rs-2026-11-03.md` |
| 2026-11-05 | 移除 dwm/Xorg 与 X11 专属组件；QQ Wayland 共享试验撤销 | `xorg-removal-2026-11-05.md` |
| 2026-11-05 | 删除 Codex 工作流、修正过时文档、包源码排除 Markdown、家目录清理 | `cleanup-2026-11-05.md` |
| 2026-11-05 | Neovim 按五个领域重写、审查与“一块画布”视觉 | `nvim-rewrite-2026-11-05.md` |
| 2026-11-06 | 软件清理（删 Codex 与 `codex-acp`、p7zip 换官方 7-Zip、xclip 移出 PATH）、防火墙改 nftables（libvirt 随之切换）、nix-daemon 改 `idle` 调度；Clash TUN VM 测试在 nftables 下通过；构建验证，未应用 | `af05492` |
| 2026-11-06 | 文档版本漂移修正、`service-policy` Docker 描述矛盾修正、执行记录合并为本索引并打标签 `history-archive-2026-11-06` | 本提交 |

## 被取代的规范全文

| 日期 | 内容 | 原文件 |
|---|---|---|
| 归档 | 旧视觉规范全文（含被取代的分层参数） | `visual-design-2026-10-30.md` |
| 归档 | 旧桌面说明全文 | `desktop-design-2026-10-30.md` |
| 归档 | 旧操作方式说明全文 | `workflow-design-2026-10-30.md` |

附带数据（同在归档标签中）：`architecture-v2-{baseline,result}.json`、`architecture-v2-files.tsv` 属于 architecture-v2-execution；`software-swap-dashboard.txt` 与 `software-swap-2026-10-24-data/` 属于 software-swap-2026-10-24。
