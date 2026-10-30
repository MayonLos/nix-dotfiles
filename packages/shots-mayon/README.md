# shots-mayon

本地截图图库，One Dark 外观复用 `mayon-ui`。公开包工厂为
`default.nix { pkgs; }`，由 `pkgs.shotsMayon` 公开，再由 Mango 截图功能安装。
现有 Print、mark-shot、wayscrollshot、OCR 快捷键及保存设置保持原样。

## 使用

```sh
shots-mayon                         # TUI，Kitty 图形缩略图
shots-mayon index                   # 增量索引 + 后台低优先级本地 OCR
shots-mayon index --no-ocr          # 仅索引元数据
shots-mayon search '关键词'          # JSON，包含 OCR 文字
shots-mayon search '2026-10' --source kitty
shots-mayon ocr pause                # 也中断本工具当前的 Tesseract 子进程
shots-mayon ocr resume
shots-mayon ocr run                  # 前台处理待识别项
```

图库只索引截图。`1` 截图、`2` 收藏；`j/k`、方向键、PageUp/Down、
鼠标选择/滚动、g/G 首尾；`/` 文件名/OCR/日期搜索，`s` 来源过滤，`D` 日期前缀。
搜索和来源使用共享大小写不敏感中文/拼音多词 AND 匹配。输入立即更新列表，
Enter 保留结果，输入中 Esc 恢复打开前过滤，列表 Esc 清空；输入中方向键仍选择截图。
过滤和刷新按路径保持选择；标题显示匹配数/总数。输入支持光标编辑和单行粘贴；
`Enter/o` 打开，`y` 复制路径，`c` 复制图片，`t` 复制 OCR，`f` 文件管理器定位，
`e` 用现有 mark-shot 标注，`*` 收藏，`i` 索引，`p` 暂停/恢复 OCR，`?` 帮助，
`q` 退出。`d` 后先确认文件，再按大写 `Y` 才调用 `trash-put`；没有永久删除入口。
文件管理器不支持 `org.freedesktop.FileManager1.ShowItems` 时退回打开父目录。

## 索引边界与隐私

默认只扫描以下目录（含子目录，不跟随符号链接）：

- `~/Pictures/mark-shot`、`~/Pictures/wayscrollshot`
- `~/Pictures/Screenshots`、`~/Pictures/截图`、`~/Pictures/MarkShot`

mark-shot 的实际默认是 **XDG Pictures** 下 `mark-shot/`，并允许自己的
pathTemplate 覆盖；wayscrollshot 默认是 `~/Pictures/wayscrollshot`。
本工具不读取/重写它们的配置。自定义 XDG Pictures 或保存路径时，以
`~/.config/shots-mayon/config.json` 明确提供完整 roots 列表，例如：

```json
{"roots":["~/Pictures/mark-shot","~/Pictures/wayscrollshot","~/Pictures/Screenshots"]}
```

不会扫描整个 HOME。原截图索引只读，不移动或删除；用户明确选择标注、回收站
操作后才由对应工具处理原文件。未知来源保留空白，不推测历史截图来自哪个窗口。
已有截图如有受信任的 `<文件名>.shots.json`（`{"source":"kitty · project"}`）可搜索来源。
普通截图工具没有提供这些元数据，安装本工具也无法追溯补全。

状态目录为 `${XDG_DATA_HOME:-~/.local/share}/shots-mayon`，权限 0700：
`library.sqlite3`（WAL，路径/时间/类型/来源/OCR/收藏/暂停状态）、`thumbs/*.png`、
`ocr.lock`、`ocr.log`。进程 umask 0077，状态文件/缩略图/元数据为 0600。
配置遵循 XDG_CONFIG_HOME；本程序不会主动生成配置文件。
SQLite 按纳秒 mtime+size 增量更新；文件变化后清空旧 OCR，保留收藏。
OCR 为本地 Tesseract chi_sim+eng，通过 nice/ionice 低优先级串行处理，
可暂停，单图有超时；没有云 OCR、遥测或媒体上传。
预览通过受限本地 FFmpeg 转 PNG，再使用 Kitty 图形协议；其他终端显示文字详情。

移除包只移除程序和安装接线，保留截图、索引、收藏和 OCR 数据。用户已有的
`~/Videos/Recordings` 录屏文件不受本工具管理，也不会被删除。主动清理状态目录
会失去索引/OCR/收藏，原截图仍在。索引和缩略图可能含敏感信息，不应提交、共享
或置于公开目录。

## 验证与待验

包构建运行 Rust 单元测试、rustfmt 与 clippy `-D warnings`，并执行私有 HOME 的
mock runtime 检查。`tests/isolated.py` 使用合成图片、私有 HOME/D-Bus/runtime、
headless sway 2560×1600 scale 1.5 和真实 Kitty，验证 OCR 搜索、宽/窄布局与确认弹窗。
必须传入独立 artifact 根目录和包含依赖的 PATH；它不继承用户会话环境。

实机仍需核验真实剪贴板、文件管理器定位、mark-shot 标注和回收站恢复。
构建和隔离 sway 测试不能证明这些项目已通过。
