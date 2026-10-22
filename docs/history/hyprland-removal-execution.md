# 移除 Hyprland

日期：2026-10-19。用户体验后决定不再使用 Hyprland，要求删除并尽量在五分钟左右完成。
主代理负责移除与构建，Luna 并行更新当前文档，独立 reviewer 核对源码、服务和启动边界。
基线 `70fe942` 工作树干净；此前添加和验证的历史保留在[系统界面记录](system-experience-execution.md)。

## 改动

移除 `hyprland-session` Den/真实 host 选择、主机模块、Lua 配置、登录 wrapper、专属检查、
Noctalia 变体及截图 dispatcher。共享服务恢复单一 `mango-session.target`，截图恢复 Mango
helper。保留此前 One Dark、Noctalia/GTK/Mango 美化、Yazi/tmux/Git、mpv/uosc、BAT 修正，
右下热区继续关闭。没有修改输入锁、用户词库、凭据、模型、历史、容器卷或 VM 镜像。

## 应用边界

检查发现当前实际运行 Hyprland，Mango target inactive。为保留当前桌面与任务，本次使用
`nixos-rebuild boot` 设置下次启动配置，不执行 switch、logout、停止 compositor 或重启系统。
锁定实现的 Boot 分支更新启动项后即退出，早于服务与 Home Manager 激活。
当前 Hyprland 进程、旧 HM 托管链接和登录列表会保留到用户自行重启；重启后使用 Mango。
这不构成当前能耗下降的实测证据，未做同负载能耗比较。

## 验证

- 源码提交 `ffb0177`。Mango/Noctalia 配置解析、desktop-composition、treefmt 及完整
  `nixos-btw` toplevel 均构建通过；未重跑无关编辑器/语言检查。
- `nixos-rebuild boot` 返回 0，系统 profile 已指向
  `/nix/store/h2m1d2llqhvr4c6xmiw9vkdca4awwx21-nixos-system-nixos-btw-26.05.20261012.7993f34`（generation 393）。
- 新产物的 Mango 登录项存在；Hyprland 可执行文件、登录项和 portal 配置不存在。
  实际查询新系统闭包，没有 Hyprland compositor 或 xdg-desktop-portal-hyprland 包。
- 当前 `/run/current-system` 仍为原 bqn generation，greetd PID 未变；
  6/6 个受保护进程 PID/启动时间保持，包含当前 compositor/launcher、终端和 Codex。
  当前桌面没有切换，实际重启进入 Mango 与配置交接尚待用户完成工作后验证。
- 构建与 boot 日志分别为 `/tmp/codex-hyprland-removal-build.log`、
  `/tmp/codex-hyprland-removal-boot.log`。没有执行 GC 或删除个人应用数据。
