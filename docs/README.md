# 文档索引

顶层文档描述当前设计、边界和用法；`history/` 保存各轮实施、应用和审核记录。历史记录中的
generation、store 路径和样本数据只对应当时提交，与当前源码或 `flake.lock` 矛盾时以后者为准。

## 当前

| 文档 | 内容 |
|---|---|
| [architecture-design.md](architecture-design.md) | Den 实体、aspect/bundle/inventory 边界 |
| [config-ownership.md](config-ownership.md) | 配置文件、可变状态与秘密的写入归属 |
| [service-policy.md](service-policy.md) | 后台服务的 session 边界与所有权 |
| [workflow-design.md](workflow-design.md) | 快捷键、tmux、项目工作台与长任务 |
| [desktop-design.md](desktop-design.md) | Mango + Noctalia 的 One Dark Darker 视觉 |
| [xorg-desktop-execution.md](xorg-desktop-execution.md) | 可选 dwm/Xorg 会话的入口、服务与待验项 |
| [dwm-visual-design.md](dwm-visual-design.md) | dwm 视觉与窗口规则 |
| [neovim-rebuild-execution.md](neovim-rebuild-execution.md) | Neovim 当前设计与验证 |
| [application-review.md](application-review.md) | 保留软件逐项评估 |
| [dsh.md](dsh.md) | DeepSeek Harness 命令与桌面入口 |
| [grok-bot.md](grok-bot.md) | Grok Bot 打包与限制 |
| [obsidian-handwriting.md](obsidian-handwriting.md) | Obsidian 手写与插件 |
| [server-plan.md](server-plan.md) | 未来服务器的复用边界（尚无真实主机） |

## 历史记录

| 文档 | 日期 | 内容 |
|---|---|---|
| [refactor-plan.md](history/refactor-plan.md) | 2026-10 | 全面重构计划与软件取舍 |
| [den-execution.md](history/den-execution.md) | 2026-10-18 | Den 迁移各批实施与检查 |
| [neovim-migration-plan.md](history/neovim-migration-plan.md) | 2026-10-18 | Neovim 重构方案 |
| [desktop-polish-execution.md](history/desktop-polish-execution.md) | 2026-10-18 | 桌面与窗口优化 |
| [system-polish-execution.md](history/system-polish-execution.md) | 2026-10-18 | 系统与编辑器优化、首次自主应用 |
| [panel-rime-execution.md](history/panel-rime-execution.md) | 2026-10-18 | 面板、场景与 Rime |
| [system-experience-execution.md](history/system-experience-execution.md) | 2026-10-18–19 | CLI、媒体与桌面 |
| [hyprland-removal-execution.md](history/hyprland-removal-execution.md) | 2026-10-19 | 移除 Hyprland |
| [repository-organization.md](history/repository-organization.md) | 2026-10-19 | 目录归属与会话边界整理 |
| [optimization-2026-10-20.md](history/optimization-2026-10-20.md) | 2026-10-20 | 可读性、面板分组与项目布局 |
| [repository-audit-2026-10-20.md](history/repository-audit-2026-10-20.md) | 2026-10-20 | 配置审核与 DSH 接线 |
| [execution-handoff.md](history/execution-handoff.md) | 2026-10-19–20 | 历次对话交接 |
| [repository-cleanup-2026-10-23.md](history/repository-cleanup-2026-10-23.md) | 2026-10-23 | 提交已应用改动、归档分支与文档 |
| [optimization-2026-10-24.md](history/optimization-2026-10-24.md) | 2026-10-24 | 项目入口清理、空 plugdev 组、输入去重与更新 |
| [boot-wallpaper-2026-10-24.md](history/boot-wallpaper-2026-10-24.md) | 2026-10-24 | systemd initrd、Plymouth、TTY 与冷色调壁纸轮换 |
| [fonts-icons-atuin-2026-10-24.md](history/fonts-icons-atuin-2026-10-24.md) | 2026-10-24 | Maple / Inter、蓝色 Papirus、Classic 指针与本地 atuin |
| [kernel-scx-2026-10-24.md](history/kernel-scx-2026-10-24.md) | 2026-10-24 | LTS 内核、同源 stable NVIDIA 与 scx_lavd 默认调度 |
