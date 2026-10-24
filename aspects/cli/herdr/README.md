# herdr

`herdr` 是独立的 AI agent 终端工作区管理器，接收 `user.appearance`；engineering-workbench 选择本功能。`pkgs.local.herdr` 是 llm-agents 锁定 0.9.5 的原始 derivation 别名，本功能只在局部 override 中叠加标签下划线补丁。

tmux 继续负责通用终端复用、既有 session、pane 与快捷键；herdr 为多 agent / 多项目提供自己的工作区、检测与终端，不嵌入或替换 tmux，不改 tmux keymap。Mango `Super+Alt+H` 启动 `herdr-terminal`，启动器中同名 **herdr** desktop 入口打开独立 Kitty 窗口（`mayon-herdr`）。CLI 可直接运行 `herdr`。没有登录自启服务；server 由用户启动的 herdr 按上游生命周期管理。

唯一配置 writer 是 `home.nix`，生成 `~/.config/herdr/config.toml`：固定 One Dark，自定义所有 0.9.5 theme color tokens 来自共享 palette；底部标签、原生细分隔 pane、符号状态读数。关闭会写回配置的首次 onboarding；不要用 GUI 设置编辑器覆盖 HM 配置。工作区、项目、终端历史、session 与认证仍归用户/herdr，移除功能不清理 `~/.local/state/herdr/` 或任何项目目录。

0.9.5 的 `src/config/{model,theme,tab_bar}.rs` 是 TOML 格式依据。上游没有标签选中下划线选项，`tab-underline.patch` 只将 `src/client/shell/tabs.rs` 焦点标签的实色 accent 填充改为 panel 背景、accent 前景和原生终端 underline；不改变命中区域与行为。升级时先核对这些源码，重新应用/审阅补丁；patch 和 postPatch 必须成功，`checks.herdr-config` 用真实二进制 `--version` 与 `config check` 校验生成配置。TUI 的线条为字符单元，没有 CSS 2px/渐变/发光；下划线由外层终端绘制。

公开入口为 `default.nix`；`checks.nix` 为 `{ pkgs, home, appearance, ... }` 测试钩子。其余文件私有。构建不会启动/重启桌面 daemon，也不代替实机字形和 agent 流程验收。
