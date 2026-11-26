# mark-shot runtime E2E

真实运行的验收套件，不是静态检查。每一项都启动真实二进制、产生真实截图/剪贴板/文件，再验像素、
PNG 完整性、尺寸与字节一致性。

## 为什么需要它

2026-11-15 的真实会话缺陷只有在真实 Wayland 协议栈里才复现：

1. Mango 在 2560×1600、scale 1.5 的 eDP-1 上给 `wl_output` 报逻辑尺寸 1707×1067、给
   layer-shell configure 报 1706×1066，而 screencopy 帧是 2560×1600。按「逻辑尺寸 × 1.5」
   取整会得到 2561×1601 / 2559×1599，与真实帧差 1 px，导致粘贴 PNG 多透明边、覆盖层预览缩放错位。
2. 真实会话同时跑 `wl-clip-persist` + `cliphist` + clipboard-bridge，多读者并发读取同一选区时，
   旧发送路径把非阻塞管道的 `EAGAIN` 当失败，`wl-paste` 恰好收到 64 KiB 截断 PNG。
3. 编辑器预览必须是冻结截图（捕获后桌面变化不应影响预览），且 UI/画布/viewport 必须同一网格。

## 环境

套件自己创建隔离环境，不接触调用者的桌面、D-Bus、剪贴板或 `~/.config`：

- 私有 `dbus-run-session`（自写 bus 配置、空 servicedir）；
- 私有 `HOME`/`XDG_*`/`XDG_RUNTIME_DIR`（700）；
- 私有 headless Mango：`WLR_BACKENDS=headless`、`WLR_RENDERER=pixman`、
  `WLR_LIBINPUT_NO_DEVICES=1`，输出 2560×1600、scale 1.5（与 eDP-1 同构）；
- 静态 `swaybg` 壁纸（棋盘格 + 纯色块 + 对角线，含高频与平坦区域）；
- 纯 Python `zwlr_virtual_pointer_v1` 客户端（复用 `scripts/wayland_virtual_pointer.py`）做
  真实拖动/点击；
- 测试结束 `SIGTERM` 整个进程组，并核对无残留。

真机 Mango 二进制不在 nixpkgs，按 PATH 查找（可用 `--mango /path/to/mango` 覆盖）。

## 运行

```sh
# 在仓库根目录执行（从上游 v0.2.4 源码 + patches 构建）
nix build --no-write-lock-file --print-out-paths --impure --expr '
  let f = builtins.getFlake (toString ./.);
      p = f.inputs.nixpkgs.legacyPackages.x86_64-linux;
      u = f.inputs.nixpkgs-unstable.legacyPackages.x86_64-linux;
  in (import ./packages/mark-shot {
       pkgs = p; inherit (u) rustc cargo;
     }).passthru.tests.e2e'
# -> /nix/store/<hash>-mark-shot-e2e
MS_E2E_OUT=/tmp/mark-shot-e2e /nix/store/<hash>-mark-shot-e2e/bin/mark-shot-e2e --phase all
```

`--phase` 可选 `all`（默认）、`capture`、`clipboard`、`persist`、`region`、`interactive`、
`editor`、`pin`、`scroll`。证据（截图、日志、`report.json`）写到 `MS_E2E_OUT`，默认
`./e2e-out`。退出码：0 = 全部通过，1 = 有失败。

直接跑 Python 时可用环境变量覆盖工具路径（Nix wrapper 已经设好）：
`MS_E2E_MANGO`、`MS_E2E_GRIM`、`MS_E2E_WL_PASTE`、`MS_E2E_WL_COPY`、
`MS_E2E_CLIP_PERSIST`、`MS_E2E_MAGICK`、`MS_E2E_FILE`、`MS_E2E_SWAYBG`、
`MS_E2E_WTYPE`、`MS_E2E_DBUS`、`MS_E2E_PYTHON`、`MS_E2E_UPSTREAM_SCRIPTS`、
`MS_E2E_ROOT`、`MS_E2E_OUT`、`MARK_SHOT`。

## 断言（按 phase）

| phase | 断言 |
|---|---|
| capture | `--capture-to` 整屏 = 2560×1600；PNG 每个 chunk CRC + IEND + IDAT 解码长度；5 个平坦色探针逐字节等于场景色；第二次捕获字节一致；区域捕获尺寸 = 两轴比例 floor/ceil 预期且内容等于整屏捕获的映射裁剪 |
| clipboard | `-m -f -t cs` 退出码 0；剪贴板 MIME 含 `image/png`；立即与延迟 1s 读取都能完整解码；尺寸 2560×1600；剪贴板 PNG == `--capture-to` PNG 字节；保存文件扩展名 `.png`、magic PNG、PNG 完整性、尺寸、保存字节 == 剪贴板字节 |
| persist | 私有 `wl-clip-persist` + 图片 watcher 并发抢选区时，连续三次 `wl-paste` 都是完整可解码 PNG（旧 bug 为 65536 字节截断） |
| region | `-r -t c` 真实拖动后复制：尺寸与两轴比例预期一致（±2px，合成器内部逻辑宽 1706.67）；内容等于整屏捕获在映射偏移处的精确裁剪（AE=0） |
| interactive | 真实用户流程：`mark-shot`（Print）→ 虚拟指针拖出选区 → 点右侧动作栏复制按钮 → PNG 完整性/尺寸/内容等于映射裁剪；同时保留选区 UI 截图 |
| editor | `--fullscreen` 覆盖层截图 2560×1600；杀掉壁纸后再次截图与之前**字节相同**（证明预览是冻结捕获而非实时桌面）；日志中不出现旧的 buffer 重拟合 |
| pin | `--pin-clipboard` 真实打开贴图窗口并截图 |
| scroll | `--scroll` 真实打开覆盖层并截图 |

## 真机会话

`real-session.sh` 在正在运行的 Mango 会话上做同类尺寸/完整性检查（捕获、复制到真实剪贴板栈、
保存、短暂打开 `--fullscreen` 后立即结束进程）。会话锁屏时锁屏层盖住覆盖层，只能验证
捕获/剪贴板/保存；覆盖层像素验收以私有 headless Mango 为准。

```sh
MS=/nix/store/<hash>-mark-shot-0.2.4/bin/mark-shot \
OUT=/tmp/mark-shot-real WAYLAND_DISPLAY=wayland-0 \
MANGO_INSTANCE_SIGNATURE=/run/user/1000/mango-<pid>.sock \
e2e/real-session.sh
```

## 已知限制

- Mango 不把 `zwp_virtual_keyboard_v1` 事件投递给 layer 表面（私有与真机都实测），所以复制触发用
  真实**点击复制按钮**而不是 Ctrl+C；`-r -t c` 另外覆盖“选区结束即复制”的代码路径。
- `interactive` phase 的点击坐标硬编码上游 0.2.4 右侧动作栏位置（复制按钮在绿色保存按钮正上方，
  物理 `(2520, 920.5)` / 1.5）。上游 UI 布局变化时需要按新截图重测坐标，否则点击会落到图标间隙。
- grim 与 mark-shot 走不同的合成器读回路径，在本机 Mango 上 grim 有 ±1 颜色/alpha 舍入，因此
  pixel 验收以场景纯色探针、mark-shot 自身字节一致性和映射裁剪为准，不把 grim 当颜色 oracle。
- 套件需要能创建 headless Mango（wlroots headless backend）；在 Nix 沙箱内不可运行，故作为
  `passthru.tests.e2e` 构建脚本、手动/CI 执行，不进入 `nix flake check` 的沙箱检查。
