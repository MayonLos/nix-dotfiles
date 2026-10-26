# 桌面统一外观与输入更新（2026-10-26）

用户确认桌面、启动器、通知、文件管理器、终端、Neovim、LibreOffice 的三张预览，并要求移除 Nix Status、更新 flake 和处理迁移。

## 实现

- 保留 One Dark 和 35 px 一体式顶栏，删除 Nix Status 小组件及其专用脚本、补丁和配置；保留启动器的 nix-search。
- Mango 外距 16 → 12、圆角 12 → 10，内距 8、焦点边框 2 不变。启动器宽度 560 → 520；控制中心保留 380 和原生三列布局。
- Noctalia 面板、通知、提示统一细边框与不透明阅读底色，迁移到新版色彩角色。通知与 SYSTEM tooltip 同时出现仍可能重叠，本轮未加入额外避让。
- Thunar 低频 herdr/lazygit 动作移入 Development 子菜单；常用终端与 Neovim 入口仍直接可达。
- LibreOffice 包装器默认选择 Qt6 外壳，保留白色文档纸张；显式 SAL_USE_VCLPLUGIN 环境设置仍可覆盖，不写用户 profile。
- tmux 在不足 100 列时隐藏时间，不足 80 列时隐藏路径，保留 PREFIX/COPY/ZOOM 提示。Kitty 和 Neovim 沿用已应用的外观与原生补全，本轮没有替换补全插件。
- 修复真实 `/etc/fonts/local.conf` 缺少 XML 根的问题；字体检查现在直接解析生产配置原文，并要求 fc-match 无解析错误，避免测试自行补根掩盖缺陷。

## 更新与迁移

更新 stable/unstable nixpkgs、Noctalia、greeter、mark-shot、llm-agents、nix-index-database 与插件输入。stable 固定至 `1f607aa79b6356ed45d3cd3c8079c196e79efa2c`，Noctalia 至 `1af14b8cdb701175bec57ddf27d070b92461024b`，mark-shot 为 0.1.61。Den 保持正式版本 v0.19.0；没有变化的输入不强行追踪开发分支。

Noctalia 的 `outline`/`surface_variant` 迁移为 `outline_variant`/`surface_container`，保留新版 CPU 每核与网络精度接口。旧零上下文补丁虽然能够应用，却可能落到错误位置；独立审核发现后，全部保留补丁重新生成三行上下文并逐一核对，随后 C++ 构建和 GUI 验证通过。mark-shot 的上游 helper 迁入 libexec，本仓库独立 Mango 检测和 OCR 入口不依赖被移走的 PATH 文件。

## 验证

字体修复后的完整 `nix flake check --no-write-lock-file` 与系统 toplevel 构建均通过。`nixos-rebuild switch` 成功应用 `/nix/store/dxz5nczhyx4mb5ks3jv77cqlv71wplap-nixos-system-nixos-btw-26.05.20261025.1f607aa`。真实 Noctalia 与 Home Manager 服务 active、用户失败服务为空；真实截图确认 Nix Status 消失。生产字体 XML 根有效，Calibri/Cambria/中文回退匹配且 stderr 为空。实际 LibreOffice 包装器默认 Qt6，用户 profile 哈希不变，抽查 Word/Excel/PowerPoint/ODT 默认应用正确。内核与当前已启动版本一致，无需因本轮更新重启电脑；已打开的应用需重开才能使用新包装器。

私有 HOME/XDG/D-Bus/Wayland 下验证 2560×1600 与 2048×1280、缩放 1.5：无 Nix Status、长中文启动器、三列控制中心、通知动作显示、完整 SYSTEM tooltip。LibreOffice 的 Qt6 深色外壳与白纸、Thunar Development 子菜单另有宽窄屏截图。tmux 覆盖 79/80/99/100/120 列。私有图形进程全部退出后才允许应用系统。

硬件音量/亮度操作、通知动作回调、多屏截图路由未在隔离环境验证。IPC 与 RSS 粗测不是前后性能对比，不据此宣称性能提升。原始日志与截图位于 Git 忽略的 `.work/polish-r32/`。

## 可用的新功能

- mark-shot 设置的 Capture 区域可关闭精细 UI 区域识别，仍保留顶层窗口识别；复杂桌面可按需降低识别负担。新版独立 `--color-picker`、`--ruler`、`--code-scan`、`--snapshot-panel` 工具改进了跟随鼠标所在屏幕的路由。[锁定版本变更日志](https://github.com/jswysnemc/mark-shot/blob/9dcc564776e1b7f53ed28130e1e03e8f2ab2a97f/CHANGELOG.md)
- Noctalia 的 readline 风格输入快捷键、蓝牙连接通知、日历隐藏过期事项可按需开启；本轮不改变这些个人操作偏好。[上游发布说明](https://github.com/noctalia-dev/noctalia/releases/tag/v5.3.0)
- 配置迁移依据[锁定版本迁移源码](https://github.com/noctalia-dev/noctalia/blob/1af14b8cdb701175bec57ddf27d070b92461024b/src/config/config_migrations.cpp)，Den 版本依据[正式发布](https://github.com/denful/den/releases/tag/v0.19.0)。GitHub compare API 匿名请求受到额度限制，差异核验使用本地锁定源码。
