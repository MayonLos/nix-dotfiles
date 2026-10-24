# 开机体验与冷色调壁纸

2026-10-24，第二轮。主代理和用户已确认“完整无闪屏开机”与“冷色调轮换，默认 005”。
开始时工作树干净。本轮只修改仓库配置与文档，不应用配置、不修改运行态、不删除素材或应用数据，
不 stage、提交或推送；`flake.lock` 保持不变。本文按任务明确要求新增，未 stage，
因此不属于 Git flake 的输入；单独检查本文内容与链接。

## 实现与归属

- `aspects/system/legion-laptop/boot.nix`：systemd-boot timeout 从默认 5 改为 1 秒，
  `consoleMode = "max"`，`editor = false`；选择 systemd initrd、`verbose = false`、
  early i915 KMS 与 Plymouth `bgrt`。原有 `dm_mod` 保留，NVIDIA 留在 stage 2。
  `console.earlySetup = true`，Terminus `ter-v32n`（16×32 像素字格，内屏约 160×50）
  与 `console.packages = [ pkgs.terminus_font ]` 也属于该笔记本的启动/高分屏策略。
- `aspects/interactive-session/host/fonts.nix`：TTY 16 色消费宿主外观输入与公开
  `appearance/ansi.nix`，仅去掉 `#`。与 Kitty/Neovim 及桌面设计的 ANSI 顺序一致，
  不复制颜色值，也不让硬件 aspect 读取外观实现。外观 README 同步消费者。
- `aspects/system/maintenance/nix.nix`：journald `SystemMaxUse=1G`；只声明滚动上限，
  未手动 vacuum 或删除日志。现有 `maintenance/nh.nix` 已启用 nh 自动清理，锁定模块
  将其实现为每周 `nh clean all --keep 5 --keep-since 14d`，timer 为 Persistent；
  `nix.gc.automatic = false`。保留该现状，没有新增清理任务；用户仍可用 `nc` 手动清理。
- `aspects/interactive-session/noctalia.nix`：用 linkFarm 派生目录限定
  `002/005/008/009/011` 五张 PNG，`recursive = false`；默认路径 `005`，
  automation 为 enabled、random、86400 秒。全部原素材保留。
  Greeter、Xorg 桌面及 Xorg 锁屏固定为 `005`；Wayland 锁屏继续跟随当前壁纸。
  Xorg 检查和 desktop-design、xorg-desktop-execution、dwm-visual-design 同步。
- `aspects/interactive-session/checks.nix` 验证真实 host 的 loader/initrd/Plymouth/TTY、
  NVIDIA 不进入 initrd、greetd VT/顺序、派生目录恰有五个有效链接与默认/greeter 同图。
  `tests/composition/desktop.nix` 同时检查 reducedMotion 关闭启动转场且保留自动轮换。

## 锁定源码核对

本轮 nixpkgs 为 `da6dc0e7b26060f2f71ce3ef7088fb56ee44fa36`：

- `nixos/modules/system/boot/plymouth.nix` 的默认主题就是 `bgrt`，
  `themePackages` 仅对 breeze 默认补包；bgrt 由 Plymouth 包自带。
  模块自动复制 DejaVuSans 字体、默认 NixOS logo 和 bgrt 依赖的 spinner 资源到 initrd，
  不需额外 themePackages/font/logo 配置。固件 logo 是否可用取决于本机 BGRT，需重启验收；
  主题不等于能保证固件至 greeter 的所有画面都无闪屏。
- Plymouth 模块自动追加 `splash`，本地不重复。保留 `quiet`、`udev.log_level=3`、
  `loglevel=3`、`split_lock_detect=off`，仅补充 `systemd.show_status=auto`。
  锁定 systemd 260.5 源码 `src/udev/udev-config.c:462` 与
  `src/basic/proc-cmdline.c:165–179` 表明 udev 不带前缀的参数在两阶段都生效，
  因而不加重复的 `rd.udev.log_level=3`。`src/core/main.c:364–372,2886–2887`
  使用 flags=0 解析且只匹配 `systemd.show_status`，不会剥除 rd 前缀；因此
  `rd.systemd.show_status=auto` 无效，不添加。无前缀的 show_status 同时作用于两阶段。
  同版本 `systemd.1` 手册确认 quiet 默认是 error，auto 平时静默、明显延迟时显示状态，
  与 quiet 的默认值不重复。
  `boot.initrd.verbose` 主要控制旧 stage-1 脚本消息；systemd initrd 的状态策略由上述参数控制。
- `nixos/modules/services/display-managers/greetd.nix` 固定 VT1，旧 `services.greetd.vt`
  已移除。`greeterManagesPlymouth` 默认 false，自动令 greetd 排在
  `plymouth-quit-wait.service` 后；Noctalia greeter 当前模块未覆写该值。
  保留模块自带交接，不添加未经支持的 VT 或 quit 覆盖。
- Noctalia 当前锁定的是 `5f864d472676c77e5310881b243f15cc371bb223`（5.3.0），
  桌面设计早期引用的 `fc2af27c…` 是旧 pin。当前
  `docs/user/desktop/wallpaper.mdx:32–36,77–87`、
  `src/config/schema/config_schema.cpp:891–900`、
  `src/shell/wallpaper/wallpaper.cpp:938–943,994–1001` 确认字段名、目录/recursive 与轮换语义：
  shell 启动时先随机选一张，之后每 86400 秒随机选图，并同步应用到已连接输出；
  不是固定日历时刻任务，也不保证登录第一张为 `005`。
  `wallpaper.cpp:589–593,612–627` 表明手动/IPC 换图会重置该计时；
  `src/app/application_ui.cpp:342` 与 `wallpaper.cpp:912–914,1037–1046` 表明锁屏期间
  不执行轮换，wall clock 仍继续，解锁时若间隔已到期可立即换图。
  `reducedMotion = true` 通过本仓库已有适配设置 `transition_on_startup = false`、
  `transition = []`，轮换继续，切换无转场。未修改用户状态中原来的 `006`；
  应用后由主代理通过已核验的 IPC 处理，不清空 Noctalia state。

## 验证与构建

实际执行以下命令。静默参数按当前 systemd 源码精简后，重新完成格式检查、flake 求值、
最终配置求值、全部 checks 和 toplevel 构建；以下证据对应最终配置。

1. `git diff --check`：通过。`nix fmt`：通过，首次格式化仅改写了 Noctalia linkFarm
   的排版；最终一轮 0 changed。之后查看 `git diff` 并复查空白，通过。
2. `nix flake check --no-build --no-write-lock-file`：返回 0，全部 checks derivation
   与真实 host 求值通过；存在既有 `unknown flake output 'denful'` 警告。
3. `nix eval --json --no-write-lock-file .#checks.x86_64-linux --apply builtins.attrNames`：
   返回 0，共 18 项。用 Python 将该列表转换成 installable 参数，实际批量运行：

   ```sh
   nix build --no-link --no-write-lock-file \
     .#checks.x86_64-linux.command-line-runtime \
     .#checks.x86_64-linux.desktop-composition \
     .#checks.x86_64-linux.editing-composition \
     .#checks.x86_64-linux.embedded-composition \
     .#checks.x86_64-linux.embedded-home \
     .#checks.x86_64-linux.embedded-tools \
     .#checks.x86_64-linux.embedded-udev \
     .#checks.x86_64-linux.interactive-session-config \
     .#checks.x86_64-linux.local-services-composition \
     .#checks.x86_64-linux.neovim \
     .#checks.x86_64-linux.project-workbench \
     .#checks.x86_64-linux.protocols-composition \
     .#checks.x86_64-linux.remote-workspace-composition \
     .#checks.x86_64-linux.rime-technical-runtime \
     .#checks.x86_64-linux.system-boundaries \
     .#checks.x86_64-linux.treefmt \
     .#checks.x86_64-linux.workspace-composition \
     .#checks.x86_64-linux.xorg-session-runtime
   ```

   返回 0，全部 18 项构建成功，包含 treefmt、真实 host 配置、reducedMotion 分支、
   Xorg 运行检查及 Neovim 检查；部分复用此前已成功构建的相同产物。
   这些运行检查在构建沙箱执行，不代表真实桌面或开机验证。
4. `nix build --no-link --no-write-lock-file .#nixosConfigurations.nixos-btw.config.system.build.toplevel --print-out-paths`：
   返回 0，产物如下。构建使用模块自带 bgrt/spinner、DejaVu 字体与 Terminus，
   未额外配置主题包。并行求值时出现 Nix eval-cache SQLite busy 的 ignored 提示，未阻断构建。

   ```text
   /nix/store/5xipwrgs2rpdkn9x0bbf2kifv3ij5g7z-nixos-system-nixos-btw-26.05.20261021.da6dc0e
   ```

5. 实际打印最终值：

   ```sh
   nix eval --json --no-write-lock-file .#nixosConfigurations.nixos-btw.config --apply 'c: { timeout = c.boot.loader.timeout; kernelParams = c.boot.kernelParams; initrdModules = c.boot.initrd.kernelModules; plymouthTheme = c.boot.plymouth.theme; consoleFont = c.console.font; wallpaper = c.home-manager.users.mayon.programs.noctalia.settings.wallpaper; }'
   nix eval --json --no-write-lock-file .#nixosConfigurations.nixos-btw.config.home-manager.users.mayon.programs.noctalia.settings.wallpaper.directory --apply builtins.readDir
   ```

   两条均返回 0。timeout=1，initrdModules=`["dm_mod","i915"]`，theme=bgrt，
   consoleFont=ter-v32n。kernelParams 的完整输出：

   ```text
   quiet
   udev.log_level=3
   systemd.show_status=auto
   split_lock_detect=off
   root=fstab
   splash
   loglevel=3
   lsm=landlock,yama,bpf
   vt.default_red=0x0e,0xe5,0x8e,0xe2,0x4f,0xbf,0x48,0xa0,0x53,0xe5,0x8e,0xe2,0x4f,0xbf,0x48,0xd1
   vt.default_grn=0x10,0x55,0xbd,0xb8,0xa6,0x68,0xb0,0xa8,0x59,0x55,0xbd,0xb8,0xa6,0x68,0xb0,0xd5
   vt.default_blu=0x13,0x61,0x6b,0x6b,0xed,0xd9,0xbd,0xb7,0x65,0x61,0x6b,0x6b,0xed,0xd9,0xbd,0xde
   ```

   壁纸目录为 `/nix/store/shl9fh0mqv840192hich73a0fl12a7g9-noctalia-cool-wallpapers`，
   `builtins.readDir` 输出恰为五个 symlink：`wallpaper-002.png`、`wallpaper-005.png`、
   `wallpaper-008.png`、`wallpaper-009.png`、`wallpaper-011.png`；构建检查进一步验证链接目标存在。
   默认路径为 `/nix/store/q4rjlxsx98ahl40zj56b30piy4vv94ai-wallpaper-005.png`。
   同时求值确认 `initrdSystemd=true`、`initrdVerbose=false`、`themePackages=[]`、
   console 16 色、greetd VT1/After 和 nh weekly 策略。
6. `nix build --no-link --no-write-lock-file .#nixosConfigurations.nixos-btw.config.systemd.package.src --print-out-paths`：
   返回 0，仅为核对锁定 systemd 260.5 的参数解析源码；产物为
   `/nix/store/s8lxzd3r71kn8f8gfj9vq4ghdzvlna7f-source`。
   读取已构建 bgrt 主题确认 `UseFirmwareBackground=true` 与 spinner ImageDir；
   Terminus 包确认存在 `share/consolefonts/ter-v32n.psf.gz`。
7. Python 校验 6 个修改/新增 Markdown 文件中的 47 个相对链接：通过；
   新 history 单独检查行尾空白。`git diff --exit-code -- flake.lock` 返回 0。
   新文件的 `git diff --no-index --check /dev/null docs/history/boot-wallpaper-2026-10-24.md`
   无空白错误输出，返回 1 表示两输入存在差异；不把该退出码写成构建失败或成功码。
   Git flake 不包含这份未跟踪历史文件；treefmt 也不承担 Markdown 版式检查。
8. 独立 reviewer 只读核对跨模块接线、Noctalia 语义与最终 systemd 参数，未发现阻断缺陷。
   审核没有应用配置，不代替实机测试。

## 应用与待验收

本轮未执行 sudo 或任何 nixos-rebuild，也未改仓库外配置、登录状态和壁纸素材。
待主代理/用户应用后重启：确认固件 logo、early KMS、Plymouth 转圈、greeter 交接及错误场景；
检查启动菜单与 TTY 字号、颜色和字体。仍需实机检查壁纸随机启动/每日轮换、reducedMotion
无转场、greeter 与 Xorg/锁屏裁切。未重新测量启动耗时、功耗或显卡 runtime 行为。
