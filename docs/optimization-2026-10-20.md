# 可读性、桌面与项目工作流优化

2026-10-20。用户授权自主优化、美化、重构和系统应用。开始时工作树已有 19 个已修改或新增文件；原始 diff 保存在权限受限的本机临时目录，不回滚或提交这些既有改动。锁定输入不更新。

## 实现

- 保留 One Dark Darker，补全详情、来源及 Markdown 深层标题使用可读前景；非激活和装饰灰色保留。
- Noctalia 面板与插件设置分别移入 `aspects/interactive-session/noctalia/bar.nix`、`plugins.nix`，两者仍为原 feature 的私有数据配方。面板保留时钟/猫和媒体，低频设备信息放进原生悬停抽屉，CPU 监视移入开发抽屉，网络、音量、通知、防空闲与电量常显。
- 加入锁定官方翻译插件，`/tr 文本` 默认译成中文，`/tr en 文本` 指定英文；显式翻译查询使用 Google 在线服务。
- 审查锁定录屏插件时发现它会接管外部 gpu-screen-recorder，停止时按名称发 SIGINT，三秒后 SIGKILL。本轮不启用该插件，保留 OBS；没有启动、停止或接管任何真实录制。
- 项目 desktop actions 提供编辑器/目录入口；`workspace = true` 的项目可建立或复用 tmuxp 编辑器与两个 shell 布局，真实 host 为 dotfiles/NewNuclear 选择。不自动构建、测试或信任 `.envrc`。
- Docker 每周维护缩小为一周未使用的构建缓存，保留原 timer 名称与生命周期，不再自动清理停止容器。没有手动触发清理命令。

未确定备份目的地，因此没有部署空备份任务；没有改 NVIDIA/休眠策略，没有改浏览器 profile 或迁移数据。

## 验证与应用

- `nix flake check --no-write-lock-file --max-jobs 1 --cores 2` 返回 0，18 个 x86_64-linux 根 checks 全部构建通过。项目 check 的 10 项测试包括真实私有 socket 上的 tmuxp 创建/复用、三 pane cwd、编辑器 `.` 参数和只启动一次；Neovim、桌面 parser、Xorg/Rime 与服务隔离按各自 check 范围通过。
- 完整 `nixos-btw` toplevel 构建通过：`/nix/store/c5kvfh2wy2k51b0wxjis6b8f8iw3p5jh-nixos-system-nixos-btw-26.05.20261012.7993f34`。输入锁没有变化。
- 激活前 greetd、NetworkManager、nix-daemon 的 unit 内容与旧系统相同；dry-activate 只计划重启 Home Manager。
- 已执行 `sudo nixos-rebuild switch --flake /home/mayon/nix-dotfiles#nixos-btw --no-write-lock-file --max-jobs 1 --cores 2`，返回 0，应用为 generation 398；`/run/current-system` 与构建产物一致。旧 generation 保留，没有 GC、注销或重启机器。
- 切换前后记录的 15/15 个进程 PID、内核 starttime 与 executable 保持一致（包括 Java、Codex、Mango、终端、Noctalia、登录与网络服务）。Home Manager 为 active / Result=success / ExecMainStatus=0；Mango、Noctalia、Fcitx5、clipboard-bridge active，用户管理器没有 failed units。
- Noctalia 自动热加载新配置；面板局部截图已目检，没有看到裁切或重叠。录屏插件 disabled、translator enabled。既有空工作区中的 `/tr hello world` 实际返回“你好世界”，已目检截图并关闭启动器，没有按 Enter 写入剪贴板，也没有打开个人项目。
- 两个真实项目的已安装 desktop entries 保持原 ID，均有 editor/files/workspace actions；`workspace-project list` 正确列出两项。实际 Docker user unit 只包含带 `until=168h` 的 builder prune，本轮没有手动触发。
- 新安装 Neovim 在临时 HOME/XDG 冷启动，通过补全与 H5/H6 前景断言；没有强制重载用户已经打开的编辑器。
- `git diff --check`、变更 Markdown 的相对链接检查通过；最终记录经 treefmt 构建检查。

日志与预览位于本机权限受限临时目录 `/tmp/dotfiles-polish.yoPoiI/`，包括 `final-checks.log`、`host.log`、`switch.log`、`bar-before.png`、`bar-after.png` 和 `translator.png`，不是长期归档资源。没有提交或推送既有用户改动。

本次不据此宣称多屏/全部抽屉交互、真实个人工程性能、睡眠恢复或会议共享均已验收。项目布局验证在隔离目录中完成；实际项目的依赖与 `.envrc` 信任仍由项目本身决定。
