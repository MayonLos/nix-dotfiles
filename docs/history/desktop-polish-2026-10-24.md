# 2026-10-24 Mango / Noctalia 桌面美化

工作目录：隔离 worktree `/home/mayon/nix-dotfiles-r9`，分支 `polish-desktop`，起点
`31aa8b6`。本轮只修改声明、文档与检查，不执行 sudo、rebuild、激活、Git 暂存/提交/推送，
不写 Noctalia 运行态。One Dark Darker、Mango + Noctalia、现有绑定语义保持。

## 依据与设计

锁定 Mango `900b8d7e06c396a20b6d4e56f242c4e240a69dfa`（0.18.3），Noctalia
`5f864d472676c77e5310881b243f15cc371bb223`（5.3.0），greeter
`8cc00abfdce3d8c1e68709a44eb0efc055932ada`。源码分别为：

- Mango：`/nix/store/qcya6bfk3h3f291ca9jidjfnlrx7l32x-source`。
- Noctalia：`/nix/store/0k6cwl09arhpjvg50lfnr12xcdfhb0w4-source`。
- Greeter：`/nix/store/flkc3702bzgyl6y19nl933mwkx8yw3jf-source`。

社区参考不是配置 schema；所有字段均再与锁定源码核对：

- [Noctalia 官方 Mango 指南](https://docs.noctalia.dev/noctalia/compositor-settings/mango/)：
  `blur_layer=0`、`layer_animations=0`；示例将阴影交 Mango 并关闭 shell 阴影。本仓库选择
  另一种已有分工：Noctalia 画自身 layer，Mango `layer_shadows=0`，只给浮窗画阴影。
- [Mango #1196](https://github.com/mangowm/mango/issues/1196)：layer shell blur 与圆角裁切
  的公开报告，最初版本为 0.15.2，不能外推为本机 0.18.3 已复现，也不能声称关模糊修复所有
  圆角问题。锁定 `docs/visuals/effects.md:8–23` 同样提醒 blur 有性能开销。
- [armin/mango-config](https://codeberg.org/armin/mango-config)：2026-10-24 经 raw main
  读取的 `config.conf:30–54` 实际为 animations=0、move/open/close=350、tag=0、open 曲线
  `0.46,1.0,0.29,0.99`。它与任务中的“约 250ms”线索不同；不将该线索写成实测事实。
  本轮采用接近 250ms 的 240ms 开场，属于本仓库的设计选择，没有复制其旧字段拼写或全局动画开关。

视觉刻度写入 [桌面设计](../desktop-design.md#视觉刻度)：8/12/16 圆角、1px 装饰描边、
2px 窗口焦点描边、4/6/8 内间距、10/12/16 外间距。Noctalia 和 greeter 的原生 6/9/12
圆角乘 `4/3`（局部内容缩放为 1 时）得到 8/12/16；bar、锁屏独立尺寸显式指定。
不是所有圆形控件和极小控件都强行套用同一半径。

## Mango：逐项决策

实现：[mango.nix](../../aspects/desktop/mango-session/mango.nix)。默认值以
`src/config/option_defs.c` 为准；其 `docs/configuration/miscellaneous.md:26` 把
`drag_tile_to_tile` 默认写为 0，但实际初始化 `option_defs.c:2470` 为 1，本轮保留实际行为。

| 选项 | 最终取值 / 决策 | 理由与锁定证据 |
| --- | --- | --- |
| `title_message_bar_*` | 全部 12 项显式设置 | `docs/visuals/theming.md:112–123`；`option_defs.c:637–715,930–933`。修复继承 group bar 的 Tokyo/Gruvbox 默认色 |
| title 字体 / 色彩 | `palette.fonts.sans + " 10"`；普通 fg/deep，聚焦 black/blue，border | 与 tab 同源；`title_message_bar.c:12–28` 实际渲染标题和 app-id 两行，并设为 focus 状态 |
| title 几何 | height 48、gap 12、border 1、radius 8、padding 8/4 | 两行 Inter 10 需要比 32px 单行 tab 更多空间；`draw/text-node.c:729,961–970` 有可用高度裁切，两行不宜挤成 32/36；仍待中文长标题实机验收 |
| `root_color` / `drop_color` / `split_color` | palette.bg / blue+0x80 / cyan | `option_defs.c:953–1032,2682–2697` 原默认灰底/粉拖放/红橙分割提示，补齐画布与交互提示色 |
| `overcircle_center_ratio` | 0.60（原 0.5） | 提高 1.5x 内屏预览内容可读性，保留两侧预览；`docs/window-management/overview.md:154`，范围 0.1–0.9 |
| `cursor_hide_timeout` | 显式 0（默认） | 保持静止指针可找；已有 `cursor_hide_on_keypress=1` 仍在打字时隐藏；misc 文档 :24 |
| `focus_on_activate` | 显式 1（默认） | 保持 launcher/应用激活聚焦，不引入焦点策略变化；misc :21 |
| `monocle_no_border` / `monocle_no_gap` | 显式 0/0（默认） | 与单窗口一致，保留蓝色焦点、外框和空隙；layouts 文档 :131–132 |
| `no_radius_when_single` | 显式 0（默认） | 单窗口仍圆角 12；effects 文档 :62 |
| `enable_border_resize` / `border_resize_size` | 1 / 8（原默认 1/10） | 保留无修饰边缘拖拽，减小侵占客户端边缘控件的抓取区域；misc :59–60。Super+右键、resize mode 保持 |
| `drag_tile_to_tile` | 显式 1（实际默认） | 保持现有拖放交换行为；`option_defs.c:2470`、FAQ :8–11 |
| `group_bar_*` 高度 / 按钮 | height 32、close=0、button size 16/margin 8/color palette.red | 高度与 tab 对齐，避免重复关闭按钮；备用色也不留上游红棕色；theming :73–87 |
| `jump_labels` | 显式 `HJKLASDFGQWERTYUIOPZXCVBNM`（默认） | 与现有 US 布局、HJKL 习惯兼容，不新增绑定；overview :104–108 |
| `shield_when_capture` | 不加规则，保留每窗/每层默认 0 | 它是 window/layer rule 字段，不是全局布尔；rules 文档 :43,254。没有用户指定敏感 app，不用宽泛规则让共享黑屏 |
| `tag_carousel` | 显式 0（默认） | 不改变 tag 两端导航语义；misc :58 |
| `warp_cursor` | 显式 1（默认） | 保持键盘焦点时指针跟随，与 sloppy_focus 配合，尽量兼容习惯；misc :23 |
| `blur` / `blur_layer` | 0 / 0，移除不用的 blur_params | Kitty 背景不透明，Noctalia 阅读面板 solid；没有已声明透明客户端受益。不承诺已测省电幅度 |
| 阴影 | shadows=1、only_floating=1、layer_shadows=0 | size 10/blur 20/offset 0,5/color 0x00000059 保留；避免平铺黑缝与双阴影 |
| 动画 | open/tag 240、move 180、close 160、focus 0 ms | 轻微 zoom 0.94/0.96 与 fade 保留；开/移/换 tag/fade-in 为 `0.16,1,0.3,1` ease-out，关/fade-out 为 `0.4,0,1,1` ease-in，无回弹；animations 文档 :80–90 支持 Bézier |
| 减少动画 | 继续共享 `palette.reducedMotion` | 不改既有 reduced-motion 分支，组合检查会调用真实 parser 验证两个用户分支 |

未新增 all_tag 或其他按键。现有 `Super+Alt+J/K` overcircle、`Super+Alt+T` switcher、
`Super+Shift+0` jump 继续有效；[工作流文档](../workflow-design.md) 补充这些已有入口，
帮助继续由原 `mango/keybinds.nix` 的数据生成。

## Noctalia：逐项决策

实现：[noctalia.nix](../../aspects/desktop/mango-session/noctalia.nix)、
[bar.nix](../../aspects/desktop/mango-session/noctalia/bar.nix)、
[greeter.nix](../../aspects/desktop/greeter/greeter.nix)。
下表 `schema` 指锁定 `src/config/schema/config_schema.cpp`。

| 项目 | 最终取值 / 取舍 | 锁定证据 |
| --- | --- | --- |
| 各 tag 胶囊应用图标 | regular 固定 1–9 保留；此版本不支持各胶囊显示应用图标 | `docs/user/bar/widgets/workspaces.mdx:8–20`；`workspaces_widget.h:102–103`、`workspaces_widget_definition.cpp:111–117`：show_icons 只对 focus_hint 的当前活动应用生效，regular 不绘图标 |
| 数据能力 | Mango 提供 appIds/window assignments，但 widget 不消费为各 tag 图标 | `src/compositors/mango/mango_workspace_backend.cpp:169–218`，不把 UI 缺失归因于后端 |
| taskbar | 不加 pinned-only 或 grouped running taskbar | taskbar 文档支持 `show_running=false`；独立 taskbar 重复 launcher pins/工作区信息，running 模式无每组图标数量上限；宽度不受约束 |
| 布局预算 | 左段 ≤640、中 ≤200、右 ≤570 仍为待验预算 | regular 九胶囊几何下界约 `8×16 + 24 + 8×4 = 184px`（`workspaces_widget.cpp:34–39,895–914`）；最终宽度还随字体、胶囊与内容变化，不宣称已经测量满足 |
| 浮动 panel | 保持 solid、outline/1、shadow=true | schema :1472–1473；outline 来自 palette.border，已有正确字段无需为了 diff 重写 |
| notification / OSD | 显式 `border_color="outline"`、width=1；OSD 显式 border=true | schema :109–111,302–304；避免继承未来默认色/宽，alpha 0.97 保留 |
| tooltip | `bar.main.show_tooltip=true` | schema :2593；固定 bar 默认，既有逐 widget tooltip 继承 |
| launcher | `layout="full"` 保持新版；category_icons_only=true、track_usage=true、sort_by_usage=true | shell 文档 :120,358–362；schema :1541,1549–1550，simple 是旧简化布局；保留应用名称/副标题、搜索入口和 pins |
| calculator provider | 改为 `providers.calculator.global=false` 具名 table | schema :1557–1562、shell 文档 :126,374–376；原数组产生 `expected a table, found an array`，仅 `/calc` 的原设计未被正确加载；此次修正实际生效 |
| 全局关闭按钮 | `shell.show_close_buttons=false` | schema :1785；shell 文档 :292 明确 panel/popups 可 Esc/外点、dialogs 可 Cancel/Esc、toast 右键、Settings 用 compositor 关闭，原生 window switcher 不受影响 |
| 锁屏密码显示 | login box `show_password_reveal=true` | lockscreen/widgets 文档 :95、`src/shell/lockscreen/lockscreen_login_box.cpp:317`；不削弱认证反馈 |
| GNOME 同步 | `theme.sync_color_scheme=false`；shell 自身固定 dark | schema :1383；禁止 shell 自动改写 GNOME 偏好，不声称此开关会主动设置其他应用为 dark |
| 桌面 media widget | 不启用 | desktop/widgets 文档 :341–371 支持 album_art_background、album_art_blur、audio_visualizer、hide_when_no_media；后者是无媒体隐藏，不等于“只在播放中可见”。bar 已有媒体与空闲隐藏频谱，避免重复封面模糊/动画，不改每日壁纸轮换 |
| 其他 5.3 功能 | 不加 dock per-monitor、模拟钟秒针与 shell switcher 滚轮设置 | dock 已禁用，时钟用数字；当前窗口切换入口仍为 Mango，不为未消费的 UI 添加配置 |
| Mango template | 继续不启用 builtin mango / noctalia-mango user template | 新模板 `assets/templates/mango/mango.conf` 有 group/tab/title 色；本仓库是 Mango 最终配色唯一写入者，无生成文件 include |

## 验证与产物

新增配置合约检查覆盖所有 12 个 `title_message_bar_*` 的存在、palette 映射、字体与几何，
检查对象是生成的 `mango/config.conf`，且真实锁定 Mango `-c … -p` 解析必须通过。
Noctalia 运行真实 `config validate`，再用 Python `tomllib` 检查生成 TOML 的新增字段与
原始 settings 合约一致；检查产物保留输入配置与日志。修正 WARN 匹配以拒绝 Noctalia 的
`WARN …` 与 `Config is valid (N warning(s))`；既有正则只识别 `[WARN]` 或 `warning:`，
首轮虽 exit 0 却漏报旧 provider 格式警告，不能记成零警告校验。

实际完成（exit 0）：

```sh
git diff --check
nix fmt
nix flake check --no-build --no-write-lock-file path:.
nix build --no-link --no-write-lock-file --print-out-paths \
  path:.#checks.x86_64-linux.{command-line-runtime,desktop-composition,editing-composition,embedded-composition,embedded-home,embedded-tools,embedded-udev,interactive-session-config,local-services-composition,neovim,project-workbench,protocols-composition,remote-workspace-composition,rime-technical-runtime,system-boundaries,treefmt,workspace-composition,xorg-session-runtime} \
  path:.#nixosConfigurations.nixos-btw.config.system.build.toplevel
```

全部 18 个 checks 与 toplevel 构建成功（部分未变化输出命中已有 store）。
`interactive-session-config` 内真实 Mango `-c 生成config.conf -p` 无解析输出/错误；
Noctalia `config validate 生成config.toml` 输出 `✓ Config is valid`，无配置 warning。
`desktop-composition` 的 reduced-motion 用户也通过这两个真实 parser；不代表启动了桌面。
新字段、palette 以及 generated TOML/config.conf 断言通过；字体匹配、已有运行态归属隔离检查
和其他 check 也随全部 checks 完成。三个改动文档的本地链接目标已逐个检查存在。

保留的上游诊断：flake check 报 `unknown flake output 'denful'`，仍 exit 0；两个 Noctalia
校验日志各有四条 community plugin manifest 的 `WRN`，来自 rss-notifier、iio_lock（两条）、
mihomo-control 的 entry setting 覆盖 plugin-level setting。这些插件未在本仓库 enabled 列表中，
是扫描锁定插件源时的已有 manifest 诊断，区别于配置 schema 的 `WARN`，未改第三方源码。

| 产物 | 路径 |
| --- | --- |
| 生成配置、parser 日志、字体和归属测试证据 | `/nix/store/9blz6blyq0bccdv413khyz7xffw8dfkx-interactive-session-config` |
| 组合结果与 reduced-motion parser 日志 | `/nix/store/7f79fs4w23gqv5l3x043jmfcnck7gln8-den-interactive-session-composition` |
| 新 toplevel（仅构建） | `/nix/store/x462s29m44b44sg8vhnfxp3628cyny5h-nixos-system-nixos-btw-26.05.20261021.da6dc0e` |

`mango.conf` / `noctalia.toml` 与 `mango.log` / `noctalia.log` 在第一个目录；
`mango-reduced-motion.log` / `noctalia-reduced-motion.log` 在第二个目录。
Luna 完成窄范围 Noctalia 实施，继承主模型的独立 reviewer 对跨模块 diff、锁定消费端、
检查及文档复核未发现可操作缺陷。主执行代理完成集成与上述实际命令。

新 history 未跟踪，因此使用 `path:.`；执行前检查 `git status --ignored --short` 无被忽略的
运行态文件，输入包含的 secrets 目录仍为仓库已有加密文件。没有修改 flake.lock、docs/README.md，
没有更改按键数据或真实用户状态。构建与求值不代表应用或实机视觉通过。

## 待实机验收

1. 内屏 1.5x 与外屏截图：bar、Launcher、控制中心、通知、OSD、锁屏和下次登录 greeter 的
   8/12/16 圆角、字体回退、边框和阴影，检查浅色窗口背后的边缘。
2. `Super+Alt+J/K` 与 `Super+Alt+T`：两行标题（含中文长标题/app-id）不裁切，蓝底黑字清楚；
   overcircle 中央 60% 预览、下方标题条不碰屏幕边缘。
3. 九工作区、长媒体标题、频谱、resize mode、IP、五个托盘图标、CPU 100% 的布局压力；
   按左 ≤640、中 ≤200、右 ≤570、段间 ≥16 实测，包含 accordion 展开/收起。
4. launcher 分类 tooltip、中文搜索、长名称、recent/频率排序；普通查询不触发 calculator，
   `/calc` 能工作；Esc、外点关闭、通知右键关闭和 Settings 的 Super+Q 可达。
5. 锁屏密码显示、Caps Lock、键盘布局、失败提示、会话按钮；不在录屏中输入真实密码。
6. 连续切换窗口/tag 20 次、浮窗开关、拖放交换与 8px 边缘 resize；指针跟随与输入隐藏沿用。
   测实际帧时间/电池功耗再决定动画取值；无本轮功耗测量。
7. Print/OCR/portal 分享输出仍完整；没有新增 shield。桌面媒体 widget 未启用，bar 媒体、
   频谱、壁纸轮换与 reduced-motion 分支仍需 GUI 检查。
