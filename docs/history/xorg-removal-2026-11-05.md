# 移除 dwm / Xorg 会话（2026-11-05）

## 背景

`xorg-session` 为 QQ、腾讯会议的原生 X11 捕获而加。用户决定只保留 Mango，并删除专为
X11 安装的全部组件。

## QQ Wayland 屏幕共享试验（已撤销）

接入 `github:SHORiN-KiWATA/linuxqq-wayland-fix`（e45408c，LD_PRELOAD）并实机应用：

- `--doctor` 22 项通过；portal（xdg-desktop-portal-wlr，`chooser_type = none`）打开成功，
  PipeWire 交付 2560x1600 帧（`reuse capture texture`）。
- Intel RPL-S 上 ANGLE Vulkan 启动即 `Unable to initialize SkSurface`（上游 #48），回退默认
  GL 后端；共享中 GPU 进程出现 `glBindFramebuffer GL_INVALID_OPERATION`。
- 强制 NVIDIA Vulkan ICD 时 ANGLE 无法导入 iGPU DMA-BUF（`Internal Vulkan error (-8)`），
  QQ 显示“视频画面暂时无法显示”。
- 测试通话对象被 QQ 风控，多次“通话房间创建失败”；未得到远端看到画面的证据。

用户判断不可用，撤销 flake input、包别名与启动器改动。wemeet 按用户要求删除。

## 删除范围

- `aspects/desktop/xorg-session/` 整个 feature（dwm、Picom、Dunst、Rofi、CopyQ、i3lock-color、
  xss-lock、xidlehook、feh、xrandr、状态程序、supervisor、`xorg-dwm.desktop`、
  `services.xserver`/startx、`xdg.portal.config.dwm` 及其检查）。
- `docs/xorg.md`、`docs/xorg-visual.md`；用户绑定、aspect 与检查登记。
- 只为 X11 存在的旁支：tmux-fzf 的 CopyQ 补丁与检查、Mango 的 CopyQ 窗口规则、Thunar
  壁纸动作的 feh 分支、`gamescope-run` 的 xrandr 回退。
- pavucontrol 原由 xorg-session 安装，Mango 仍在用，改由 `session-support` 安装。

保留：`xresources`/`xrdb-merge`（Xwayland DPI 与根光标）、`xclip`（剪贴板桥）、
`hostFacts.display.x11Dpi`、NVIDIA `services.xserver.videoDrivers`（驱动选择入口）。
CopyQ 历史、Rofi 频次等用户数据未清理。
