# mark-shot

本仓库维护的截图工具。上游是 [jswysnemc/mark-shot](https://github.com/jswysnemc/mark-shot) 的 Rust `main`，提交 `4cf891014f584e9199e41a182c13f6f478435115`（2026-11-13）。许可证 MIT OR Apache-2.0，原文在 `LICENSE-MIT` 与 `LICENSE-APACHE`。

在这棵树上直接改，不再跟上游 flake，也不再对拉取的包打补丁。`rust-toolchain.toml` 要求 rustc 1.99.1，包工厂使用 `nixpkgs-unstable` 的 rustc 与 cargo，系统库仍来自本仓库的 stable nixpkgs。

## 本机改动

`src/backend/window_detection/mango.rs` 在没有 `NIRI_SOCKET` 和 `SWAYSOCK` 时执行 `mmsg get all-clients` 与 `mmsg get all-monitors`。Mango 给出的矩形已经是排好的全局逻辑坐标。只保留可见、未最小化、且落在活动输出上的窗口。`MARK_SHOT_MMSG_BIN` 可改 `mmsg` 路径；`MARK_SHOT_CAPTURE_OUTPUT`、`MARK_SHOT_CAPTURE_ALL_OUTPUTS=1` 和 `MARK_SHOT_CAPTURE_{X,Y,WIDTH,HEIGHT}` 与原来的检测脚本含义相同。

**物理像素网格统一（2026-11-15，真实会话复现修复）**：Mango 在 2560×1600、scale 1.5 的 eDP-1 上
给 `wl_output` 报逻辑尺寸 1707×1067、给 layer-shell configure 报 1706×1066，而 screencopy 帧是真实
mode 的 2560×1600。旧实现把「逻辑尺寸 × 协议比例 1.5」再取整当成缓冲/画布尺寸（2561×1601 与
2559×1599），随后在 `frame_staging.rs` 里按交付字节数猜 1–3 px 重拟合缓冲——缓冲、画布、viewport
和 damage 各用不同网格，粘贴出的 PNG 比屏幕多一列一行透明像素，覆盖层预览也被额外缩放/错位。

现在的规则是**捕获帧的物理像素尺寸是唯一网格**：

- `app/init.rs` 的捕获比例改为帧宽/逻辑宽的精确值（2560/1707），不再量化到 1/120；新增
  `build_placements_for_frames`，布局的 `px_size()` 由捕获帧推出 2560×1600（编辑器画布、
  damage、标注都在这张网格上）。
- 覆盖层通过 `ScreenOverlay::set_output_pixels` 在 `present` 前拿到每台输出的捕获帧尺寸，
  `state/compositor_shm.rs` 用它分配 shm 缓冲（不再用 configure 逻辑尺寸乘比例），layer-shell
  同时显式请求 wl_output 的逻辑尺寸，viewport destination 仍是 configure 的逻辑尺寸。
- `frame_staging.rs` 删除“猜 1–3 px 重拟合”逻辑：交付帧与缓冲网格不一致时直接报错，避免掩盖
  真实的网格错误。
- `renderer/capture_composite.rs` 的导出按**两轴精确比例**做像素映射（2560/1707 与 1600/1067
  并不相等），完整桌面得到 2560×1600；分数原点用 floor/ceil 覆盖部分像素（原版 Qt 语义）。
  这样 `--capture-to`、剪贴板、保存、`--fullscreen` 冻结预览共用同一网格。

**剪贴板整包交付**：`backend/wayland/clipboard/image_source.rs` 的发送路径原来把非阻塞管道的
`EAGAIN` 当成失败。真实会话里 `wl-clip-persist`/`cliphist` 会同时读取选区，管道写满后传输恰好
停在 64 KiB，`wl-paste` 得到被截断、无法解码的 PNG（实测 65536/196608/720896 字节）。现在
`EAGAIN` 只视为消费者窗口暂满，等待后继续写完整个 PNG；辅助进程在选区被接管后也会等待进行中的
传输结束再退出。`tests/e2e` 用私有 `wl-clip-persist` + watcher 复现并守护该场景。

**格式审计（“jpg 无法发送”）**：本程序只编码 PNG——`--capture-to`、默认保存、另存为都写 PNG
字节，默认保存路径固定 `*.png`，保存对话框给非 `.png` 文件名补 `.png`；剪贴板提供
`image/png`（另加 KDE 提示 `x-kde-force-image-copy`）。因此 mark-shot 不会产出“扩展名 jpg、内容
却是 PNG”的文件。DSH 侧 `prepareImageFile` 实测接受该剪贴板 PNG（2560×1600、image/png），而把
同一份 PNG 声明成 `image/jpeg` 会被 `IMAGE_TYPE_MISMATCH` 拒绝：用户看到的“jpg 无法发送”是
文件名/声明类型与真实字节不一致（例如手工改扩展名或别的工具另存）造成的，不是本程序的输出。

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

## 运行时端到端测试（真实进程/真实像素）

`tests/e2e/` 是可复跑的运行时套件：私有 D-Bus + 私有 headless Mango（2560×1600@1.5，与 eDP-1
同构）、静态 swaybg 壁纸、纯 Python wlr 虚拟指针。它真的启动 mark-shot、真的框选/点复制按钮/读
剪贴板/写文件，并用 PNG CRC 解码、像素探针和整图字节比较验收，而不是静态检查。

```sh
# 构建套件（脚本内已固定 grim/wl-clipboard/ImageMagick/swaybg/wtype/dbus 等工具路径）
# 在仓库根目录执行
nix build --no-write-lock-file --print-out-paths --impure --expr '
  let f = builtins.getFlake (toString ./.);
      p = f.inputs.nixpkgs.legacyPackages.x86_64-linux;
      u = f.inputs.nixpkgs-unstable.legacyPackages.x86_64-linux;
  in (import ./packages/mark-shot { pkgs = p; inherit (u) rustc cargo; }).passthru.tests.e2e'
# 运行（需要 PATH 里有 mango；可用 --mango 指定）
MS_E2E_OUT=/tmp/mark-shot-e2e /nix/store/...-mark-shot-e2e/bin/mark-shot-e2e --phase all
```

覆盖项（45 项断言）：整屏/区域 `--capture-to`（尺寸=2560×1600、PNG CRC、纯色探针、可复现）、
`-m -f -t cs` 剪贴板+保存（MIME/尺寸/整数解码/剪贴板==捕获字节/保存==剪贴板字节）、
`wl-clip-persist` 并发读取下连续三次完整解码、真实框选拖动 + 复制按钮（尺寸/像素等于全屏捕获
的映射裁剪）、`--fullscreen` 冻结预览（杀掉壁纸后屏幕字节不变）、`--pin-clipboard`、`--scroll`
覆盖层。真实会话脚本 `tests/e2e/real-session.sh` 在正在运行的 Mango 上做同样尺寸/整包校验
（页面锁定时只能验证捕获/剪贴板/保存，不能验证覆盖层像素）。

上游要求的 `cargo fmt --all -- --check`、`cargo clippy --workspace --all-targets --locked -- -D
warnings`、`cargo test --workspace --locked` 在此包构建里没有执行（`doCheck = false`）；本分支
改动已单独跑过 `cargo test --lib`，失败集合与改动前基线完全一致（38 项环境/Qt 参考字体类失败）。
