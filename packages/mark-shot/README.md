# mark-shot

仓库维护的截图工具。**源码来自上游** [`jswysnemc/mark-shot`](https://github.com/jswysnemc/mark-shot) 的
release tag `v0.2.4`（commit `dbef0b5f5391fac9031443ed074e49bc1dd836d0`，2026-11-22），
本目录只保留：

- `default.nix`：包工厂（`fetchFromGitHub` + `applyPatches` + 本地 Nix 打包）；
- `patches/`：本仓库特有的行为补丁（见下）；
- `media.nix`：进程内录制/导出媒体库的 LGPL 构建；
- `e2e/`：真实运行的运行时验收套件（私有 headless Mango 2560×1600@1.5）。

不再像旧版那样整棵拷贝上游源码。升级上游 = 改 `default.nix` 里的 `revision`/`hash`、
刷新 `patches/`、重算 `cargoHash`；上游修过的补丁直接删掉。

## 为什么不再 vendored

2026-11-15 之所以把整棵上游源码放进仓库，是因为当时上游 `main` 没有 `flake.nix`，而仓库需要
Mango 窗口矩形、物理像素网格、剪贴板整包传输等本机修复。2026-11-22 的上游 0.2.4 已经恢复了完整
Nix 打包（`packaging/nix/`），并且已经覆盖了下面这些旧本地改动：

| 旧本地改动 | 上游 0.2.4 现状 | 处理 |
|---|---|---|
| 剪贴板 `EAGAIN` 等待整包写完 | `image_source.send_fd` 先清除 `O_NONBLOCK`，改为阻塞分块发送（匿名文件源） | 删除本地补丁，改用上游实现 |
| OCR 运行库缺 `libstdc++.so.6` | 上游 Nix 包设置运行库搜索路径；本仓库 wrapper 同样提供 | 不需要源码补丁 |
| 测试里 `/usr/bin/python3`、`fc-match` 路径 | 上游 `package.nix` 的 `postPatch` 已替换 | 不需要源码补丁 |
| UI 字体固定 Inter | 0.2.4 遵循 Fontconfig 系统字体 | 不需要源码补丁 |
| 上游缺少本地 packaging | 上游有 `packaging/nix/`，但本仓库仍保留自己的包工厂 | 保持本地打包（避免 flake 求值期 import-from-derivation） |

## 保留的补丁

| 补丁 | 内容 | 为什么上游没有 |
|---|---|---|
| `0001-mango-window-detection.patch` | `src/backend/window_detection/mango.rs`：用 `mmsg get all-clients/all-monitors` 读取 Mango 已排好的全局逻辑矩形，`MARK_SHOT_MMSG_BIN` 可改路径，遵守 `MARK_SHOT_CAPTURE_OUTPUT` 等环境变量 | 上游窗口识别只实现 niri/sway/KDE/UIA/Windows |
| `0002-capture-pixel-grid.patch` | 捕获帧的物理像素尺寸是唯一网格：编辑器画布、damage、标注、导出、剪贴板 PNG、保存共用同一网格；删掉按字节数猜 1–3 px 重拟合缓冲；覆盖层按帧尺寸分配 shm；导出用两轴精确比例映射 | 本机 Mango 在 2560×1600、scale 1.5 上给 layer-shell 的 configure 是 1706×1066，输出逻辑尺寸是 1707×1067，帧是 2560×1600。按「configure × scale」取整会得到 2559×1599，与帧差 1 px，上游 `frame_staging` 会报 `the native frame does not match the configured buffer` |
| `0003-config-recovery.patch` | 配置容错解码：逐字段剔除非法值（例如 `toolbar.fontSize:"middle"`）并写日志路径，不再整份回退默认；`recovery::repair` 备份后只删非法字段；`settings_store::write` 不被历史脏字段阻塞；修 `uploader`/`imageHost` 映射产生重复 `upload` 组的 bug | 上游 `config/loading.rs` 仍是整份回退 |
| `0004-one-dark-theme.patch` | 编辑器 chrome 的 One Dark 调色板（背景 `#1e2228`、浮层 `#272c33`、正文 `#abb2bf`、强调 `#61afef`、边框 `#5c6370`、危险 `#e06c75`、画布外围 `#181b20`） | 上游有自己的系统明暗主题，不是仓库 One Dark |

补丁按 `git apply -p1` 作用于干净的上游源码；`default.nix` 用 `pkgs.applyPatches` 应用。

## 打包

- 系统库用仓库 stable nixpkgs，Rust 工具链用 unstable（`rust-toolchain.toml` 固定 1.99.1）。
- `cargoHash` 而不是 `cargoLock.lockFile`：lock 文件在拉取的源码树里，flake 求值期不能
  import-from-derivation。
- `media.nix` 从 `crates/shot-media/native` 编译 `libmarkshot-media.so`，FFmpeg 9.0.2 是
  自建 LGPL-only 静态构建（无 GPL/nonfree，`CONFIG_GPL=0` 由构建检查），NVENC 用
  nv-codec-headers `n13.0.19.0`，软件编码用 OpenH264 2.6.0。不要换成 nixpkgs 的 `ffmpeg`
  （GPL 构建，会污染按 LGPL 发布的共享库）。
- wrapper 提供：`fc-match` 所在 PATH；`LD_LIBRARY_PATH` = OCR 运行库需要的 C++ 运行库 +
  `/run/opengl-driver/lib` + libpulseaudio（媒体库运行期 dlopen）。
- 安装桌面入口、metainfo、图标与两份 LICENSE；`$out/share/mark-shot/SOURCE-COMMIT` 记录
  上游 commit 和「带仓库补丁」标记。
- `doCheck = false`：上游测试需要私有参考字体、媒体库和真实显示；运行时验收走 `e2e/`，
  系统重建不跑整套 workspace 测试。

## 构建与验证

```sh
# 包
nix build --no-link --no-write-lock-file .#nixosConfigurations.nixos-btw.config.system.build.toplevel
nix build --no-link --no-write-lock-file --impure --expr \
  'let f = builtins.getFlake (toString ./.); p = f.inputs.nixpkgs.legacyPackages.x86_64-linux;
        u = f.inputs.nixpkgs-unstable.legacyPackages.x86_64-linux;
   in import ./packages/mark-shot { pkgs = p; inherit (u) rustc cargo; }'

# 真实运行时套件（私有 D-Bus + headless Mango 2560x1600@1.5）
nix build --no-write-lock-file --print-out-paths --impure --expr \
  'let f = builtins.getFlake (toString ./.); p = f.inputs.nixpkgs.legacyPackages.x86_64-linux;
        u = f.inputs.nixpkgs-unstable.legacyPackages.x86_64-linux;
   in (import ./packages/mark-shot { pkgs = p; inherit (u) rustc cargo; }).passthru.tests.e2e'
MS_E2E_OUT=/tmp/mark-shot-e2e /nix/store/<hash>-mark-shot-e2e/bin/mark-shot-e2e --phase all
```

套件细节与断言见 [`e2e/README.md`](e2e/README.md)。

2026-11-25 迁移到上游 v0.2.4 时的证据：包构建
`/nix/store/k9ylxx6jp0xjid8kb81k25z0iy59hypw-mark-shot-0.2.4`，`--version` 输出
`mark-shot 0.2.4`；私有 headless Mango 2560×1600@1.5 套件 **46 PASS / 0 FAIL**（整屏/区域捕获、
剪贴板与 `wl-clip-persist` 并发整包 398378 字节、点击动作栏复制、冻结预览、pin、scroll）。
真实会话的 `Print` 框选仍需 `nixos-rebuild switch` 后手动确认。

## 升级上游

1. 改 `default.nix` 的 `version`、`revision`、`hash`（`nix hash path` 或 `nix flake metadata` 的 narHash）。
2. 按顺序重放 `patches/`：`git init` 干净上游 → `git apply -p1 --3way` → 手工解冲突 → `git diff` 生成新补丁。
   上游已修的项目直接删补丁。
3. `cargoHash` 用 `lib.fakeHash` 构建一次，按报错里的 `got:` 填回。
4. 跑 `e2e` 的 `capture`/`clipboard`/`persist`/`editor` phase；`nixos-rebuild switch` 前再用真实会话
   跑一次 `Ctrl+Print` 与 `Print` 框选。

## 运行时注意事项

- OCR 模型与推理库首次使用需联网下载（仓库 RC 记录过 `github.com/microsoft/onnxruntime`
  访问 404 时面板内重装会失败，已有安装不受影响）；翻译、上传需要凭据与配置。
- 录制是单显示器或单显示器内区域，SDR 8-bit 4:2:0；不支持多显示器拼接/HDR。
- 窗口吸附依赖 Mango 的 `mmsg`；换合成器时 `0001` 补丁需要换成对应后端的实现。
