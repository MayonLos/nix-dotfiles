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

`pkgs.local.mark-shot` 只构建主程序。录制与媒体导出需要的进程内媒体库 `libmarkshot-media.so`
由上游 `scripts/media/build-libraries.sh` 单独构建（下载固定版本的 FFmpeg 9.0、OpenH264 2.6
与 nv-codec-headers），本仓库的 Nix 包尚未接入这一步：`$out` 下没有 `media/libmarkshot-media.so`，
`crates/shot-media/src/lib.rs` 按可执行文件旁的 `media/` 目录加载，因此 `--record` 能打开控制器但
开始录制缺少媒体库。内置 OCR 模型首次使用需联网下载，翻译与上传分别需要 API 凭据和配置，离线只能
验证功能入口。上游当前 release 同样是 0.2.0，没有需要同步的更新版本。

隔离验证（私有 headless Sway + 私有 D-Bus，见 `.work/preview/mark-shot/`）已覆盖 `--version`、
`--list-displays`、`--capture-to`（整屏与区域）、`--scan-json`、编辑器覆盖层、`--pin-clipboard`、
`--record` 控制器与 `--recording-status`。上游要求的 `cargo fmt --all -- --check`、
`cargo clippy --workspace --all-targets --locked -- -D warnings`、`cargo test --workspace --locked`
在此包构建里没有执行（`doCheck = false`）。
