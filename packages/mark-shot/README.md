# mark-shot

本仓库维护的截图工具。上游是 [jswysnemc/mark-shot](https://github.com/jswysnemc/mark-shot) 的 Rust `main`，提交 `4cf891014f584e9199e41a182c13f6f478435115`（2026-11-13）。许可证 MIT OR Apache-2.0，原文在 `LICENSE-MIT` 与 `LICENSE-APACHE`。

在这棵树上直接改，不再跟上游 flake，也不再对拉取的包打补丁。`rust-toolchain.toml` 要求 rustc 1.99.1，包工厂使用 `nixpkgs-unstable` 的 rustc 与 cargo，系统库仍来自本仓库的 stable nixpkgs。

## 本机改动

`src/backend/window_detection/mango.rs` 在没有 `NIRI_SOCKET` 和 `SWAYSOCK` 时执行 `mmsg get all-clients` 与 `mmsg get all-monitors`。Mango 给出的矩形已经是排好的全局逻辑坐标。只保留可见、未最小化、且落在活动输出上的窗口。`MARK_SHOT_MMSG_BIN` 可改 `mmsg` 路径；`MARK_SHOT_CAPTURE_OUTPUT`、`MARK_SHOT_CAPTURE_ALL_OUTPUTS=1` 和 `MARK_SHOT_CAPTURE_{X,Y,WIDTH,HEIGHT}` 与原来的检测脚本含义相同。

`src/backend/wayland/overlay/frame_staging.rs` 的覆盖层缓冲改按实际交付帧重拟合。Mango 在 2560×1600、scale 1.5 的 eDP-1 上给 layer-shell 的 configure 逻辑尺寸是 1706×1066，乘 1.5 得到 2559×1599；但截图帧按 1707×1067 逻辑尺寸取整，是 2561×1601。旧代码直接报 “the native frame does not match the configured buffer”，交互式框选因此完全打不开。现在发现字节数不一致时会在 ±3 px 内反推真实像素网格并重配 shm 缓冲，viewport destination 仍是 configure 的逻辑尺寸。`MARK_SHOT_DEBUG=1` 会打印重拟合结果。`--capture-to` 不受影响。

`src/theme/` 的暗色调色板改为仓库 One Dark：背景 `#1e2228` / 浮层 `#272c33`，正文 `#abb2bf`、
强调文字 `#d7dae0`，强调色 `#61afef`，边框 `#5c6370`，危险色 `#e06c75`；画布外围底色用 deep
`#181b20`，透明度棋盘格用 bg/surface 两色。`[ui].theme` 默认改为 `system`：桌面报告
prefer-dark（本仓库 GTK/门户设置为 prefer-dark）时即使用上述 One Dark，无门户信息的测试环境
由 `system::detect()` 解析为浅色。浅色调色板仍保持原版 Qt 输出；`tests/fixtures/qt-theme.json`
的 dark 段同步更新。界面字体继续使用程序自带的 Inter（与 `palette.fonts.sans` 一致），
工具栏只继承主题颜色、几何未改。

## 使用

| 命令 | 作用 |
|---|---|
| `mark-shot` | 区域、窗口、标注、复制、保存、置顶 |
| `mark-shot --scroll` | 滚动截图 |

配置优先读 `~/.config/mark-shot/config.toml`。没有这份文件时继续读已有的 `config.json`，不在激活时改写它。滚动截图不再使用 wayscrollshot。

安装和快捷键在 `aspects/desktop/mango-session/screenshot.nix` 与 `mango/keybinds.nix`。`Print` 启动标注，`Shift+Print` 启动滚动截图。

## 本仓库构建的功能覆盖

`pkgs.local.mark-shot` 现在同时构建主程序和录制/导出需要的进程内媒体库：

- 产物 `$out/bin/media/libmarkshot-media.so`。`crates/shot-media/src/lib.rs` 默认从可执行文件
  所在目录的 `media/` 加载（也可用 `MARK_SHOT_MEDIA_LIBRARY` 指向绝对路径覆盖），所以安装位置
  与上游发布包一致，`--record` 能直接开始录制。
- 构建表达式在 `packages/mark-shot/media.nix`，由 `default.nix` 引用：
  - `ffmpeg-lgpl-9.0.2`：从 ffmpeg.org 固定 tarball（`sha256-...`）自建，LGPL-only。
    `--disable-autodetect --disable-everything` 后只显式打开 shot-media 用到的组件；GPL/nonfree
    关闭（x264/x265 不存在），静态 PIC。configure 后检查 `CONFIG_GPL=0`、`CONFIG_NONFREE=0`，
    违反时构建直接失败。软件编码用 OpenH264，硬件保留 VAAPI 与 NVENC（CUDA 头只在编译期使用，
    运行时由 FFmpeg 自己 dlopen 驱动）。
  - `openh264-2.6.0`：codeload 固定 tarball（`sha256-...`），`libraries` + `install-static`，PIC。
  - `nv-codec-headers-n13.0.19.0`：与 vendored `scripts/media/build-libraries.sh` 相同的版本。
    没有采用某些 nixpkgs 渠道的 9.1.23.1：FFmpeg 9.0.2 的 configure 要求
    `ffnvcodec >= 12.1.14.0`，而 git.videolan.org 重新编号后的 9.1.23.1 不满足该范围，会被静默
    判为不可用并丢掉 NVENC。若以后 FFmpeg 更新了该检查，可再切换。
  - 包装代码按上游参数编译链接：`-fPIC -O2 -fvisibility=hidden -Wall -Wextra -Werror`、
    `-Wl,-z,defs -Wl,-Bsymbolic -Wl,--exclude-libs,ALL`；只导出 `ms_*` ABI
    （`ms_media_abi` 返回 2），FFmpeg 符号全部隐藏。
- 许可：`$out/share/licenses/mark-shot-media/` 安装 FFmpeg LGPL 文本与
  `FFMPEG-CONFIG.{h,mak,COMPONENTS.h}`、OpenH264 BSD 文本、nv-codec-headers README 和
  `NOTICES.txt`。不要改用 nixpkgs 的 `ffmpeg`：它是 GPL 构建（含 libx264/libx265），会污染
  这个按 LGPL 发布的共享库。
- 构建（flake 输出仍由 `nix/pkgs.nix` 的 `pkgs.local.mark-shot` 提供；下面这条用于直接构建本包）：

```sh
nix build --no-link --no-write-lock-file --impure --print-out-paths --expr '
let
  root = "/path/to/nix-dotfiles/packages/mark-shot";
  f = builtins.getFlake "/path/to/nix-dotfiles";
  pkgs = import f.inputs.nixpkgs {
    system = "x86_64-linux";
    config.allowUnfree = true; # CUDA headers are compile-time only
  };
  u = import f.inputs.nixpkgs-unstable {
    system = "x86_64-linux";
    config.allowUnfree = true;
  };
in import root { inherit pkgs; inherit (u) rustc cargo; }'
```

- 验证脚本 `scripts/media/verify-nix-package.py`：私有 headless Sway（`WLR_BACKENDS=headless`
  + pixman）+ 私有 D-Bus 中驱动打包后的真实 GUI 流程（`--record` → `wtype` 虚拟键盘 Enter 开始 →
  `--recording-status` 轮询 → `--stop-recording`），再用 ffprobe 校验编码/尺寸/时长、完整解码、
  解码帧数与首帧 fixture 颜色；录制进程跑在 `strace` 下以记录媒体库打开路径。2026-11-15 在
  本 worktree 实测（媒体库 runpath 完整，`ldd` 无 `libav*`/`libx264`/`libx265` 共享依赖）：
  - MP4：`h264` 1280×720、约 2.3 s、35 帧；GIF：`gif` 1280×720、约 2.26 s、28 帧；
    两者首帧都有 74576 个 fixture 颜色像素。
  - 状态详情为 `Wayland image-copy SHM · libopenh264 · in-process`，`strace` 记录
    `openat("<store>/bin/media/libmarkshot-media.so")`，没有打开任何 GPL FFmpeg 共享库。
  - 证据（截图、录制文件、probe JSON、strace）在 `.work/media/evidence/final/`，已被 gitignore。
- 交互自动化的注意点：headless Sway 没有输入设备，sway 的 `seat cursor press` 不会给客户端
  `wl_pointer` 能力；必须用 `wtype` 之类创建 wlroots 虚拟键盘，并让连接保持一小段时间
  （脚本用 `-s 800`）等客户端完成键盘能力绑定后再按 Enter。脚本里的滚动终端用于持续产生真实
  合成器 damage，否则 mark-shot 会把无变化输出的编码帧率节流到约 1 fps，测不到 15 fps 帧数。

内置 OCR 模型首次使用需联网下载，翻译与上传分别需要 API 凭据和配置，离线只能验证功能入口。
上游当前 release 同样是 0.2.0，没有需要同步的更新版本。隔离验证（私有 headless Sway + 私有
D-Bus，见 `.work/preview/mark-shot/`）已覆盖 `--version`、`--list-displays`、`--capture-to`
（整屏与区域）、`--scan-json`、编辑器覆盖层、`--pin-clipboard`、`--record` 控制器与
`--recording-status`。上游要求的 `cargo fmt --all -- --check`、
`cargo clippy --workspace --all-targets --locked -- -D warnings`、`cargo test --workspace --locked`
在此包构建里没有执行（`doCheck = false`）。
