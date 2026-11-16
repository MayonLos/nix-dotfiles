# mayon-overlay

Wayland layer-shell 剪贴板历史与纯文字应用启动器。Mango 会话不安装、也不绑定它：
启动器是 fuzzel（`Alt+Space`），剪贴板历史是 cliphist，`Super+V` 用 fuzzel 的
dmenu 模式。单二进制、Rust 编写、CPU 光栅化（tiny-skia + fontdue）直接写
`wl_shm`，不依赖 GTK/Qt，也不使用 EGL/Vulkan，因此在 pixman headless
compositor 下同样可运行。

## 模式

| 入口 | 作用 |
|---|---|
| `mayon-clipboard` / `mayon-overlay clipboard` | 读取 cliphist 历史；文本条目显示文本，图片条目显示缩略图；选中即 `cliphist decode \| wl-copy` 复制并关闭，随后尝试自动粘贴 |
| `mayon-launcher` / `mayon-overlay launcher` | 纯文字应用列表（不显示图标）；输入过滤、方向键/Tab 选择、Enter 启动、鼠标点击启动；启动走 `gio launch <desktop-file>` |
| `mayon-overlay ctl <command>` | 通过 Unix socket 控制正在运行的 overlay（测试与脚本用） |

外观使用 `aspects/appearance/appearance/onedark.nix` 的 One Dark 调色板：构建时由
`build.rs` 把该文件序列化进二进制，因此改主题会重建 overlay，不会出现两套颜色。
布局是聚焦输出上的全屏遮罩 + 居中卡片：背景 `bg`、卡片 `surface`、边框 `border`、
选中行 `selection` + `blue` 左侧指示条。

## 构建与安装

本仓库的包工厂已在 `nix/pkgs.nix` 注册为 `pkgs.mayonOverlay`（合并后由主 flake
求值即生效；把 `packages/mayon-overlay/tests/check.nix` 注册成 check 后也可直接
`nix build .#checks.x86_64-linux.mayon-overlay`）。未注册 check 前可用包工厂表达式构建：

```sh
nix build --no-link --print-out-paths --no-write-lock-file --impure --expr '
let
  flake = builtins.getFlake "path:/home/mayon/nix-dotfiles-wt/overlay";
  pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
in import /home/mayon/nix-dotfiles-wt/overlay/packages/mayon-overlay { inherit pkgs; }'
pkgs.mayonOverlay
# $out/bin/mayon-overlay    原始二进制（子命令形式）
# $out/bin/mayon-clipboard  已带 clipboard 子命令的 wrapper
# $out/bin/mayon-launcher   已带 launcher 子命令的 wrapper
```

wrapper 用 `makeWrapper` 注入运行时依赖：`cliphist`、`wl-clipboard`、`wtype`、`glib`
（`gio launch`）、`libnotify`（降级通知 `notify-send`）、`fontconfig`（`fc-match`）、
`coreutils`，并把 `MAYON_OVERLAY_FONT`（Inter）与
`MAYON_OVERLAY_FONT_FALLBACK`（Maple Mono NF CN，静态 TrueType；nixpkgs 的 Noto Sans
CJK 2.004 是 fontdue 无法轮廓化的可变 CFF2 集合，所以不作为默认回退）指向 store 内字体。

## 运行

```sh
mayon-clipboard                  # Super+V
mayon-launcher                   # Super+A
mayon-overlay ctl state          # 默认自动尝试 clipboard/launcher 两个 socket
mayon-overlay ctl --socket "$XDG_RUNTIME_DIR/mayon-overlay-clipboard.sock" activate 0
```

常用参数（`--help` 有完整列表）：

| 参数 | 说明 |
|---|---|
| `--socket PATH` | 控制 socket；默认 `$XDG_RUNTIME_DIR/mayon-overlay-<mode>.sock` |
| `--log PATH` | JSON-lines 事件日志；默认 `$XDG_RUNTIME_DIR/mayon-overlay.log` |
| `--ready-file PATH` | 首帧提交后写入几何信息（自动化测试用） |
| `--font` / `--font-fallback` | 覆盖字体文件 |
| `--query TEXT` | 初始查询 |
| `--data-dir PATH` | 追加 XDG data 目录（启动器扫描 `applications/*.desktop`） |
| `--paste-keys CHORD` | 复制后注入的按键，默认 `ctrl+v`，`none` 关闭 |
| `--no-paste` | 只复制，不注入 |
| `--scale N` | 强制整数 buffer scale |

环境变量：`MAYON_OVERLAY_SOCKET`、`MAYON_OVERLAY_LOG`、`MAYON_OVERLAY_FONT`、
`MAYON_OVERLAY_FONT_FALLBACK`、`MAYON_OVERLAY_PASTE_KEYS`、`MAYON_OVERLAY_SCALE`、
`MAYON_OVERLAY_DATA_DIRS`（冒号分隔）、`MAYON_OVERLAY_DEBUG=1`（把按键/焦点事件写日志）。

同一 socket 上第二次启动会向已运行实例发送 `toggle` 并关闭它，因此同一个快捷键可按开/关。

### 控制协议

socket 是换行分隔的 JSON：请求一行命令，响应一行 JSON。

```
ping | state | query <text> | select <index> | activate [index] | click <x> <y> | close | toggle | reload
```

`state` 返回模式、查询、选中下标、条目列表，以及当前 `layout`（卡片与每行矩形，
逻辑像素），测试据此做点选与断言；`click` 与真实鼠标走同一命中/激活代码路径。

## 自动粘贴

选中条目后：

1. `cliphist decode <id> | wl-copy [--type <cliphist 记录的 MIME>]`；
2. overlay 销毁，键盘焦点回到原焦点窗口；
3. 等 160 ms 后调用 `wtype -M ctrl -k v -m ctrl`（`zwp_virtual_keyboard_manager_v1`），
   把 Ctrl+V 注入当前焦点应用；
4. 失败时降级为“已复制到剪贴板”通知（`notify-send`），并把 `wtype` 的 stderr 原因写入日志
   （`paste_failed` 事件）与通知正文。

已在私有 headless Mango 会话实测：Mango 广告
`zwp_virtual_keyboard_manager_v1` v1、`zwlr_layer_shell_v1` v4，自动粘贴成功
（`wev` 观测到 Control + `v`，见 `.work/overlay/` 证据）。

已知限制：默认 chord 是 GUI 常用的 `ctrl+v`，Kitty 等终端用 `ctrl+shift+v`。当前不查询
焦点应用类型，因此在终端里需要把它改成 `MAYON_OVERLAY_PASTE_KEYS=ctrl+shift+v`（或
`--paste-keys ctrl+shift+v`）运行；不注入时用 `--no-paste`，复制本身总是成功。compositor
不支持虚拟键盘协议时降级路径同上。

## 集成清单（由 lead 在主分支接线）

本 worktree 只注册了包工厂，没有改快捷键/Noctalia 配置：

1. `nix/pkgs.nix`：已加 `mayonOverlay = import ../packages/mayon-overlay { pkgs = final; };`。
2. 安装：在 `aspects/desktop/mango-session/` 的剪贴板 feature 的 `home.packages` 里加
   `pkgs.mayonOverlay`（`clipboard.nix` 现有 `home.packages` 列表即可）。
3. 快捷键 `aspects/desktop/mango-session/mango/keybinds.nix`：
   - `"SUPER,V,spawn,clipboard-history"` → `"SUPER,V,spawn,mayon-clipboard"`；
   - `"SUPER,A,spawn,noctalia msg plugin nix-dotfiles/launchpad:control all toggle"` →
     `"SUPER,A,spawn,mayon-launcher"`。
4. 删除/停用旧实现：`clipboard-history`（fuzzel 脚本）、Noctalia launchpad 插件及其
   `nix-dotfiles/launchpad` 接线；`cliphist`、`cliphist-images`、`wl-clip-persist`、
   `clipboard-bridge` 服务保持不变（历史库和 X11 桥接仍由它们提供，overlay 只是读取端）。
5. 不需要新增 systemd user service：overlay 是按快捷键启动的一次性前台程序，复制后
   `wl-copy` 会 fork 出常驻 selection owner（与旧绑定行为一致）。
6. 可选：把 `packages/mayon-overlay/tests/check.nix` 注册成
   `checks.x86_64-linux.mayon-overlay`（见下节）。

## 测试

自包含 headless 行为测试（Sway + 可选 Mango，真实 `cliphist`/`wl-copy`/`wtype`/`grim`）：

```sh
python3 packages/mayon-overlay/tests/headless_check.py --help
# 完整命令示例见 tests/check.nix 或 .work/overlay/EVIDENCE.md 中记录的实际执行命令
```

覆盖：文本 + PNG 历史构造，UI 打开与截图（背景/卡片/选中行/文字/缩略图像素断言），
键盘方向键选择 + Enter 复制，PNG 复制后 `wl-paste` 像素一致，自动粘贴（`wev` 观测
Control + v），启动器打字过滤/Enter/`gio launch` 产出 marker/点击激活/无图标断言，
唯一实例 toggle，`wtype` 缺失时的降级通知；Mango 场景额外断言虚拟键盘与 layer-shell
global、全屏覆盖与自动粘贴。

Nix check 接线（lead 合并时选择）：

```nix
# 主 flake 有 inputs.mango 时：
checks.x86_64-linux.mayon-overlay = import ../packages/mayon-overlay/tests/check.nix {
  inherit pkgs;
  mango = inputs.mango.packages.${system}.mango; # 可省，省略则只跑 Sway
};
```

`tests/check.nix` 用 `python3.withPackages [pillow]` 运行同一脚本，sandbox 内自建
`$XDG_RUNTIME_DIR`、fake HOME，不接触真实会话。已验证：sandbox 内 Sway 场景
30/30 checks 通过（输出目录含 `metrics.json` 与截图）；把 `mango` 参数传进来后
本机人工执行完整 40/40（Sway + 私有 headless Mango）。

## 已知限制

- 缩略图解码支持 PNG/JPEG（本机截图主要是 PNG）；其它图片 MIME 仍按 cliphist 记录的
  MIME 原样复制，只是列表里显示“无法解码”。
- 键盘输入使用 compositor 下发的 xkb keymap 转 UTF-8；没有实现 text-input/IME 协议，
  因此中文搜索依赖键盘布局直接产生对应字符，暂不支持输入法组字。启动器搜索是
  name/generic/comment/keywords/categories 的确定性排序（前缀 > 包含 > 其它），
  不包含拼音首字母。
- HiDPI 只用整数 buffer scale（`wl_output.scale`）；小数缩放输出下文字会被
  compositor 再次采样。
- 启动器不渲染图标，`Terminal=true` 的 desktop entry 仍由 `gio launch` 处理；
  需要终端包装的条目由 desktop 环境自己的 handler 决定。
