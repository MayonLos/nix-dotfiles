# 桌面真实运行 E2E（runtime-e2e）

这是**真实调用型**测试套件：直接运行桌面上的真实程序、真实截图（`grim`）、真实读写文件与
D-Bus，而不是 Nix 求值断言。它和 `tests/composition/`（求值/构建 fixture）是不同证据层级：
这里的结果只说明“当前 live 系统实际怎么跑”，配置检查仍由 `nix flake check` 负责。

设计目标有两条：

1. 能对**当前 live 系统**跑出真实基线（包括已知 bug 的真实 FAIL）；
2. 在 lead 下次 `nr` 之后**原样复跑**，用同一套断言验证修复，而不需要改测试代码。

## 一键运行

```sh
# 在仓库任意位置：
python3 tests/runtime/run.py

# 只跑某些类别 / 单个测试：
python3 tests/runtime/run.py --categories services,bar,osd
python3 tests/runtime/run.py --only mark-shot/capture-size
python3 tests/runtime/run.py --list

# 指定证据目录（默认 <repo>/.work/e2e/<时间戳>/）：
python3 tests/runtime/run.py --artifact-dir /tmp/e2e-run

# 额外写一份 JSON：
python3 tests/runtime/run.py --json /tmp/e2e-report.json
```

依赖：登录会话内已有的 `grim`、`mmsg`、`ImageMagick`（`magick`/`identify`）、
`busctl`、`journalctl`、`systemctl`、`wl-clipboard`、`cliphist`、`notify-send`、
`makoctl`、`swayosd-client`、`mark-shot`、`noctalia`、`mangobar` 等（都在现有用户/系统
profile 里，套件不额外安装）。Python 只用标准库。

退出码：`0` = 没有 FAIL（SKIP 不算通过，但也不让整套失败）；`1` = 至少一个 FAIL；
`2` = 参数/选择错误。

### 输出

每次运行在证据目录写入：

| 文件 | 内容 |
|---|---|
| `report.json` | 完整报告：环境快照、逐测试 status/expected/observed/data/artifacts、分类统计 |
| `environment.json` | 系统 generation、git 分支/commit/dirty、monitor/scale、palette 来源、live 会话信息 |
| `commands.log` | 实际执行过的每条命令、退出码、stdout/stderr（截断） |
| `<category>/*.png` | 真实截图证据（顶栏、OSD、通知卡片、Launchpad、mark-shot 编辑器、greeter、私有 mangobar 等） |

stdout 会打印逐测试行、分类矩阵、FAIL/SKIP 清单。证据 PNG 只落在 `.work/`（已 gitignore），
不提交大图。

## 分类与测试矩阵

类别名即 `--categories` 的取值；id 即 `--only`/`--exclude` 的取值。

| id | 检查内容 | 真实调用 |
|---|---|---|
| `services/user-units` | mangobar/mako/swayosd/cliphist/cliphist-images/wl-clip-persist active | `systemctl --user is-active` |
| `services/system-backend` | `swayosd-libinput-backend.service` active，且系统 bus 名 `org.erikreider.swayosd` 由该 root 进程持有 | `systemctl is-active`、`busctl --system list`、`ps` |
| `services/failed-units` | `systemctl --user --failed` 为空 | 真实 systemd 查询 |
| `services/restart-stability` | 上述单元 `NRestarts` 无崩溃循环 | `systemctl show -p NRestarts` |
| `services/journal` | 相关单元最近 2h journal 的 error/warn/fail 分类；系统 1h coredump 归因；backend 单元日志 | `journalctl --user -u ...`、`journalctl -b`、`journalctl -u swayosd-libinput-backend` |
| `services/session-env` | `XDG_SESSION_ID` 是否注入 user manager（R41 复核项；旧会话为 SKIP 并注明重新登录） | `systemctl --user show-environment` |
| `bar/config` | mangobar `height=30` 逻辑 px、layer=top、layout/workspaces + tray/clock 模块、`#bar` 透明、Mango `no_blur:1` layer_rule | 读 `~/.config/mangobar/{config.jsonc,style.css}`、`~/.config/mango/config.conf` |
| `bar/transparency` | 顶栏 45 物理 px 内壁纸透出、无纯色填充，且有 palette 文字像素 | `grim -o eDP-1` + 逐行主色占比/颜色计数 |
| `bar/modules` | 左/中/右三分区真实绘制（active workspace 蓝色、窗口标题、右侧 tray/clock） | 截图像素采样 |
| `bar/geometry` | 像素测得窗口顶边 == `mmsg` client.y×scale == 配置 bar 高度（45px） | `mmsg get focusing-client` + 截图像素 |
| `bar/tray-items` | `org.kde.StatusNotifierWatcher` host 已注册且有 ≥1 个真实 SNI item | `busctl --user call ... Properties.Get` |
| `osd/config` | swayosd `top_margin` 与源码公式 `(logicalHeight-96-26)/logicalHeight` 一致、`show_percentage=true` | 读 `~/.config/swayosd/config.toml`、`mmsg` |
| `osd/caps-lock` | `swayosd-client --caps-lock` 的 pill 真实出现、紧凑尺寸、底部居中、palette 颜色、自动消失且恢复基线 | 真实命令 + 触发前后 `grim` 差分 |
| `osd/num-lock` | 同上（`--num-lock`） | 同上 |
| `osd/output-volume` | `--output-volume raise` 的 OSD 含蓝色进度条，测试后恢复原音量 | 同上 + `wpctl get/set-volume` |
| `notifications/config` | mako 360 逻辑 px、`outer-margin=42,28,0,0`、`margin=0,0,8,0`、One Dark 颜色、`on-notify=pw-play ...` | 读 `~/.config/mako/config` |
| `notifications/daemon` | mako 独占 `org.freedesktop.Notifications` 且只有 1 个进程 | `busctl --user call`、`ps` |
| `notifications/card` | `notify-send` 后卡片真实出现：宽≈540 物理 px、右边距≈42px、顶部在 bar 下 42 逻辑 px、文字/边框像素 | `notify-send` + `makoctl list` 归属 + `grim` |
| `notifications/dismissed` | `makoctl dismiss --all` 后卡片消失 | 截图对比 |
| `notifications/on-notify-sound` | 从 config 提取 `on-notify` 的真实 `pw-play` 命令并执行一次，记录退出码（无声卡时允许非零，记为降级） | `bash -c <on-notify>` |
| `clipboard/text-roundtrip` | 文本 `wl-copy → wl-paste → cliphist list → decode → wl-paste` | `wl-clipboard`/`cliphist` |
| `clipboard/image-roundtrip` | 生成 96×64 PNG → `wl-copy --type image/png` → cliphist 条目 → decode → `wl-paste`，sha256/尺寸一致 | 真实 PNG 字节往返（并发占用剪贴板时 SKIP 并注明） |
| `clipboard/super-v-preview` | SUPER+V 绑定是否仍是无图片预览的 fuzzel 流（**当前基线 FAIL**） | 读 live Mango config + 解析绑定脚本 |
| `mark-shot/version` | 真实 `mark-shot --version` | 命令 |
| `mark-shot/list-displays` | `--list-displays` JSON 与 mmsg 的 active/scale 一致，并记录逻辑尺寸取整（1707×1067）作为 2561 像素 bug 的根因候选 | 命令 |
| `mark-shot/capture-size` | `--capture-to` PNG 物理尺寸必须等于 `grim`（**当前基线 FAIL：2561×1601 vs 2560×1600**） | 真实截图 + ImageMagick |
| `mark-shot/copy` | `-m -f -t c` 复制到剪贴板的 PNG 尺寸/完整性（**当前基线 FAIL：尺寸差 1px，且读出被截断**） | 真实命令 + clipboard 读取 |
| `mark-shot/editor` | `--fullscreen` 编辑器真实出现（client/layer），保存截图后由测试进程立即关闭 | `mmsg get all-clients/all-layers` + `grim` |
| `mark-shot/editor-cleanup` | 测试后 live 会话无 mark-shot surface 残留 | `mmsg` 复查 |
| `launcher/binding` | SUPER+A 绑定与实现可用性（Noctalia Launchpad 或移除后的新启动器） | 读 live Mango config、`noctalia` |
| `launcher/noctalia-open` | 真实 toggle 打开 Launchpad：layer 名 `noctalia-plugin:nix-dotfiles/launchpad:drawer`，中心区域像素显著变化 | `noctalia msg plugin ... toggle` + `grim` |
| `launcher/noctalia-closed` | 关闭后无 drawer 残留层 | `mmsg get all-layers` |
| `greeter/render` | 私有 headless Sway（与 greeter 相同的 sway store 路径）+ 真实 `gtkgreet` + 当前 `/etc/greetd/gtkgreet.css` 渲染登录卡片 | 真实进程 + `grim`，无 PAM |
| `tray/mangobar-render` | 私有 headless Sway 中真实 mangobar 创建 layer surface 并绘制 clock | 真实 mangobar 二进制 |
| `tray/menu-open` | tray 菜单点击：**未能自动验证**（见下） | 真实探测 seat capability 后记录 SKIP |
| `session/cleanup` | 套件结束后无 Launchpad/mark-shot 覆盖层残留 | `mmsg` + `makoctl` |

## 安全边界（重要）

套件可以在用户正在使用的 live 会话里运行，它遵守：

- **不用 sudo**；不 `nixos-rebuild`；不修改 `~/.config`（只读检查）；不启停/重置任何
  真实 systemd 单元；不 kill 用户进程。
- live 会话操作全部轻量且自带恢复：截图、一次 `notify-send` + `makoctl dismiss`、一次
  OSD 触发（临时改音量会还原）、一次 Leadpad toggle（结束后必须关闭）、一次
  `mark-shot --fullscreen`（测试自己 spawn、自己终止、结束后复查残留）、剪贴板写入
  （前后保存/恢复原内容）。
- 私有环境（greeter/tray）完全隔离：私有 `HOME`/XDG、0700 `XDG_RUNTIME_DIR`、私有
  session D-Bus、系统 bus 指向不存在的 socket、`WLR_BACKENDS=headless`；不继承 live
  `WAYLAND_DISPLAY`/`SWAYSOCK`/`DISPLAY`；结束（含异常）删除临时根目录。
- 所有被套件写出的内容都在证据目录/临时目录里；live 会话里不留下覆盖层或窗口。

## 状态语义

- `PASS`：断言真实执行并通过。
- `FAIL`：断言真实执行并失败，`data`/`expected`/`observed` 里带数字证据。已知 bug 也如实
  FAIL，用于 `nr` 后对照。
- `SKIP`：环境不提供该测试面（无 live 会话、Noctalia 已移除、并发占用剪贴板等）或明确
  未自动化。**SKIP 永远不会被算作通过**。

## 当前 live 基线（2026-11-15，system-32 / base `804af3f`）

连续两次完整运行的真实结果：**36 项中 PASS 31、FAIL 3、SKIP 2**（分类见 `report.json`；
两次结果一致，`FAIL` 全部是已知待修 bug）。真实失败清单（`nr` 后必须复核）：

| 失败项 | 数字证据（两次运行） |
|---|---|
| `mark-shot/capture-size` | `--capture-to` 输出 `2561×1601`，`grim` 物理尺寸 `2560×1600`，差 1×1（`--list-displays` 报逻辑尺寸 1707×1067，×1.5 后向上取整正是根因候选） |
| `mark-shot/copy` | 复制到剪贴板的 PNG 头也是 `2561×1601`，且 `wl-paste` 读出的 PNG 被截断（65536 / 196608 字节，ImageMagick 无法完整解码）——现有实现让复制数据在 owner 退出时丢失尾部 |
| `clipboard/super-v-preview` | `SUPER,V` 仍绑定 `clipboard-history`（`cliphist list | fuzzel --dmenu`），图片条目只能显示 binary placeholder，无图片预览 |

SKIP 清单：

| SKIP | 原因 |
|---|---|
| `services/session-env` | 当前图形会话在 system-32 激活前建立，user manager 里 `XDG_SESSION_ID` 为空；重新登录后复核 |
| `tray/menu-open` | 未自动化，见下 |
| 偶发 `notifications/*`、`clipboard/*`、`bar/geometry` | live 会话同时被其它自动化占用（通知/剪贴板竞争、焦点窗口浮动）时 SKIP 并注明；安静会话复跑即可。`bar/geometry` 已优先用 focused tiled client，浮动时自动回退到任一可见 tiled client |

## `nr` 之后重点复核

1. **mark-shot**：`mark-shot/capture-size`、`mark-shot/copy` 必须从 FAIL 变 PASS（尺寸
   2560×1600、剪贴板 PNG 完整）；`mark-shot/editor` 不能因新编辑器/媒体库变化而残留。
2. **剪贴板**：`Super+V` 是 cliphist + fuzzel，`clipboard/super-v-preview` 以此为通过；
   图片在列表里是文字占位，`clipboard/image-roundtrip` 仍须无损。
3. **mangobar tray One Dark**：`bar/config`、`bar/transparency`、`bar/tray-items` 会按新
   的 live `config.jsonc`/`style.css` 重新取期望值；如果 tray 配色/模块名变化，`bar/modules`
   的右三分区仍有 palette 像素即可通过，具体颜色断言按 palette 源码自适应。
4. **启动器**：`launcher/binding` 要求 `Alt+Space` 为 fuzzel 且没有 `Super+A` 启动绑定。
   `launcher/noctalia-*` 在 Noctalia 不在时 SKIP。覆盖层用例只在会话仍绑定
   `mayon-launcher` / `mayon-clipboard` 时才打开。
5. **OSD/greeter**：`osd/*` 不依赖 Noctalia；`greeter/render` 从 `/etc/greetd/sway.conf`
   动态发现 gtkgreet/CSS，`nr` 后自动使用新 generation 的真实二进制与 CSS（`data.css_sha256`
   会变化，这是预期）。
6. **XDG_SESSION_ID**：重新登录后 `services/session-env` 应从 SKIP 变 PASS；若仍为空，
   说明 Mango 早期环境钩子未生效（desktop README R41）。

## 未自动化项及原因

| 项 | 原因 / 现状 |
|---|---|
| tray 菜单**点击打开**（`tray/menu-open`） | 私有 headless Sway 的 seat 没有 pointer capability（`swaymsg -t get_seats` 实测 `capabilities=[]`），`swaymsg seat - cursor set/press` 虽然返回 success 但不投递事件；真实菜单还需要真实 SNI item + wlr-virtual-pointer 客户端（本仓库 tray 分支的 `session-test` 正在实现）。套件已把 capability、mangobar 依赖和失败原因写入 `tray/tray-menu-evidence.json`，明确 SKIP，不伪装通过。 |
| mangobar tray 在 live 会话的点击 | live Mango 没有 IPC/工具可以注入指针或打开 tray 菜单；`mmsg dispatch` 不含鼠标事件。 |
| Caps/Num Lock **物理按键**路径 | 无法在无人值守测试里按物理键盘；`swayosd-client --caps-lock/--num-lock` 已能真实触发 OSD，root backend→system bus 的链路由 `services/system-backend` 验证。 |
| mark-shot 编辑器交互（标注/保存/钉图） | 需要键盘/鼠标交互；套件只验证编辑器真实出现与清理，不模拟画布操作。 |
| Noctalia 新启动器的交互式打开/关闭 | 未实现前（`launcher/binding` 检测到非 Noctalia 绑定时 SKIP 并注明）；新启动器若有非交互 CLI 可在此扩展。 |
| PAM 登录/锁屏解锁 | 需要真实凭据，明确不在本套件范围。 |
| 真实 GPU 模糊质量 | 截图像素可验证“无填充/无模糊带”，但真实的 dual-Kawase 采样质量仍属 `mango-blur-sampling` 等专项检查。 |

## 私有 greeter harness 说明

`greeter/render` 复刻主仓库 `.work/preview/greeter/harness/run-preview.sh` 的隔离契约，
但完全自包含在 `tests/runtime/private.py` + `tests/runtime/greetd_stub.py`：

- gtkgreet 可执行文件、CSS、`-c` 登录命令都从 **当前** `/etc/greetd/sway.conf` 解析，
  `nr` 后自动跟随新 generation；
- `greetd_stub.py` 用 greetd 的 4-byte LE 长度 + JSON 协议守住 `GREETD_SOCK`，不做任何
  认证，只保证 gtkgreet 能真实渲染登录卡片；
- headless 输出 `2560×1600 @ scale 1.5`（grim 在 headless 上取整为 `2560×1599`，断言接受
  这两个高度）；截图与当前 CSS 的 hex 颜色命中一起证明“真实二进制 + 当前 CSS”都生效。

## 加新测试

在 `tests/runtime/live.py` 或 `tests/runtime/private.py` 写一个
`def test_xxx(ctx: Ctx) -> Result`，然后用 `Result.passed/failed/skipped` 返回；真实命令统一
走 `ctx.exec([...])`（会进 `commands.log`），截图用 `ctx.screenshot(...)`，像素分析用
`tests/runtime/pixels.py`。最后在 `tests/runtime/run.py` 的 `TESTS` 表里登记
`(id, category, title, function)` 即可。

flake 入口未加：`nix/` 正在被其它分支（Noctalia 删除）修改，避免冲突。需要 Nix 环境时直接
用现有系统的 `python3`：`python3 tests/runtime/run.py`，或用
`nix shell nixpkgs#python3 --command python3 tests/runtime/run.py`。
