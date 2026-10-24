# 紧凑 · 下划指示 v3

2026-10-25 用户确认，第十八轮实施规范。实现与验证见 [执行记录](history/ui-v3-2026-10-25.md)。本版取代此前稿中顶栏、候选框、启动器、控制中心、通知、Neovim 与终端的尺寸和状态语言；其余平台约束与 palette 继续适用。

## 1. 视觉依据与状态语言

唯一视觉依据为用户提供的两组本地稿：

- 顶栏与输入法：`/tmp/claude-1000/-home-mayon-nix-dotfiles/13f9340b-d643-4d3f-bd2f-97266d0e2965/scratchpad/ui3/bar2.html` 与同目录 `bar2.png`。
- Neovim、启动器、控制中心、通知、终端：同一 scratchpad 下 `ui2/desktop.html` 与 `desktop.png`。其中顶栏与候选框已由 bar2 取代。

HTML 的 `html{zoom:1.5}` 只负责预览放大，CSS 数值均是逻辑像素。源稿中的示意派生色不作为新增 palette；实现只取下表源色与透明混合。PNG 为设计图，不是本机运行截图。

| 区域 | 尺寸与留白 | 状态语言 |
|---|---|---|
| 顶栏 | thickness 30、radius 10，上缘 6、两端 8 | 无分组填充胶囊，组间细分隔；活动为 2 px 蓝色圆角短下划线，hover 极淡底 |
| 工作区 1–9 | 等宽紧凑数字 | 当前 blue+短下划；占用下方小圆点；紧急 red 下划；空项暗色 |
| 日期与时间 | 日期 Inter；时间 Maple Mono 粗体 | `10月25日 周日`，日期由系统时钟生成，不固定日期 |
| 输入法 | surface 面板、细边、radius 10、10 pt，选项距边 ≥6 | 选中无底色，2 px blue 底部圆角短条；正文 brightFg、选中序号 blue、其他序号/注释 muted；保留柔影及 ShadowMargin |
| 启动器 | 宽 560，保留彩色应用图标 | 选中极淡底+左侧 2 px blue 竖条 |
| 控制中心 | 可见宽 380，用户卡、3×2 开关、细轨滑块、媒体卡 | 激活 blue 文字/下划+极淡底；不铺高饱和蓝色 |
| 通知 | 宽 320 | 细边、正文 brightFg，错误用图标/边线 |
| Explorer | 单一左栏约30列，git root/cwd | 项目标题大写；目录 blue；当前 selection+左蓝条，git 字母右对齐 |
| 标签栏 | 左侧项目区与 Explorer 等宽 | 当前 bg+顶部细蓝线，未保存 orange 点；TUI 精度以字符单元为限 |
| 状态栏 | 单行，模式/分支/变更/文件/诊断/LSP/AI/位置 | 模式 blue 文字与柔和底；保持正文可读 |
| 补全/picker/which-key/AI | deep 底、细边、圆字符边框 | 选中极淡底+blue 前景/左标记；Claude Code 标题和差异使用既有 provider 能力 |
| tmux / Starship | 单行状态栏 / 两行 prompt | 当前窗口 blue+下划，无实心胶囊；耗时 ≥3s 才显示 `· 12s` |

A 原生配置、B 主题接口（SVG/highlight/格式串）、C 局部源码适配须区分。Noctalia 的分组、工作区、选中面与 Home 布局部分需要 C 类补丁；配置项按锁定源码核实，不虚构 CSS/TOML API。TUI 不能逐像素绘制 2 px 线或改变单行字号，使用字符下划/上划与原生窗口边框近似，差距写入执行记录。

默认正文不透明，brightFg；蓝色表达焦点和选择，错误正文仍中性。分组以留白与细线组织，不把所有控件做成胶囊。固定 palette、不从壁纸取色。

## 2. 颜色令牌

只有下表的 16 色是源色；透明混合和壁纸渐变是由这些源色计算的派生结果，不增加独立调色板。不要从壁纸自动提色。所有应用固定深色模式。

| 源令牌 | 色值 | 语义 |
|---|---|---|
| bg | `#1e2228` | shell 与应用默认背景 |
| deep | `#181b20` | 代码阅读面、终端、侧栏、低层表面 |
| surface | `#272c33` | 卡片、工具栏、浮层内表面 |
| selection | `#323843` | 悬停、选中、按下填充 |
| fg | `#abb2bf` | 次级信息；在 bg/deep 上也满足正文门槛 |
| brightFg | `#d7dae0` | 全局正文、标题、输入、选区正文 |
| muted | `#828a95` | 辅助灰字与未接受的 AI 幽灵文本；bg/deep 上 ≥4.5 |
| comment / border | `#5c6370` | 分隔、描边；不作需要阅读的注释 |
| blue | `#61afef` | 焦点线、短选中标签、函数 |
| cyan | `#56b6c2` | 类型、信息图标 |
| purple | `#c678dd` | 特殊模式小图标；不作正文或大片背景 |
| green | `#98c379` | 成功标记、代码字符串 |
| orange | `#d19a66` | 代码数字、常量 |
| yellow | `#e5c07b` | 警告标记、待处理状态 |
| red | `#e06c75` | 错误图标、诊断下划线、删除标记 |
| black | `#0e1013` | 阴影、遮罩、ANSI 0 |

2026-10-25 收尾：muted 从原设计的 `#7d8590` 微调为 `#828a95`，使 bg 上幽灵文本达到 4.5；所有消费 muted 的辅助文字与装饰同步略微提亮，正文仍用 brightFg/fg。

### 交互与合成角色

| 角色 | 背景 → 前景 / 边线 | 透明度与用途 |
|---|---|---|
| 正文默认 | bg 或 surface → brightFg | 文字 alpha 1 |
| 次级说明 | bg / surface / selection → fg | 不再用 muted 降低必要信息 |
| hover | selection → brightFg | 1；不改变尺寸 |
| active / selected | selection → brightFg，短标签/图标 blue | 1；主题可控组件加 1 px blue 线或 2 px 左标记 |
| pressed | deep → brightFg / blue | 1；不做强光闪烁 |
| focus-visible | 原表面 → 原文字，2 px blue 外线 | offset 2；不依赖 hover；Mango 为窗口外框本身 |
| disabled | bg → fg，border 虚线/原生禁用轮廓 | 可控主题保持文字 alpha 1；加“不可用”说明；原生控件若固定淡化不宣称达标 |
| success / info | bg → brightFg，green / cyan 图标 | 标签正文中性；图标附“完成 / 信息” |
| warning | bg → brightFg，yellow 图标/边线 | 不以黄色铺卡片 |
| error | bg → brightFg，red 图标/边线 | 不在 surface 上写小号红色说明 |
| 阴影 | black | 层级见下；不使用纯 #000000 |
| 遮罩 | black | 普通模态 0.32；锁屏视觉等效 0.48，原生 tint 另计 |
| 顶栏 | bg | 背景 0.98；内部文字与胶囊不透明 |
| 通知、OSD | bg | 背景 0.98；若下方纯白导致受干扰，回退 1.0 |
| 浮层、认证输入、候选框 | bg / surface | 1.0；禁用整个控件 opacity 淡化 |
| diff 新增 / 删除 / 修改底 | green / red / blue 覆盖 deep | 0.08；字内变化 0.12；正文 brightFg |

Noctalia palette 的 A 类对应：`mPrimary/mOnPrimary=blue/black`、`mSecondary/mOnSecondary=cyan/black`、`mTertiary/mOnTertiary=purple/black`、`mError/mOnError=red/black`、`mSurface/mOnSurface=bg/brightFg`、`mSurfaceVariant/mOnSurfaceVariant=surface/fg`、`mOutline=border`、`mShadow=black`、`mHover/mOnHover=selection/brightFg`。C 类目标选中态直接取 selection/blue，不篡改这套角色的正文含义。所有跨应用模板从上面的源令牌取值；不能盲用 Material 衍生 token 替换整个 One Dark。

### 对比度实算

使用 sRGB 线性化，相对亮度 `L=0.2126R+0.7152G+0.0722B`，比值 `(L亮+0.05)/(L暗+0.05)`。已用 Python 计算，四舍五入至两位。以下是无透明覆盖的平面值，不包含抗锯齿边缘。

| 前景 | bg | deep | surface | selection |
|---|---:|---:|---:|---:|
| brightFg | 11.41 | 12.33 | 10.03 | 8.41 |
| fg | 7.49 | 8.10 | 6.59 | 5.53 |
| muted | 4.58 | 4.95 | 4.03 ✗ | 3.38 ✗ |
| border | 2.64 ✗ | 2.86 ✗ | 2.32 ✗ | 1.95 ✗ |
| blue | 6.76 | 7.31 | 5.95 | 4.99 |
| cyan | 6.74 | 7.29 | 5.93 | 4.97 |
| green | 7.92 | 8.56 | 6.97 | 5.84 |
| orange | 6.48 | 7.01 | 5.70 | 4.78 |
| yellow | 9.25 | 9.99 | 8.14 | 6.82 |
| red | 5.00 | 5.40 | 4.40 ✗ | 3.69 ✗ |
| purple | 5.42 | 5.86 | 4.77 | 4.00 ✗ |

正文统一 brightFg；deep 上代码可用 blue/cyan/green/orange/yellow，均 ≥7。选择行里的代码转 brightFg，语义保留在字形/诊断图标，避免蓝字在 selection 上被误称为 ≥7。短选中标签、来源名、行号按次级 ≥4.5 验收；正文注释使用 fg，AI 未接受的虚拟灰字使用 muted + 斜体（deep 上 4.95、bg 上 4.58），不是 comment/border。v3 候选框按确认稿使用 surface/muted 元数据（4.03:1），它未达到4.5门槛；选中正文仍为 brightFg，不能把该元数据配对称为达标。红色错误句子、紫色关键词改成 brightFg，红/紫只留标记。

透明最差情况：bg 以 0.98 覆盖纯白后约 `#22262c`；brightFg 对比约 10.81，fg 约 7.10，仍满足本案门槛。v3 顶栏内部无填充胶囊，背景透明度仍按0.98验收。壁纸上的 Home 用户资料有原生 tint；需真实截图验证其最终底色；图稿用户资料区以深色罩层保证阅读。

## 3. 几何、字排与运动

### 几何令牌

| 项目 | 目标值 | 能力与边界 |
|---|---|---|
| 圆角 | 8：按钮/选项；12：窗口/内部卡片；16：独立面板/通知 | Noctalia 原生 Md/Lg/Xl 6/9/12 × `shell.corner_radius_scale=4/3`；Sm 3 → 4 是微控件例外 |
| 胶囊 | 顶栏半径 10；头像圆形；tmux 使用字符下划 | 不把所有控件改为半圆 |
| 间距 | 4 / 8 / 12 / 16 / 24 / 32 / 48 | 4 为微间隙，8 为行内，16 为卡片，24 为分区 |
| 固定原生留白 | Noctalia panel/card padding 14，capsule padding 6 | 源码常量；接受为光学例外，不声称有任意 padding 配置 |
| 描边 | 静态 1 border；焦点 2 blue；紧急通知原生至少 3 red | border 是装饰，不承担唯一状态表达 |
| 控件热区 | 常用按钮目标 ≥32 × 32；表单 40 高 | 原生按自身字号计算；顶栏可视图标 16–18、紧凑顶栏热区 30（按已确认稿） |
| S0 | 无阴影 | 平铺窗口、卡片内部、Neovim/TUI |
| S1 | `0 4 12 / black 0.24` | 顶栏/小浮层，CSS 目标 |
| S2 | `0 8 24 / black 0.32` | shell 面板与通知，CSS 目标 |
| S3 | `0 12 32 / black 0.40` | 认证或单个浮动主窗，CSS 目标 |

Noctalia 只开放 `shell.shadow.direction="down"` 与 `alpha=0.32`、组件 shadow 开关；没有逐级 CSS blur/offset 参数，因此 S1–S3 为设计近似，不为它编造三个阴影对象。Mango 用 `shadows=1`、`shadow_only_floating=1`、`shadows_size=10`、`shadows_blur=20`、`shadows_position_x=0`、`shadows_position_y=6`、`shadows_color=0x0e101352`（32%），`layer_shadows=0`，让 shell 自己负责自身阴影。

### 模糊与透明

- Mango 默认 `blur=0`、`blur_layer=0`：正文不透明，无需持续模糊。`focused_opacity=unfocused_opacity=1`、`dim_enable=0`，非焦点代码仍可阅读。
- Noctalia `[backdrop]` 是给合成器 overview/backdrop 模式使用的壁纸副本，不是普通面板背后的通用模糊；Mango 本案设 `backdrop.enabled=false`，不假定支持 niri 的 backdrop 规则。面板本体 `shell.panel.transparency_mode="solid"`。锁屏独立 `lockscreen.blur_intensity=0.40`、`tint_intensity=0.48`。这些为 0–1 原生强度，**不等价于 Gaussian px**；HTML 背景近似 blur 16 px。
- 如果今后明确需要透明客户端，可试 Mango `blur_params_radius=4`、`blur_params_num_passes=2`、`blur_params_noise=0.01`、brightness/contrast/saturation 均 1、`blur_optimized=1`，但本案默认不启用。锁屏模糊由 Noctalia 自身完成。

### 字体层级

| 用途 | 字体 | 逻辑视觉字号 / 字重 / 行高 |
|---|---|---|
| 桌面正文、控件 | Inter → Noto Sans CJK SC | 14 / 400–500 / 22 |
| 卡片标题 | 同上 | 16 / 600 / 24 |
| 面板标题 | 同上 | 20 / 600 / 28 |
| 说明、快捷键提示 | 同上；键帽 Maple | 13 / 400 / 20 |
| 顶栏 | 同上 | 13 / 500 / 20；工作区原生 11，可 `font_scale` 增至约 13 |
| 代码/终端 | Maple Mono NF CN | 约 15 / 400 / 单元行高约 22 |
| 终端状态、标签 | Maple Mono NF CN | 同终端字号 / 500 / 一个字符行 |
| 锁屏时钟 | Inter，tabular nums | 72 / 400 / 84 |
| 锁屏日期 | Inter → Noto Sans CJK SC | 16 / 400 / 26 |

HTML 指定 `font-family:Inter,"Noto Sans CJK SC",sans-serif` 与 `"Maple Mono NF CN",monospace`。真实 shell 用 Pango family `Inter` 和 fontconfig 中文 fallback；CJK 不使用合成斜体，正文不额外加字距。标题紧凑但不使用全角空格做对齐。中英文字之间保留半角空格，数字与 `%` 连写、与 `GB/ms` 留空格。菜单名和日期使用中文；时间 24 小时制，不显示秒。

Kitty 从 `font_size=11.0` pt 开始（约 14.67 CSS px），不是把 15 直接写成 15 pt。Pango `Inter 10.5` 约为 14 逻辑 px。Noctalia 使用原生字体常量和 `font_scale`，不能全局写入不存在的字号/行高字段。终端字号与实际 cell 高度需要实屏核对，HTML 的行高是视觉目标。

### 动效

| 事件 | 目标 | 实现 |
|---|---|---|
| hover / press | 100 / 80 ms；ease-out | CSS 可设；Noctalia 保留原生 fast 100 ms |
| 浮层出现 / 消失 | 180 / 120 ms；`(.16,1,.3,1)` / `(.4,0,1,1)` | Noctalia 只用 `shell.animation.speed=1`、原生 normal 200 ms，不伪称可逐项设曲线 |
| 窗口打开 / 关闭 | 220 / 140 ms；同上 | Mango `animation_duration_open/close`、`animation_curve_open/close` |
| 移动 / tag | 180 / 220 ms | `animation_duration_move/tag`、对应 curve |
| 焦点 | 0 ms | `animation_duration_focus=0`；边线立即响应 |
| 轻缩放 | open 0.96 → 1；close 1 → 0.98 | `animation_type_open/close=zoom`、`zoom_initial_ratio/zoom_end_ratio` |
| 锁屏背景 | fade 200 ms | `lockscreen.transition=["fade"]`、`transition_duration=200` |

`layer_animations=0`，不重复 shell 动画。减弱动效：Mango `animations=0`，Noctalia `shell.animation.enabled=false`，锁屏/壁纸 transition 空列表，Kitty 光标拖尾与闪烁关闭。图稿静态，无循环动画。

## 4. Noctalia 顶栏

采用 §1 的30逻辑像素紧凑栏。左侧依次为启动器、分隔线、1–9 工作区、分隔线、布局（图标+平铺文字）、Quill、播放中的媒体与频谱。mangowm-keymode 仅非默认模式出现。

中部为中文日期和 Maple Mono 粗体时间。右侧为社区 system-monitor 的 CPU%，悬停展开 GPU/内存；插件不能直接展开时用 accordion 组合。随后为社区 nix-status（❄+当前世代，点开查看世代与输入更新）、仅占用时出现的内置 privacy、网络/蓝牙/音量百分比、输入法、电池百分比与绿色“养护”、通知及 Nix 控制中心入口。

mini-docker、portctl、ip-monitor、tray、亮度、电源模式等低频项放入可展开组；亮度、电源模式在控制中心也保留入口，默认不让所有图标占满顶栏。不启用任何 AI 额度/用量组件。nix-search 启用 nixpkgs/NixOS/HM 查询，声明 `nix-search-tv` 与 fzf 运行依赖。

养护权限归 `hardware/legion-laptop`：host 声明组和 ideapad_acpi udev 规则，user class 授权；桌面调用公开 CLI 读取/切换。禁止运行时 sudo、groupadd、usermod，不使用 ideapad-conservation-mode 插件。构建不改变当前 sysfs 及组权限。

字段与渲染实现以锁定 Noctalia 5.3、官方和社区插件源为依据。补丁仅改此 package 的绘制/布局，不替换全局 Primary 的语义；palette 的 Primary 仍为 blue。

## 5. 启动器与控制中心

启动器 full layout、宽560，彩色应用图标，常用 pinned Kitty/Neovim/Firefox/Thunar。选中为柔和中性底+左2px蓝条，说明文字 fg。色彩恢复必须追溯图标 monochrome/colorize/tint 路径，不通过更改系统全部图标来绕过。

控制中心可见宽380，用户卡置顶，Wi-Fi/蓝牙/免打扰/防休眠/夜灯/电源模式构成3×2块；活动为蓝字/短下划和极淡底。下方音量与亮度细轨滑块、媒体卡。原生布局不提供的部分由局部补丁落实，并保持既有点击与拖动逻辑。浮动右上，面板与顶栏留间隔。

## 6. 通知、OSD、锁屏与登录

### 通知

宽 320，普通高约 108–132，padding 14，外圆角 16，顶右 x=16 / y=64，间距 8；同时最多 3。正文 14/22，应用/时间 13，标题 14/600；标题 1–2 行，正文按原生换行，action 保留完整文字。

普通：border 1，信息图标 cyan。警告：同一中性卡片、yellow 图标与“注意”；**Freedesktop 没有 warning urgency**，作为 normal 消息的正文/发送方图标处理，不能编造 warning 配置。错误：正文 brightFg、red 错误标记；critical 原生边线至少 3 px red。图稿分别展示 normal、normal+警告语义、critical。正文不写一整段红字。

**依据 A**：`notification.{width=320,background_opacity=0.98,border=true,border_color="outline",border_width=1,offset_x=16,offset_y=64,max_visible=3,position="top_right",show_app_name=true,show_actions=true}`。普通消息的关闭时间由发送方/现有 filter 决定，不以视觉稿改写交互语义。若控制中心覆盖通知，交由原生层级；图稿将通知移到空白区作为同时展示状态，不承诺自动避让算法。

### OSD

底部居中，底距 32，视觉宽约 300、高 56、padding 16、圆角 16；图标 20、轨道 4–6、百分比 13。surface/bg alpha .98，1 border。静音/亮度最低不能隐藏图标和数字。

**依据 A**：`osd.{position="bottom_center",orientation="horizontal",offset_y=32,hide_delay_ms=1400,scale=1,background_opacity=0.98,border=true,border_width=1}`。宽高来自原生类型，未提供 width/height 配置；数值为视觉验收参考。

### 锁屏

壁纸 005 的暗化版本；时钟在中心偏上，72 字号、中文日期 16；登录区在逻辑中心偏下，宽约 440，使用 **compact 密码行**。原生解锁提示是独立状态卡，位于输入行上方，不把它硬塞成自定义竖向头像表单。输入 40–44 高，radius 8、实底；认证失败保留尺寸，仅提示卡显示“密码不正确，请重试”。Caps Lock 显示文字；不因错误播放震动动画。媒体与天气在本方案不进入锁屏。

**依据 A**：`lockscreen_widgets.widget.<id>` 的 `type="clock"/"label"`、`cx/cy/box_width/box_height/settings.format/font_family`；login box `layout="compact"`、`background_color="surface"`、`background_opacity=1`、`background_radius=16`、`input_opacity=1`、`input_radius=8`、`show_unlock_hint=true`、`show_caps_lock=true`、`show_keyboard_layout=true`。login box 只可移动，不可任意 resize；图稿的宽高是原生近似。`lockscreen.blurred_desktop=false` 使用壁纸，blur .40 / tint .48。

### Greeter

与锁屏同壁纸和中文日期，居中用户卡约 400 宽；用户名 18/600、头像 64、输入约 40 高；session “Mango” 清晰可见，电源动作在右下。底部不放新闻、天气或个人项目。蓝色焦点细线，登录按钮中性选中底；错误消息 brightFg + red 标记。不能把锁屏的 widgets 配置复制进 greeter。

**依据 A/C**：当前 `aspects/desktop/greeter/greeter.nix` 已使用 `appearance.{scheme,theme_mode,corner_radius_scale,font_family,hide_logo,scheme_selector_position,power_buttons_position,palette,wallpaper}`、`clock.{enabled,position,time_format,date_format}`、`session.default`、`output.scales`。palette 与本规范语义对应，`clock.date_format="%Y年%m月%d日 %A"`，中文需 greeter 进程 `LC_TIME=zh_CN.UTF-8` 且相应 locale 可用。卡片精确尺寸、独立按钮前景/底色没有在当前模块证明可配：接受原生布局；若原生 primary 登录按钮为蓝实底，原生替代是保留小尺寸按钮，图稿中性按钮属于与 shell 同样的局部主题适配。登录前字体、头像与壁纸需进入系统可读资源路径，这是交接要求，不在此执行。

## 7. Mango 窗口系统

- 窗口外框 2 px，普通 border、焦点 blue、urgent red，圆角 12。内间距 8、外间距 16。`no_radius_when_single=0`，单窗口保留边界；不对非活动窗口加暗膜。
- 普通 Kitty/Neovim 不加合成器常驻假标题栏，窗口身份通过应用标签、终端标题和切换器显示。图稿标签行属于 Kitty/Neovim；不是 Mango 普遍提供的传统标题栏。
- monocle auto tab / group bar 高 32，圆角 8，padding x8/y4，字 Inter 10.5 pt。普通 deep/fg，选中 selection/blue，未保存标记 brightFg。装饰边线 1 border；关闭按钮默认不显示。
- `title_message_bar` 用于 overcircle 和 switcher，标题+app-id 两行，高 48、与预览 gap12，padding 8/4、radius8；focus selection/blue，长标题截断，app-id 次级 fg。标准 overview 不承诺每张卡都带这块条。
- jump label：Maple Mono NF CN Bold 12 pt，约 32–40 高，padding8/4、radius8、1 border；默认 deep/brightFg，focus selection/blue。
- overview inner gap16、outer32，显示实际客户端缩略图，焦点 2 blue，保留原生命中逻辑。不得承诺可配置固定三列、固定缩略图大小、实时毛玻璃或搜索框。

**依据 A**：`borderpx`、`border_radius`、`border_color/focus_color/urgent_color`、`gappih/gappiv/gappoh/gappov`；`tab_bar_height`、`group_bar_height` 与各自 `*_decorate_{fg_color,bg_color,focus_fg_color,focus_bg_color,border_color,border_width,corner_radius,padding_x,padding_y,font_desc}`；`title_message_bar_height/gap` 和同族 decorate 字段；`jump_label_decorate_*`；`overview_gap_inner/outer`。颜色采用 `0xRRGGBBAA`，例如焦点 `0x61afefff`，不是 ARGB。

## 8. Kitty、tmux 与 Starship

### Kitty

编辑和终端正文统一 deep，这一档比 shell bg 深，但仍属于同一 One Dark。默认背景不透明 `1.0`；与本方案可读性门槛一致，不推荐 0.85 的“玻璃终端”。窗口 padding 12，`hide_window_decorations=yes`。光标 brightFg，beam 1.5；选区 selection / brightFg。终端默认前景 brightFg（12.33），ANSI 7 保留 fg；ANSI 0–7 依次 black/red/green/yellow/blue/purple/cyan/fg，8=border，9–14 不加饱和或提亮，15=brightFg。

标签栏只在 ≥2 标签时出现；目标一行字符高，左右各 1 cell，选中 selection/blue、普通 deep/fg，取消斜切撞色。可用 `tab_bar_style="separator"`、`tab_separator=" │ "`；若必须做圆端可写 `custom` tab draw，但图稿不把 CSS 圆角算成原生能力。无独立自绘标题行。

**依据 A/B**：现有 `kitty.nix` 的 `font_family/font_size/background_opacity/background/foreground/cursor*/selection_*/window_padding_width/tab_bar_min_tabs/tab_bar_style/active_tab_*/inactive_tab_*/tab_bar_background`。换用 separator 是 Kitty 原生 tab renderer；终端颜色遵循自己 palette，不依赖 shell 的 Material token。

### tmux

底部一行，deep 底、左右 1 cell；顺序为 session → window 列表 → 空白 → prefix/copy/zoom 状态 → 时间。当前窗口 blue 字加 underline，取消实心胶囊及圆端；后台 fg。prefix/copy/zoom 分别用 cyan/yellow/blue 标签，窄屏保留当前窗口身份。

**依据 B**：现有 `status-left/right/style`、`window-status-format/current-format`、`pane-border-style/pane-active-border-style`、`message-style/mode-style`、`@prefix_highlight_*` 与 `#{client_width}`、`#{pane_in_mode}`、`#{window_zoomed_flag}` 格式表达式。使用真彩色 `#RRGGBB`，不把 ANSI 8 border 作为必要说明前景。

### Starship

两行：第一行目录 blue、分支 fg、工作区变更 yellow 的短数字、耗时 fg（≥3s 显示 `· 12s`）；第二行 `❯` blue + 用户命令 brightFg。失败时 red 符号加可读 exit code；没有背景色块、没有重复用户名主机占位（SSH/root 才显示）。提示符不显示秒级时间，与顶栏避免重复。AI 灰字不属于 Starship prompt；如使用 shell suggestion 也应 fg/deep。

**依据 A/B**：`programs.starship.settings.format`、`directory.style/format`、`git_branch.style/format`、`git_status.style`、`cmd_duration.style/min_time`、`character.success_symbol/error_symbol`；现有 zsh 模块已声明相应结构。只调整呈现，不改变命令行为。

## 9. Neovim 工作台

| 区域 | 尺寸、留白、状态 | 可实现性依据 B |
|---|---|---|
| 正文 | deep；Maple 约15/22；边距以 cell；行号 fg，当前行号 brightFg；当前行保持 deep，只在 gutter 画 blue 标记 | `Normal/NormalNC/LineNr/CursorLineNr/SignColumn`，`cursorlineopt`；真实终端无 CSS padding |
| 语法 | 关键字 cyan（7.29）、函数 blue（7.31）、字符串 green（8.56）、数字 orange（7.01）、注释 fg（8.10）、标点/变量 brightFg；紫色不承担正文 | `nvim_set_hl`、Treesitter `@keyword/@function/@string/@number/@comment`，已有 `ui/theme.lua` |
| 标签栏 | 一个字符行；deep 底；活动 bg/brightFg、顶部细 blue 标记，后台 fg；改动圆点 orange；项目名独立区与 explorer 宽度对齐 | 已有 Heirline/`ui/tabline.lua`；圆角只能用字形 |
| 状态栏 | 一个字符行；模式前景 blue/cyan/yellow，底 deep；文件、Git、诊断、LSP、AI、行列有优先级 | Heirline/`ui/statusline.lua`；不全行模式色底；长路径中间缩写 |
| 浮窗 | NormalFloat=deep，正文 brightFg，FloatBorder=border；左右1 cell，`border="rounded"` | Neovim window border 为框线字符，视觉半径不可直接设 12；无独立阴影 |
| 补全菜单 | ≥28列，最多8项；左右1 cell；候选 brightFg，选中 selection/brightFg + blue 类型符号；来源 fg | 原生 `pumheight/pummaxwidth/pumborder`、`Pmenu*` 高亮；窄屏去说明与来源 |
| 补全文档 | 最多60列×14行，deep/brightFg，border圆字符，延迟300ms | 原生 `completeopt=popup` 与 `Pmenu*` 高亮；不与输入法候选互相遮挡 |
| AI 虚拟建议 | muted + 斜体；无光晕、无低透明度；未接受标识在状态栏“建议” | 插件 ghost-text highlight/extmark；具体组名以实际 provider 为准，CodeCompanion 不被假定自带持续 inline ghost completion |
| AI 侧栏 | 正文约32–40列，deep/brightFg，Claude Code provider 标题可辨，内容 Markdown；分隔1字符 border；引用文件单独短行 | 当前 CodeCompanion split 布局与 highlight；宽不够时改独立 tab/浮窗，禁止压缩代码到小于约60列 |
| diff 审阅 | deep 底；左右原文/修改；新增/删除各8% green/red底；局部12%；全文brightFg；gutter有 +/−；修改 blue 标记 | `DiffAdd/Change/Delete/Text`、CodeDiff、Claude 原生 diff、mini.diff；blend 颜色在主题生成阶段计算为实色，TUI 不支持逐cell alpha |
| 启动页 | 项目名20视觉近似（终端仍同字号，可用两行布局）；最近项目5项、会话/新文件/查找3–4项；中性标题、小号蓝标记 | 已有 `ui/dashboard.lua`/Snacks dashboard；终端不混用任意字号，不渲染巨型彩色ASCII logo |

选区中的所有源码以 brightFg/selection 呈现。错误正文中性，DiagnosticError 用 red 图标或 undercurl；虚拟诊断正文 brightFg，避免红字在 tinted surface 低对比。diff 彩底仅用于已有/待审变化；AI 产出未接受时不自动显示为已应用的绿色成功。

diff 合成后的实测正文对比：8% green/red/blue 底分别约 10.70 / 11.21 / 10.79；12% 字内底分别约 9.82 / 10.53 / 10.00，均 ≥7。

图稿同时展示补全菜单、AI 灰字与侧栏是覆盖状态样本；实际补全弹出时应抑制抢占的 ghost text，接受方式维持现有键位与 provider 能力，不把视觉稿当成功能升级。

## 10. 输入法、GTK / Qt 与 Firefox

### fcitx5 横排候选

预编辑一行、候选一行、每页7项、10pt；面板 surface、细 border，外 radius10。选中项不填底，brightFg 候选/blue 序号，下方2px蓝色圆角短条，其他序号与注释 muted。选中内容与面板边缘至少6逻辑像素；保留柔和阴影及 ShadowMargin，由 Fcitx 原生避边。SVG nine-slice 的底部短条代替旧 selection 填充。

**依据 A/B**：Classic UI 横排与字体设置、Rime page_size、`InputPanel.*Color`、`Background/Highlight`、`ContentMargin/TextMargin/ShadowMargin`。字段及像素效果由 rime-checks 对生成主题核验；GUI 截图与实际 DPI 行为属于应用后验证。

### GTK / Qt（Thunar 为代表）

正文 brightFg，主面 bg，侧栏 deep，工具栏 surface。工具栏约40高，按钮32、内边距8，列表行约32，sidebar目标176–208宽；选中行 selection + brightFg，图标/细边 blue；hover selection。路径栏圆角8、focus blue2。文件列表中文14/22，大小/日期 fg；图标16–20，文件夹保留已有 Papirus 风格。

**依据 A/B/C**：GTK3 保留 adw-gtk3-dark，通过现有 Noctalia GTK模板或主题 CSS 接口统一 `theme_bg_color/theme_fg_color/selected_bg_color/selected_fg_color` 等；CSS 局部控制 selection、entry、headerbar，Thunar 自身侧栏宽度是用户窗口状态。GTK4/libadwaita 的不暴露部分以其原生尺寸为准，不宣称能对所有应用强制圆角。Qt6ct 已用 Fusion，QPalette `Window/Base/AlternateBase/Button=bg/deep/surface`、`Text/WindowText/ButtonText=brightFg`、`Highlight=selection`、`HighlightedText=brightFg`、`Link=blue`、`PlaceholderText=fg`。QPalette 不负责控件圆角和内边距；Qt 保留 Fusion 形状，只有外窗口 Mango 半径12。Qt5、私有绘制应用同色近似，不能承诺统一CSS覆盖。

### Firefox

工具栏40–44高，地址栏高32、radius8、bg底；输入文字brightFg；焦点2 blue，悬停selection。原生垂直标签侧栏约208宽，标签高36、间隔4、radius8；选中selection/brightFg，加blue短标记。关闭图标出现在可用状态，不用彩色交通灯。页面正文不被 browser chrome CSS 强行反色。

新标签页是安静的工作入口：原生搜索框约560宽、高48；常用站点8项以内，卡片 surface、中性文字和小蓝图标。中文标题“搜索网页”，不用伪实时生产力评分、天气、项目统计。搜索与网站入口在真实浏览器由原生页面提供。

**依据 A/B/C**：现有 Firefox `userChrome.css` 已处理 `#nav-bar/#urlbar-background/.tab-background/#tabbrowser-tabs[orient="vertical"]`；垂直标签用当前 Firefox 原生开关，不要求扩展。新标签页样式需单独 `userContent.css`，限定 `@-moz-document url("about:newtab"),url("about:home")`；`userChrome.css` 不能改网页内容。原生内容DOM随Firefox版本变化，间距/色值是主题目标，默认内容数量/开关先用浏览器设置；CSS选择器须在实施时检查。图稿没有承诺把时间/文案注入原生新标签页。

## 11. 壁纸回退与用户目录

2026-10-25 按用户要求恢复仓库已有的冷色五张图：`wallpaper-002.png`、`wallpaper-005.png`、`wallpaper-008.png`、`wallpaper-009.png`、`wallpaper-011.png`。默认桌面、greeter 与锁屏资源为 005；锁屏的原生背景跟随桌面当前壁纸，轮换后会显示当前图片。四张新绘制图与外部照片不再进入资源工厂；不再有构建期图像生成器或配方。全部 `wallpaper-0xx.png` 原始文件均保留。

`~/Pictures/Wallpapers/managed` 是只读内置集合，`local/` 继续归用户拥有。Noctalia 递归扫描共同父目录并跟随目录软链；移除功能不清理本地图像或历史。固定 One Dark 配色，不从壁纸自动提色。

## 12. 依据索引与验收交接

以下以用户指定本地版本为准，未用旧版在线教程替换字段：

- **N** = `/nix/store/0k6cwl09arhpjvg50lfnr12xcdfhb0w4-source`（Noctalia 5.3）。已读 `docs/user/theming/palette.mdx`、`bar/index.mdx`、`bar/widgets/workspaces.mdx`、`configuration/shell.mdx`、`control-center/index.mdx`、`control-center/shortcuts.mdx`、`launcher/index.mdx`、`services/notifications.mdx`、`lockscreen/widgets.mdx`、`desktop/wallpaper.mdx`、`configuration/date-format-tokens.mdx`。补充核对 `src/ui/style.h`、`src/shell/bar/widgets/workspaces_widget.cpp`、`src/shell/launcher/launcher_panel.cpp`、`src/shell/control_center/tabs/home_tab.cpp`、`src/shell/control_center/control_center_panel.cpp`、`src/ui/controls/slider.cpp`。
- **M** = `/nix/store/qcya6bfk3h3f291ca9jidjfnlrx7l32x-source`（Mango 0.18.3）。已读 `docs/visuals/theming.md`、`effects.md`、`animations.md`、`docs/window-management/overview.md`。
- **R** = `/home/mayon/nix-dotfiles`。只读 `docs/desktop-design.md` 及 `aspects/desktop/{mango-session,greeter,session-support}`、`aspects/cli/{terminal,shell}`、`aspects/dev/neovim/config/lua/mayon/{ui,plugins}`、`aspects/apps/firefox/resources/noctalia-userChrome.css`。引用现有配置说明接口已接线，不证明目标参数已实施。

本轮采用上述用户确认的 HTML/PNG，不再使用此前 mockup.html/mockup-panels.html 的尺寸。实施只执行构建与隔离/headless 验证，没有应用系统配置、启动或重启桌面常驻进程。Noctalia parser、Neovim Explorer/文本渲染、palette 对比度与完整构建结果见 [执行记录](history/ui-v3-2026-10-25.md)。

实机待验：150% 缩放下文字/下划线/候选边距、九工作区和最长媒体/展开组时顶栏容量、彩色应用图标、3×2开关及滑块、隐私占用出现/退出、电池养护权限和切换、中文候选避边、长通知裁切。构建不代替这些运行证据。

## 13. 第十九轮科技版（2026-10-25）

本节覆盖前文与本轮冲突的外观目标。唯一视觉依据为用户确认的 `ui4/term.html` / `term.png`、`ui4/sys2.html` / `sys2.png`；顶栏沿用 `ui3/bar2.html` 的下划指示，相关第十八轮变更由另一 worktree 实施。本轮不修改顶栏、launcher、控制中心、输入法主题和 Neovim。

| 科技版令牌 | 表达方式 |
|---|---|
| 等宽读数 | Maple Mono NF CN；用于时钟、日期、路径、表头、时间/容量/百分比、模式徽标；中文正文保留可读字体 |
| 渐变细描边 | blue → cyan，仅用于认证框下沿与必要边缘；颜色从 palette/主题角色传入，不增加源色 |
| 发光下划线 | 认证输入底部细线配低透明度 blue 柔光；失败仍保留文字/错误状态 |
| 分段刻度 | OSD 20 个细轨刻度，亮段 blue、轨道 selection，数值等宽；电量为独立分段读数，数据实时获取 |
| 焦点外发光 | Mango 焦点蓝边 2px，blue alpha 约 22% 的柔和外发光；非焦点 surface 边与 black 柔和阴影 |
| 下划指示 | Kitty/tmux/herdr 的活动标签使用终端 underline，保留中性背景；终端字符单元不等同于 CSS 2px 描边 |

终端：Kitty 原生标题 renderer 外围加蓝下划；tmux 底部 session 蓝字、活动窗口下划，zoom 显示黄色 Z，prefix/copy/zoom 为蓝/黄/紫小徽标，非焦点 pane 只留 surface 分隔线。Starship 两行、目录蓝、分支紫、变更黄、耗时 muted、失败红提示符。Yazi selection 底与蓝标记，Lazygit 圆角细线面板，btop 原生细圆角与蓝青渐变。fastfetch 小 Nix 标志配平铺键值，键蓝色。herdr 是新增独立 agent 工作区，保留 tmux，入口为 `Super+Alt+H` 与 desktop launcher。

系统界面：锁屏与 greeter 用等宽时钟/日期、蓝青底线和等宽状态；Mango tab/group/title 使用等宽字体；OSD 数值等宽、分段细轨。Thunar 与 Firefox 保留已有单一模板/seed，选择态 selection 底加左蓝条，路径和读数等宽；uosc 细进度线和蓝选中条。Zathura 以原生目录索引和数字页进度替代文件目录侧栏/独立进度线，uosc 采用平面线而无发光。

补丁清单和上游升级处理在 [Mango session README](../aspects/desktop/mango-session/README.md)、[greeter README](../aspects/desktop/greeter/README.md)、[herdr README](../aspects/cli/herdr/README.md)。补丁应用和关键渲染锚点在构建期强制校验；不能用求值成功代替补丁构建或视觉验收。实际完成范围、命令结果和剩余实机项见 [第十九轮记录](history/ui-v4-2026-10-25.md)。
