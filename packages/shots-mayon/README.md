# shots-mayon

截图与录屏的本地图库，One Dark 外观直接复用 `mayon-ui`。公开包工厂为
`default.nix { pkgs; }`，由 `pkgs.shotsMayon` 公开，由 Mango 截图功能追加安装。
现有 Print、mark-shot、wayscrollshot、OCR 快捷键及其保存设置均保持原样。

## 使用

```sh
shots-mayon                         # TUI，Kitty 图形缩略图
shots-mayon index                   # 增量索引 + 后台低优先级本地 OCR
shots-mayon index --no-ocr           # 仅索引元数据
shots-mayon search '关键词'          # JSON，包含 OCR 文字
shots-mayon search '2026-10' --kind image --source kitty
shots-mayon ocr pause                # 也中断本工具当前的 Tesseract 子进程
shots-mayon ocr resume
shots-mayon ocr run                  # 前台处理待识别项
shots-mayon record toggle            # 当前输出、静音；再次执行停止
shots-mayon record toggle --region
shots-mayon record toggle --window   # 点选可见 Mango 窗口的初始矩形
shots-mayon record toggle --output eDP-1 --system-audio --mic
shots-mayon record status
```

录屏文件：`~/Videos/Recordings/Recording-<时间>-<pid>.mkv`。默认 30 fps、
`libx264`、ultrafast、CRF 23、禁用 DMA-BUF，避免依赖可能断电的 NVIDIA。
MKV 便于中断后恢复；编码器错误会保留文件供检查，不删除任何录制内容。
`--encoder h264_vaapi --device /dev/dri/renderD128` 或
`--encoder h264_nvenc` 为显式硬件编码请求，必须先验证设备/驱动/编码器。
不会自动唤醒独显，也不会失败后悄悄开始另一种录制。

TUI：`1` 全部、`2` 截图、`3` 录屏、`4` 收藏；`j/k`、方向键、PageUp/Down、
鼠标选择/滚动；`/` 文件名/OCR/日期/类型搜索，`s` 来源过滤，`D` 日期前缀，
`Esc` 清空；`Enter/o` 打开，`y` 复制路径，`c` 复制图片，`t` 复制 OCR，
`f` 文件管理器定位，`e` 用现有 mark-shot 标注，`*` 收藏，`i` 索引，
`p` 暂停/恢复 OCR，`r` 录屏控制，`?` 帮助，`q` 退出。
`d` 后先确认文件，再按大写 `Y` 才调用 `trash-put`；没有永久删除入口。
文件管理器不支持 `org.freedesktop.FileManager1.ShowItems` 时退回打开父目录。

录屏不随 TUI 退出而停止：独立监督进程持有录制锁，通过私有 Unix socket
接受同命令 toggle；停止向自己的编码器发送 SIGINT，等待容器收尾。
不会从 PID 文件猜测进程并杀掉其他程序。启动、停止与异常退出通过
`notify-send` 告知桌面，开始通知为 critical、无过期时间；Noctalia 的真实显示、
DND 策略与通知历史需实机确认。不修改 Noctalia。

音频默认关闭。`--system-audio` 取当前默认 sink 的 monitor；`--mic` 取默认
source；两者同时选用时创建本次录制专属 null sink 和两个 loopback，
录制其 monitor，结束/错误时按逆序卸载模块。不更改默认设备。
机器断电、SIGKILL 等无法执行清理的情况可在 `pactl list short modules` 中
识别 `shots_mayon_<pid>` 相关模块，由主代理实机检查后清理。

## 索引边界与隐私

默认只扫描以下目录（含子目录，不跟随符号链接）：

- `~/Pictures/mark-shot`、`~/Pictures/wayscrollshot`
- `~/Pictures/Screenshots`、`~/Pictures/截图`、`~/Pictures/MarkShot`
- `~/Videos/Recordings`

mark-shot 的实际默认是 **XDG Pictures** 下 `mark-shot/`，并允许自己的
pathTemplate 覆盖；wayscrollshot 默认是 `~/Pictures/wayscrollshot`。
本工具不读取/重写它们的配置。自定义 XDG Pictures 或保存路径时，以
`~/.config/shots-mayon/config.json` 明确提供完整 roots 列表，例如：

```json
{"roots":["~/Pictures/mark-shot","~/Pictures/wayscrollshot","~/Pictures/Screenshots","~/Videos/Recordings"]}
```

不会扫描整个 HOME。原媒体索引只读，不移动或删除；用户明确选择标注、回收站
操作后才由对应工具处理原文件。未知来源保留空白，不推测历史截图来自哪个窗口。
本工具窗口录屏记录所选 `app_id · title`；已有截图如有受信任的
`<文件名>.shots.json`（`{"source":"kitty · project"}`）可搜索来源。
普通截图工具没有提供这些元数据，安装本工具也无法追溯补全。
窗口录屏捕获的是固定逻辑矩形，窗口移动、缩放、遮挡或跨屏后不会跟随。

状态目录为 `${XDG_DATA_HOME:-~/.local/share}/shots-mayon`，权限 0700：
`library.sqlite3`（WAL，路径/时间/类型/来源/OCR/收藏/暂停状态）、`thumbs/*.png`、
`ocr.lock`、`ocr.log`、`toggle.lock`、`recording.lock`、`record.sock`、`record.log`。
进程 umask 0077，状态文件/缩略图/录屏/元数据为 0600。
配置遵循 XDG_CONFIG_HOME；本程序不会主动生成配置文件。
SQLite 按纳秒 mtime+size 增量更新；文件变化后清空旧 OCR，保留收藏。
OCR 为本地 Tesseract chi_sim+eng，通过 nice/ionice 低优先级串行处理，
可暂停，单图有超时；没有云 OCR、遥测或媒体上传。
预览通过受限本地 FFmpeg 转 PNG，再使用 Kitty 图形协议；其他终端显示文字详情。

移除包只移除程序和安装接线，保留全部截图、录屏、索引、收藏和 OCR 数据。
若主动清理状态目录将失去索引/OCR/收藏，原文件仍在。索引和缩略图可能含敏感信息，
不应提交、共享或置于公开目录。

## 选型依据

- 参考 [wf-recorder v0.6.0](https://github.com/ammen99/wf-recorder/tree/v0.6.0)
  的 wlr-screencopy 输出/区域捕获、FFmpeg 编码和单 PulseAudio source 模型。
  锁定 Mango `9c44c664725421fbccaf2619e3641b38614db04d` 的
  [`src/main.c`](https://github.com/mangowm/mango/blob/9c44c664725421fbccaf2619e3641b38614db04d/src/main.c)
  注册 `wlr_screencopy_manager_v1_create`，满足捕获协议前提。
- 比较 [GPU Screen Recorder](https://github.com/Dec05eba/gpu-screen-recorder)：
  硬件编码和多音源直接，但 portal/设备能力取决于驱动及独显供电。
  这里选择 wf-recorder 软件编码作为基线，不把 NVENC 当作恒定可用。
- 参考 [Kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/)
  的分块 PNG 传输；界面使用仓库 mayon-tui 的共享组件，不引入新主题。
- mark-shot 锁定 `9dcc564776e1b7f53ed28130e1e03e8f2ab2a97f` 的
  `qt/src/save_path_config.cpp` 和 `qt/src/main.cpp` 确认保存目录和位置参数标注；
  wayscrollshot 锁定 `703474ad7b94a504306d7a93d21668ee162ebf1c` README 确认默认路径。

## 验证与待验

包构建运行 Rust 单元测试、rustfmt 与 clippy `-D warnings`。
`tests/isolated.py` 生成合成图片、使用私有 HOME/D-Bus/runtime、headless sway
2560×1600 scale 1.5 和真实 Kitty，验证 OCR 搜索、宽/窄布局、确认弹窗及静音录屏。
必须传入独立 artifact 根目录和包含依赖的 PATH；它从不继承用户的会话环境。
保存 gallery.html、overview.png、逐张截图和 ffprobe JSON，不录真实屏幕/音频。

必须由主代理应用后实机核验：Mango+Intel/NVIDIA 的实际编码速度、缩放/多屏/负坐标、
窗口选择矩形、硬件编码能力、系统声/麦克风及混音后的音画同步、设备切换、
Noctalia 录制通知持续可见/停止提示、真实剪贴板、文件管理器定位、mark-shot 标注、
回收站恢复。构建、隔离 sway 测试不能证明这些项目已通过。
