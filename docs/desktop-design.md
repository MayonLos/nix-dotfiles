# Mango + Noctalia 桌面视觉设计

状态：**此前桌面配置已由用户 nr 应用；本轮系统与编辑器优化获授权继续应用**。
此前 Den 迁移的构建证据见[实施记录](den-execution.md)，本轮检查与交付状态另见
[视觉优化执行记录](desktop-polish-execution.md)。尺寸、动画、混合缩放与功耗仍需本机验收，
构建不证明视觉效果；用户正在运行的 mod 任务不受本轮配置编辑影响。

## 视觉方向与责任

固定采用 Mango + Noctalia、One Dark Darker、Kitty + tmux 和 Lua + Nix Neovim。桌面呈现深石墨底色、蓝色焦点、青紫辅助色、清楚的表面层次；通过胶囊分组、媒体封面与频谱、BongoCat、细描边和短动画获得丰富感。基础背景固定为 `#1f2329`，壁纸不参与自动取色，白天也不切换浅色主题。

外观数据与各软件适配遵守 [架构设计](architecture-design.md)：外观拥有语义色、字体等公共数据，Noctalia、Mango、Kitty、Neovim 等各自消费；greeter 是主机的明确选择。最终文件只有一个写入者。本文中的尺寸、布局和时长是设计目标；硬件相关参数以验收结果决定是否保留。

现有配置已经具备丰富的基础：[Noctalia](../aspects/interactive-session/noctalia.nix) 有分组胶囊、媒体频谱、BongoCat、开发工具、通知和锁屏；[Mango](../aspects/interactive-session/mango.nix) 有圆角、窗口模糊、动画和 monocle 标签栏。实施以这些能力为基础，插件继续从 flake 锁定路径加载，`auto_update = "none"`。

## 语义调色板

下表是外观接口的数据，不是所有应用都原样接受的选项名。共享 [Darker palette](../aspects/appearance/onedark-darker.nix) 是颜色依据，Neovim 的丰富高亮消费生成数据，桌面文字增加已有 ANSI bright-white 作为强调前景。

| 语义 | 值 | 使用位置 |
| --- | --- | --- |
| background | `#1f2329` | 终端与编辑器主背景、shell 基础表面 |
| deep | `#181b20` | 编辑器浮层、tmux 状态底色、底层阴影区域 |
| surface | `#282c34` | 胶囊、卡片、次级表面 |
| selection | `#30363f` | 悬停、选择、编辑器选区 |
| foreground | `#a0a8b7` | 编辑器正文、桌面次级但必要的文字 |
| foregroundStrong | `#d1d5de` | 桌面正文、标题、重要状态文字 |
| muted | `#7a818e` | 非必要辅助信息；不作为小字号按钮或正文颜色 |
| border | `#535965` | 描边、未聚焦窗口边界；不承担正文角色 |
| black | `#0e1013` | 彩色实心控件上的深色文字、ANSI 0 |
| accent / info | `#4fa6ed` | 当前工作区、聚焦边框、选择、链接 |
| secondary | `#48b0bd` | 媒体频谱另一端、辅助交互、信息提示 |
| tertiary | `#bf68d9` | 暂存窗口、特殊模式、少量装饰 |
| success | `#8ebd6b` | 已完成、正常连接等有语义的状态 |
| warning | `#e2b86b` | 电量警告、待处理状态、tmux copy mode |
| error | `#e55561` | 错误、紧急工作区、破坏性操作边框与图标 |
| orange | `#cc9057` | 编辑器数字/常量与次级语法强调 |

Noctalia 使用 `theme.mode = "dark"`、`shell_mode = "follow"`、`source = "custom"`、`custom_palette = "One-Dark-Darker"`，关闭 `pure_black_dark`，由外观适配通过现有 HM `programs.noctalia.customPalettes` 生成 `~/.config/noctalia/palettes/One-Dark-Darker.json` 的 `dark` 对象。固定模式不依赖日出日落或地理定位。其 16 个字段映射为：

| Noctalia JSON 字段 | 值 |
| --- | --- |
| `mPrimary` / `mOnPrimary` | `#4fa6ed` / `#0e1013` |
| `mSecondary` / `mOnSecondary` | `#48b0bd` / `#0e1013` |
| `mTertiary` / `mOnTertiary` | `#bf68d9` / `#0e1013` |
| `mError` / `mOnError` | `#e55561` / `#0e1013` |
| `mSurface` / `mOnSurface` | `#1f2329` / `#d1d5de` |
| `mSurfaceVariant` / `mOnSurfaceVariant` | `#282c34` / `#a0a8b7` |
| `mOutline` / `mShadow` | `#535965` / `#0e1013` |
| `mHover` / `mOnHover` | `#30363f` / `#d1d5de` |

`success`、`warning` 和 `deep` 保留在公共外观数据中；它们不是额外的 Noctalia palette 字段。需要这些颜色的已支持 widget 字段可以传固定十六进制值，不能虚构新的 ColorRole。JSON 同时填写 `terminal`：背景/前景为 background/foreground，光标为 foregroundStrong，光标下文字为 background，选区为 selection/foregroundStrong；ANSI 0–7 为 black/red/green/yellow/blue/purple/cyan/foreground，8 为 border，9–14 与对应普通彩色相同，15 为 foregroundStrong。主题格式依据 [锁定版本 palette 文档](https://github.com/noctalia-dev/noctalia-shell/blob/fc2af27c0e616006bf858cad3b7c9711a028e501/docs/user/theming/palette.mdx)。

## 面板：固定骨架与有状态的内容

所有尺寸均为逻辑像素，字体另行标注。主面板固定在顶部、预留窗口空间、不自动隐藏，普通 `top` layer 不覆盖全屏应用。沿用三个区段与现有 `capsule_group`：

```text
左：Launcher │ 1…9 工作区 │ 调整模式 │ 布局[悬停：端口] │ Quill[悬停：Docker] │ 媒体/频谱
中：月-日 时:分 │ BongoCat
右：网络/IP/蓝牙/音量/亮度 │ 托盘 │ CPU/电源模式/电量 │ Nix 控制中心
```

| 项目 | 确定值及实施字段 |
| --- | --- |
| 面板 | `thickness = 36`，`radius = 12`，`margin_ends = 14`，`margin_edge = 8` |
| 内部节奏 | `padding = 8`，`widget_spacing = 8`；组内 padding 6、间距 4；时间组 padding 8、间距 8 |
| 表面 | `background_opacity = 0.96`，`border = "outline"`，`border_width = 1` |
| 胶囊 | `capsule = true`，`capsule_fill = "surface_variant"`，`capsule_radius = 8`，`capsule_thickness = 0.78`，`capsule_opacity = 0.96`；不逐个再加边框 |
| 文字 | Noto Sans CJK SC，`font_weight = 500`，`font_scale = 1.0`；时钟单独用 JetBrainsMono Nerd Font，数字等宽 |
| 图标 | 保留 Noctalia 自带图标与应用原图；系统状态单色、应用身份保留彩色；右端保留现有 Nix SVG |
| 阴影 | `shadow = true`、`contact_shadow = true`，全局 shadow alpha 0.38、方向 down |
| 位置 | `reserve_space = true`、`auto_hide = false`、`layer = "top"`；attached 接缝初始 `panel_overlap = 1` |

Noctalia 的正文基准为 14，图标基准为 16，regular 工作区文字基准为 11；工作区单独设置 `font_scale = 1.18`，目标约 13。这里使用已有缩放字段，不把文档中的字号当成不存在的 `font_size` 配置。局部图标看起来偏小先检查其 own widget scale，不整体再叠加显示器缩放。字段与默认尺寸见 [Bar 文档](https://github.com/noctalia-dev/noctalia-shell/blob/fc2af27c0e616006bf858cad3b7c9711a028e501/docs/user/bar/index.mdx) 与 [Style 常量](https://github.com/noctalia-dev/noctalia-shell/blob/fc2af27c0e616006bf858cad3b7c9711a028e501/src/ui/style.h)。

内容规则如下，保持插件功能而约束它们对版面的影响：

- 时钟使用 `{:%m-%d  %H:%M}`，不显示秒；猫保留键盘响应与音频响应，`rave_mode = false`。频谱保留 64 宽、16 bands、蓝青双色、无音频时隐藏。媒体最大宽度 160、`title_scroll = "on_hover"`、无媒体时隐藏，完整曲名在媒体面板查看。
- 布局插件显示图标，`show_text = false`；resize/keymode 移到工作区右侧的独立位置，仅非默认模式出现，避免被折叠隐藏。`dev` 以布局为首项、Portctl 为第二项；`panels` 以 Quill 为首项、Docker 为第二项。两组使用 `accordion = true`、`accordion_direction = "end"`。Docker 继续使用 `running_only`，空闲状态以 `on_surface_variant` 表示。
- 网络沿用 `show_label = false`，SSID 在 tooltip 与网络页；IP 插件保留当前功能，实测其最长地址与托盘展开宽度，不能假定插件支持不存在的截断开关。
- CPU 平常为 primary，数值最小宽度 34；1% 与 100% 不推动邻居。红色只用于异常，电量 ≤20% 使用警告语义，低电量的既有行为不由视觉改动重写。
- tooltip、点击/右键入口保留。日期、百分比、模式名提供文字；不能只凭颜色识别当前工作区、静音或错误。

内屏约 1707 逻辑像素宽，扣两端 margin 后约 1679。验收预算为左段 ≤640、中段 ≤200、右段 ≤570，段间至少 16；这是布局预算，尚未实测。需以九工作区、长媒体标题、IP、五个托盘图标、100% CPU 和 resize mode 同时出现作压力场景。低频 `dev` / `panels` 已声明为 accordion，其他状态组不折叠；不缩小正文或隐藏关键电量/网络状态。锁定实现初始只显示首项，**悬停展开，离开收起**，首项点击仍执行原功能，没有独立展开按钮或持久 collapsed 设置。没有承诺 Tab 能展开胶囊；纯键盘通过 `Alt+Space` → `/pan` 搜索 Mango Layouts、Portctl、Quill、Mini Docker 面板。面板提供器枚举已注册插件面板，未禁用任何插件或删除状态。展开后的宽度、鼠标移动与面板打开行为仍待 GUI 验收。窄外屏采用明确的 per-monitor 区段覆盖，不声称存在自动响应断点。

## 工作区、窗口与层次

工作区采用 regular 有标签胶囊，`label_source = "id"`、`show_labels = true`、`hide_when_empty = false`，固定显示 1–9，保持位置记忆；`active_pill_size = 1.35`、`inactive_pill_size = 1.0`。当前工作区为 primary，已占用为 surface_variant，空工作区用 `#181b20`，紧急为 error；active 的长度与数字同时提供状态线索。`show_all_outputs = false`、`focused_output_only = true`，每块屏只呈现自己的工作区，键盘焦点所在输出显示蓝色当前项。文字由源码按填充色选择可读色，不额外发明 per-state text 参数。[工作区字段](https://github.com/noctalia-dev/noctalia-shell/blob/fc2af27c0e616006bf858cad3b7c9711a028e501/docs/user/bar/widgets/workspaces.mdx)

Mango 保持 `tile,scroller,monocle` 切换，并按下述活动设置工作区默认布局。窗口边框 2、圆角 12；内间距横纵各 6、外间距各 10；单窗口保留边框与间距。focus 为 blue，普通边框为 border，urgent 为 red，scratchpad 为 purple。半透明预览与拖放提示可以使用 accent 的 alpha，应用前景不随聚焦降低透明度。

`dim_unfocused_color = 0x00000010` 为轻微非焦点遮罩，焦点 overlay 为透明。现场比较非聚焦代码注释、图表和低亮度屏幕：如果关键文字仍明显变暗，则关闭 dim，焦点继续由 2 像素蓝边框表达。这个回退是可读性条件，不改变整体配色。

monocle 标签栏已显式适配：高度 32，`tab_bar_decorate_font_desc = "Noto Sans CJK SC 10"`，普通 fg/background 为 foreground/deep，选中 fg/background 为 black/blue，border 为 border，圆角 8。对应 `tab_bar_decorate_{fg_color,bg_color,focus_fg_color,focus_bg_color,border_color,corner_radius}` 均存在于 pinned Mango。当前标签栏使用共享 palette，不再依赖旧 Tokyo Night 试验色。Noctalia 当前 Mango template 输出了 group bar 色，**没有输出 tab bar 色**，所以只换 palette 不会覆盖 monocle 标签栏。[Mango parser](https://github.com/mangowm/mango/blob/1cfb497eea7b18a2fb8372321b7927629208436a/src/config/option_defs.c)、[Noctalia Mango template](https://github.com/noctalia-dev/noctalia-shell/blob/fc2af27c0e616006bf858cad3b7c9711a028e501/assets/templates/mango/mango.conf)

## 透明、模糊、动画与壁纸

Kitty 主背景设为不透明 1.0，使 shell、tmux 和 Neovim 的 `#1f2329` 在截图与实际显示中一致。Noctalia 面板、通知和浮层负责玻璃感，编辑正文有稳定底色。应用正文不统一施加 compositor alpha。

| 层 | 设计值 | 约束 |
| --- | --- | --- |
| Noctalia 浮层 | `shell.panel.transparency_mode = "soft"`，border 1、shadow 开启 | 锁定实现的浮动背景为 0.80、内部卡片为 0.88；保留轻透感，优先保证应用名称和输入文字清楚 |
| 通知 / OSD | alpha 0.97 | 不与文本一起降低透明度 |
| 背景遮罩 | `backdrop.blur_intensity = 0.40`、`tint_intensity = 0.50` | 核对覆盖范围、首开成本和文字对比 |
| Mango 客户端模糊 | 沿用 `blur = 1`、optimized、2 passes、radius 6 | 仅实际透明的客户端受益；Noctalia 的玻璃和 backdrop 不能等同于 Mango 的 client blur |
| layer 效果 | 保持 `blur_layer = 0`、`layer_animations = 0`、`layer_shadows = 0` | 不叠加两套阴影/动画；bar blur 协议请求是否生效单独验收 |
| 窗口阴影 | size 6、blur 16、offset 2/4、`0x00000066` | 浮窗有层次，平铺间隙不形成黑色污边 |

2026-10-18 收尾实机截图显示，居中 Launcher 使用 glass 时后方终端文字清晰透出，干扰应用名称阅读。
据此将共享浮层模式改为 soft，不改 compositor；阴影、圆角、动画与居中构图保持。
上述 0.80/0.88 来自锁定源码，仍需应用后的同场景截图确认改善；若文字穿透仍影响阅读，
官方支持的进一步选择是 `solid`（浮动背景与卡片均为 1.0），不依赖 layer blur 获得可读性。

Noctalia bar 的 `compositor_blur` 只在 compositor 支持相应协议并实际处理请求时有意义。现有 `blur_layer = 0` 下，不承诺面板背后必然出现实时场景模糊，也不为达到效果擅自翻转它；首先检查协议与画面，必要时以 panel 内部 backdrop/更实的表面完成设计。[Bar blur 说明](https://github.com/noctalia-dev/noctalia-shell/blob/fc2af27c0e616006bf858cad3b7c9711a028e501/docs/user/bar/index.mdx)

Mango 默认动效：open 200 ms、close 140 ms、move 160 ms、tag 220 ms、focus 0；open/close 用 zoom，起始/结束比例分别 0.94/0.96，淡入淡出保留；沿用已验证 parser 接受的 `0.46,1.0,0.29,0.99` 曲线。Noctalia `animation.speed = 1.0`，这是倍率，不是毫秒。按键重复切换 20 次不应积压动画；减少动画通过共享 `appearance.reducedMotion` 实现，具体边界见下节。

默认壁纸选用仓库现有 `wallpaper-009.png`：蓝青森林、水面和中央柔光，为石墨面板提供明暗
层次；所有原素材保留。Noctalia 默认与 greeter 使用同一公开资源，锁屏跟随当前壁纸。
固定单张、自动轮换关闭，壁纸转场统一 `fade`、450 ms；不改写 palette，也不引入视频壁纸服务。
已有可变壁纸选择可能继续优先于默认值。本轮用户明确选择统一场景后，由主代理通过官方
`noctalia msg wallpaper-set <009 的最终 store 路径>` 更新连接输出与默认壁纸；不删除 state。
该运行态动作及是否成功以本轮执行记录为准，源码默认值不能证明当前壁纸已经切换。背景填色为 surface，
`screen_corners.size = 12`。实际裁切、浮层玻璃在亮部的可读性须在内屏与外屏截图验收。

## Launcher、控制中心、通知与认证界面

Launcher 使用原生 full layout、浮动居中、宽 720、`search_position = "top"`、`default_view = "recent"`、`app_grid = true`、`compact = false`，显示图标与完整名称/副标题。常用应用通过真实 desktop ID 固定：Kitty、浏览器、文件管理器、编辑器；ID 由实施时枚举确认。保留 tmux、JetBrains、Prism 等现有 providers；calculator 继续仅 `/calc` 显式调用。中文搜索、长文件名、上下键/Enter/Esc、Ctrl+A/E/U/K 都纳入验收。宽度是 full layout 的真实选项，不给内部卡片臆造 padding/font API。[Shell / Launcher 配置](https://github.com/noctalia-dev/noctalia-shell/blob/fc2af27c0e616006bf858cad3b7c9711a028e501/docs/user/configuration/shell.mdx)

控制中心改为 floating center，与 Launcher 同为 720 宽，二者显式关闭 `open_near_click`，键盘与面板点击都使用中央构图。`sidebar = "full"`、`sidebar_section = "full"`，保留快捷方式标签。Home 给出用户、媒体、日期天气与入口；音频、网络、蓝牙、显示、系统、通知使用原生 tabs，具体内容沿用已有服务。常用滑块、开关与设备名直接可见；不重排上游未开放布局的内部卡片。布局插件自身面板放置沿用锁定 manifest（floating / bottom_right）。下方两个 hot corner 沿用 200 ms 延迟，上方关闭。[Control Center](https://github.com/noctalia-dev/noctalia-shell/blob/fc2af27c0e616006bf858cad3b7c9711a028e501/docs/user/control-center/index.mdx)

通知设置右上角，`width = 360`、`offset_x = 14`、`offset_y = 56`、`max_visible = 3`、border 1、alpha 0.97，避免覆盖顶部面板。继续 `follow_focused_output = true`；已经出现的通知留在原输出，不因鼠标移动跳屏。正常通知显示应用名、正文与动作，critical 使用原生加粗边框；错误文案保持可读前景，红色负责警示。保留当前 overlay 行为，专注/演示时使用原生勿扰；不新添后台规则替用户吞通知。OSD 保留右上与跟随焦点，现场检查与通知栈碰撞；未核对的 OSD offset 不写成确定配置。[通知字段与语义](https://github.com/noctalia-dev/noctalia-shell/blob/fc2af27c0e616006bf858cad3b7c9711a028e501/docs/user/services/notifications.mdx)

锁屏采用同一静态壁纸与配色，`blurred_desktop = false`，blur 0.40、tint 0.60；较暗的背景承托中央时钟与认证框。
锁屏有独立转场池，现明确为单一 `fade`、550 ms；不再继承上游随机效果池和 1500 ms 默认。
锁定实现会为转场临时捕获桌面（内存中留至解锁），这与使用桌面截图作为持续锁屏背景不同；
没有 screencopy 能力或捕获失败时跳过转场。`reducedMotion` 使用空池，避免这项动画捕获。使用原生 regular login box、圆角 14、背景 surface_variant/0.94、输入框 radius 8/opacity 1.0；保留认证提示、Caps Lock、键盘布局和会话按钮。媒体摘要关闭、天气保留，时钟单独配置为原生 clock widget，使用 Noto Sans CJK SC、居中文本、无底板、保留文字阴影。`lockscreen_widgets` 的坐标属于真实输出：内屏按约 1707×1067 逻辑画布，clock 初始中心约 (853, 240)、box 360×100，认证框按同一输出的逻辑尺寸计算中央；时钟 x 为逻辑宽度的 1/2、y 为逻辑高度的 22.5%，外屏仍须按真实输出建立记录，不复制物理像素坐标。这些 widget 类型和字段已支持，最终坐标、实际尺寸与边界仍须解锁状态预览验证。[Lockscreen widgets](https://github.com/noctalia-dev/noctalia-shell/blob/fc2af27c0e616006bf858cad3b7c9711a028e501/docs/user/lockscreen/widgets.mdx)

Greeter 由主机显式生成 `appearance.scheme = "Synced"`、`theme_mode = "dark"`、完整 `appearance.palette`、同一可公开壁纸的 store 路径、Noto Sans CJK SC、与 shell 一致的圆角 scale 1.1。其 palette 使用 `primary` 等 snake_case 字段，不直接塞 Noctalia JSON 的 `mPrimary`。时间在 above-panel，24 小时、日期 `%m-%d %A`；隐藏 scheme selector 与底部品牌 logo，保留右下电源按钮、当前 random password mask 与 Mango 默认会话。`greeter.toml` 的完整 palette 优先于 mutable `sync.toml`，不用 shell 运行时同步来取得登录前必需的颜色。字体/壁纸必须进入系统可访问 closure，不能指向个人 home。[Greeter 配置及优先级](https://github.com/noctalia-dev/noctalia-greeter/blob/05fc8e3763de7940233358b5e0b1a5ae1967bcf1/docs/user/configuration.md)

本轮场景表面统一使用外框、下投影和清楚的输入框；`shell.shadow.alpha = 0.38`、
`corner_radius_scale = 1.1`，内部 `button_borders/card_borders = false`，
`input_borders/popup_borders/popup_shadows = true`、`list_item_background = true`。
`floating_offset = 12` 统一浮层边缘间隔；居中布局不依赖该偏移模拟自定义坐标。
未修改插件、会话与认证行为，也没有引入新壁纸资源。折叠规则、透明度与字段依据
[Bar 实现](https://github.com/noctalia-dev/noctalia-shell/blob/fc2af27c0e616006bf858cad3b7c9711a028e501/src/shell/bar/bar.cpp)、
[面板提供器](https://github.com/noctalia-dev/noctalia-shell/blob/fc2af27c0e616006bf858cad3b7c9711a028e501/src/launcher/panel_provider.cpp)、
[表面透明度实现](https://github.com/noctalia-dev/noctalia-shell/blob/fc2af27c0e616006bf858cad3b7c9711a028e501/src/config/config_types.cpp) 和
[壁纸 IPC](https://github.com/noctalia-dev/noctalia-shell/blob/fc2af27c0e616006bf858cad3b7c9711a028e501/docs/user/ipc/media-and-ui.mdx)。
本轮 Astra 已完成两个 Nix 文件的定向格式、语法解析和差异空白检查；
生产配置校验、构建、应用由主代理记录。hover 展开、`/pan` 操作、亮区文字对比、锁屏和下次 greeter 的
实际构图仍待 GUI 验收，不以源码支持代替运行结果。

## 应用之间的协调

| 消费者 | 实施目标与边界 |
| --- | --- |
| GTK 3 | 保留 `adw-gtk3-dark` 与 Papirus-Dark，通过现有 Noctalia gtk3 template 渲染固定 palette |
| GTK 4 / libadwaita | 保留 `gtk4.theme = null` 和 prefer-dark，由现有 gtk4 输出提供可支持的颜色；逐个检查原生控件，不保证所有应用私有 UI 完全同色 |
| Qt | 保留 qt6ct + Fusion、Papirus-Dark；qt6ct 的 mutable 入口继续引用单一 Noctalia palette 输出。Qt5、硬编码主题及第三方弹窗逐个验收 |
| Firefox | 继续现有 userChrome template/application hook，输出固定 palette；标签、地址栏、侧栏与菜单统一。网站正文遵循网站自己的主题，不全局反色 |
| Fcitx5 | 已使用自己的固定 Darker 资源，替代旧 `Tokyonight-Mayon` 派生主题；背景 background、前景 foregroundStrong、选中 blue/black。保留现有 10 pt 字体和紧凑 padding，保留 Wayland/X11 DPI 修正依据 |
| Kitty | JetBrainsMono Nerd Font 11 pt、padding 8、隐藏应用装饰、背景 opacity 1.0；ANSI 与上述 terminal 数据一致，光标 beam 1.5，主题不再运行时随 shell 改写 |
| tmux | 状态栏一行、底部；左会话、中央窗口、右前缀/复制模式，现有条件日期可保留。普通背景 default，活动项 ANSI blue/black，copy mode yellow/black；仍从同一 ANSI palette 取色 |
| Neovim | 保留现有 Lua 高亮、状态线、tabline、补全、诊断和语法色；Normal/NormalNC 固定 background。只有 palette 数据进入公共外观接口，Lua 行为与插件适配仍由编辑器拥有 |
| Swayimg / Fastfetch | Swayimg 信息浮层采用共享 Noto Sans CJK SC 11 pt、brightFg/deep，图库和选择色继续来自 palette；Fastfetch 普通电池标签用蓝色，避免常态错误红色 |
| 其他模板消费者 | btop、Obsidian、VS Code、Yazi、Zathura 继续现有模板选择，逐个检查生成文件与重载行为；不因统一外观删除现有软件或插件 |

鼠标保持 Bibata-Modern-Ice 24，应用图标保持 Papirus-Dark；中文 UI 使用 Noto Sans CJK SC，等宽内容使用 JetBrainsMono Nerd Font。不把 Nerd Font 作为全部桌面文字字体。GTK/Qt 的字体设置需各自适配，不能以设置 Noctalia `font_family` 代替。浏览器与代码编辑区保持足够内容密度，应用自己的标题栏高度不强行伪装为同一个 36 像素条。

## Neovim：OneDark 工作台重设计

用户随后否定自写组件的实机表现，要求按旧 Nixvim 的效果重新设计，并明确继续采用当前
One Dark Darker；TokyoNight 只作历史画面参考。实际 Astra 负责本轮设计，不以历史截图
推导性能结论。具体实施和构建/应用证据见[重建记录](neovim-rebuild-execution.md)。

- 主题由锁定的 `onedark.nvim` darker 完整实现负责，共享 `#1f2329`、palette 和终端 ANSI
  保留。薄适配管理表面关系，不再手写整套语法高亮。正文不透明，Context 融入正文；
  通知和搜索正文使用实底，避免文字叠读。浮窗、输入框和补全保留圆角与清楚边界。
- Snacks explorer 左侧默认 38 列，一项一行；文档保持自动折行和按词断行，保留续行缩进，
  不再用全局 nowrap 裁掉 Markdown 段落。代码 Context 最多三行、不另占分隔线，
  Markdown/AI 文档不重复固定标题。
- Heirline 使用深底状态栏、小面积模式强调与右侧位置胶囊，按可用宽度组合 Git、文件、诊断、LSP、AI 和位置；Navic 最多三级。
  顶部项目区随 Explorer 实际宽度对齐正文，当前、可见、后台文件有三级区分。
  未修改的空白占位从标签展示过滤，未保存内容继续可见；标签点击选择正文窗口，保留侧栏。
- Markdown/CodeCompanion 恢复原插件的标题、代码、表格等渲染；插入模式仍渲染，Visual
  使用源字符以准确选择。公式使用 Snacks 图像与专门触发器，PDF 外开保留单一 owner。
- Snacks 通知采用 compact、2500 ms、从底部出现；普通 LSP 进度只更新状态栏，不刷 toast。
  状态栏只显示当前缓冲的紧凑进度，不放滚动的扫描计数。滚动短动效尊重 `reducedMotion`，
  dim 同步关闭范围动画，缩进线为静态作用域提示。
- Blink 菜单按图标、名称/描述、来源分列，最多九项，省去重复类型名称；文档窗上限 60×18。
  Lua 补全接入 lazydev，LuaLS 只按需补充依赖库，不再预加载全部 runtimepath；项目自有
  `.luarc.json` / `.luarc.jsonc` 时退出库注入，保持原生根目录探测。

文件树和成熟插件仍需数据保护适配：重命名保留未保存正文、拒绝覆盖目标，删除须有垃圾桶
工具且不能丢掉未保存缓冲。会话、草稿、撤销和 AI 历史不随配置重做而迁移或清空。
真实文件树操作、窄窗口/CJK 标签、Markdown 长段落、补全和 Java LSP 仍按记录区分隔离
检查与真实终端验收；不把插件配置或无报错启动当作视觉已完成。

## 单一写入者与现场交接

当前声明已固定 dark/custom palette；Kitty 是单一 HM renderer，不再由 Noctalia 模板维护 include。
历史上的 mutable Kitty stub、Tokyo Night 自动主题及 Mango palette 模板属于迁移前配置，
不是当前源码。真实会话仍可能来自旧 generation，因此应用前后要按[配置归属](config-ownership.md)
核实实际文件与 writer；不能把声明删除当成旧 hook 或进程已经退出。

| 产物 | 当前声明的唯一写入者 |
| --- | --- |
| 公共 palette、Noctalia custom JSON、Kitty 配置、Neovim palette、Fcitx theme | 对应功能的 Nix/HM renderer |
| Noctalia 配置、模板选择 | HM renderer；sidecar helper 仅移除已声明公开键的 override，未知 state 保留 |
| GTK CSS、Qt palette、Firefox managed CSS、已选社区主题输出 | Noctalia 模板及所属 feature 的有限 hook；Nix 不重复拥有同一完整文件 |
| Mango 配置与颜色 | Mango renderer，包含 tab/group/jump、scratchpad/global/overlay/最大化边框 |
| Greeter palette 与公共资源引用 | host greeter renderer；不依赖用户会话同步取得登录前资源 |

首次应用仍需检查旧文件类型、冲突与备份，完整退出旧 writer 后交接，再验证 Noctalia theme
apply/undo、Kitty 新窗口、tmux attach、Neovim 与 GTK/Qt/Firefox。不得删除应用历史、模型、
项目或整个 Noctalia state。运行 mod 任务期间不执行这一应用流程。

Noctalia 已由绑定 Mango target 的 systemd 用户服务唯一启动，设置有限 on-failure 恢复预算。
Mango HM 的非空 autostart 是补充同步；C 实现会更早请求 session target。安全静态环境经同源
白名单预先投递给 user manager 与 Noctalia，不依赖 autostart 与 C 启动的先后顺序。
新 manager 环境、冷登录/退出顺序和 `launch_apps_as_systemd_services` 下的应用存活仍需实测。
依据：[Noctalia HM](https://github.com/noctalia-dev/noctalia-shell/blob/fc2af27c0e616006bf858cad3b7c9711a028e501/nix/home-module.nix)、
[Mango HM](https://github.com/mangowm/mango/blob/1cfb497eea7b18a2fb8372321b7927629208436a/nix/hm-modules.nix)、
[Mango 启动](https://github.com/mangowm/mango/blob/1cfb497eea7b18a2fb8372321b7927629208436a/src/main.c)。

## 可读性、缩放与外屏

以 sRGB 相对亮度计算，不透明 foreground/background 对比约 **6.60:1**，foreground/selection **5.09:1**，foregroundStrong/surface **9.52:1**。muted/background 只有 **4.03:1**，muted/surface **3.57:1**；error/background **4.36:1**，因此小字号必要正文不能只涂 muted/red。错误提示用可读正文加图标/边框，选中彩色控件用 black 文字；输入框焦点、错误、禁用和 hover 必须能通过形状/文字辨认。

透明表面的实际对比取决于背后的画面，不能直接套用上述数值。用纯白窗口、浅色网页、高细节壁纸与深色壁纸分别置于浮层后方，检查 100% 与实际 150% 缩放下的中文字、数字、选中项。验收目标：必要小字 ≥4.5:1，大字/主要非文本状态指示 ≥3:1；装饰边框不承担唯一状态信息。这些是本项目验收门槛，本文没有声称整桌面已经符合某项无障碍认证。

内屏事实保持 `eDP-1`、2560×1600、165.002 Hz、scale 1.5；约 1707×1067 逻辑工作区。面板 36 在此对应 54 物理像素，2 像素边框对应 3；字体应用自身单位，不机械换算所有 pt 为逻辑 px。`Xft.dpi = 144` 与 `xwayland_ignore_scale = 1` 的现有配对、Mango 会话环境注入以及 Fcitx `PerScreenDPI` 修正按源码/运行行为保留。[桌面常量](../inventory/hosts/nixos-btw/facts.nix)、[Mango 模块](../aspects/interactive-session/mango.nix)、[输入法模块](../aspects/interactive-session/input-method.nix)

外屏连接器、分辨率、刷新率与物理尺寸尚未取得；实施时读取真实输出，按 EDID/connector 配置。通常 1080p/1440p 外屏从 1.0、4K 从 1.5 或 2.0 做现场字号比较，这些是测试起点，不是硬件事实。不得直接复制内屏 scale 1.5 到所有外屏。Noctalia 每屏使用相同逻辑尺寸，必要时以 `bar.main.monitor.<id>` 覆盖 `start/center/end`；窄屏先折叠工具组，完整功能仍由原生面板/launcher 可达。

混合缩放验收必须覆盖窗口跨屏、鼠标/拖拽坐标、截图/屏幕共享、Fcitx 候选、Qt/GTK、Electron、Steam 与实际 XWayland 应用。XWayland 的全局 DPI 不能承诺每屏无缝独立缩放。greeter 已使用内屏 `output.scales` 映射，没有全局强制 scale；未知外屏使用其自动缩放，新增固定值前须记录真实输出事实。外屏断开后认证框、通知、launcher 必须回到可见输出。

## 窗口场景、临时工具与减弱动效

普通工作区默认：1 开发 tile/60%，2 资料 scroller/80%，3 通讯 tile，4 文档 monocle，
5 专业工具 tile/65%，6 媒体 monocle，7 虚拟化 tile，8 游戏 monocle，9 临时 tile。
Tag 0 使用 scroller/65%，遮罩 0.32，内间距 8、外间距 20。它是可开合的工具工作区，
不是把所有工具永久浮动；不按 app-id 把普通应用自动搬到编号。布局入口和工作区数字保持不变。
锁定 `reapply.c` 将 id 0 应用到 pertag slot 0，`client_switch_view` 在 TAG0_MASK 时使用该 slot。

概览使用内间距 12、外间距 24，保留跳转标签、已有四指手势与 `Super+0`。
命名工具新增独立 Kitty class 的 Yazi（78%×78%）和 btop（72%×74%）；临时终端为 78%×78%。
三个工具一次显示一个，跨屏召回到当前输出；窗口隐藏不终止其任务。Kitty/Yazi/btop 命令均为
明确 store 路径，独立选择交互会话也能启动这些声明入口。详细按键见[操作方式](workflow-design.md)。

浮窗宽高比例以当前输出的完整逻辑尺寸（`mon->m`）计算，不是扣除面板后的可用区；
实际窗口仍受客户端尺寸提示约束。浮窗规则只扩展已知身份：Swayimg 60%×72%；portal 文件选择 62%×68%；Noctalia 设置
68%×82%；Thunar 重命名只指定浮动与 fade，保留内容尺寸提示。父子窗口关系、size hints 和
模态交互继续由 Mango 与应用处理；默认是输出工作区居中，不承诺父窗精确居中。Firefox
`Picture-in-Picture` 为 480×270，offset_x/y 85/80（剩余空间百分比），跨 tag、安静打开，
默认不 overlay；用户可分别切换 global 与 overlay。跨 tag 的青色边框、置顶的紫色边框
来自共享 palette，最大化边框也使用蓝色。多状态同时存在时遵循 Mango 优先级（global 高于 overlay）；
状态操作与说明不只依靠颜色。

工具、设置和 PiP 使用 fade；主窗保留轻 zoom；Steam 游戏窗口关闭窗口动画。
这些是每窗动画类型，不是每窗独立时长。Mango 支持 `layer_rule`：锁定 Noctalia 的
`noctalia-bar-*`、`noctalia-panel`、`noctalia-attached-panel`、`noctalia-notification`、
`noctalia-osd`、`noctalia-window-switcher`、`noctalia-panel-click-shield` 禁止重复合成器动画/阴影；
`noctalia-screenshot-region` 与 `noctalia-annotate` 另外禁止 blur。全局 layer 效果仍关闭，
没有按猜测启用截图程序或外部 shell 的 namespace；认证 lock surface 不伪装成 layer window。

`appearance.reducedMotion` 默认 `false`。显式选 `true` 时：Mango animations=0；Noctalia
shell animation 关闭，壁纸/锁屏 transition=[]，媒体不滚字、天气 effects 关闭，面板移除猫与
频谱；Kitty 光标停止闪烁。插件配置、媒体入口与用户 state 均保留。该参数不改变 GPU、电源、
模糊或应用自身动画，不是自动省电策略，也没有新增常驻切换器。单独 host/user 外观输入各自生效。

社区参考：[end-4](https://github.com/end-4/dots-hyprland) 的概览与一致浮层、
[niri](https://github.com/niri-wm/niri) 的资料宽度和空间组织、
[meloworld](https://github.com/melatonia/meloworld-dotfiles) 的统一开合节奏，
[Victoria](https://github.com/kohagizpk/victoria-mangowm-dotfiles/blob/master/rule.conf) 的规则分类，
[Alphonso](https://github.com/Harman1307/Alphonso) 的动效分档。移植的是设计原则；
Alphonso 使用 mango-ext，自绘 Quickshell、fork canvas、任意 shader、视频锁屏及 niri 的动态
workspace/外屏恢复没有作为当前实现承诺，也未安装第二套 shell。

## 性能测量与验收

美观预算通过本机 A/B 测试确认，不预设“模糊仅消耗几瓦”或“动画零开销”。GPU polling 保持现有 `gpu_poll_seconds = 0.0`，采样时也避免用持续 `nvidia-smi` 唤醒独显，测量工具本身可能改变待测状态。

每组固定亮度、刷新率、电源模式、壁纸、窗口数量与后台负载；暖机后测 5 分钟、重复 3 次，记录中位数与波动。顺序覆盖基线（当前配置）、固定色但无频谱/猫音频响应、完整设计、关闭模糊；只改变一个变量，插电/电池和单屏/双屏分别记录。常见场景是静置、中文输入、快速切换工作区、媒体播放、拖动透明浮窗和打开/关闭控制中心。

| 指标 | 方法与项目验收门槛 |
| --- | --- |
| shell/compositor CPU | 用进程统计区分 Mango/Noctalia/plugin 子进程；静置 CPU 增量目标不超过一个逻辑核的 1 个百分点，须高于噪声才判断回归 |
| 内存与重复操作 | 记录 RSS/PSS；连续开关面板 100 次后静置，比较前三轮，不应持续单调增长；一次缓存增长不直接判泄漏 |
| 响应 | launcher 首次可输入目标 ≤150 ms；20 次 tag 切换不积压；可用带时间标记的视频/合成器可用 trace 估计，测量分辨率需记录 |
| 帧时间 | 165 Hz 帧周期约 6.06 ms、60 Hz 约 16.67 ms；这是周期换算，不是已测延迟。记录重复操作的掉帧与可获得的 p95/p99，不能用应用 FPS 代替 compositor 帧时间 |
| 电池 | 从电池遥测或外部功率计采样相同区间；完整设计静置功耗增量目标 ≤0.5 W 且不超过基线 10%，必须结合重复测量误差；无可靠遥测则标未验证 |
| GPU 状态 | 对比独显 runtime power 状态及唤醒原因；静态桌面不应因新视觉轮询长期唤醒独显；外屏物理接线导致独显常开另记 |

超预算按固定顺序减负：先关闭 BongoCat 音频响应，保留按键动画；再从面板移除频谱；再将 Mango blur 关闭并把透明浮层改 soft/solid；最后关闭非必要动画。每一步重测，不用缩小文字或删通知/设备控制换性能。上述阈值是验收目标，当前没有功耗、CPU、GPU 或帧时间实测结果。

最终交付至少留以下截图与记录：空桌面、双窗代码+浏览器、全部面板区块最宽状态、launcher 中文结果、控制中心、三条通知/OSD、Fcitx 候选、锁屏与 greeter、实际混合缩放双屏。截图只使用无敏感内容的测试工作区。确认颜色、字体、裁切、焦点、点击热区、接缝、tooltip、键盘导航，再将采用的参数写回声明配置。

## 设计阶段证据与应用后未验证项

以下首先记录早期设计证据；本轮窗口与动效优化的实际检查另见执行记录。早期阶段只新增本文。读取当时模块、公共桌面常量、Neovim Lua palette 和架构设计；通过只读 Nix 输入求值得到当前 locked store source，检查官方随包文档、Mango parser、Noctalia template 与插件 manifest。额外打开官方 GitHub 固定 revision 页面确认来源。上述对比度已实际运行 Python 按 sRGB 线性化和相对亮度公式计算，并非目测；只证明列出的不透明色对，不证明透明合成后或屏幕校色后的对比。没有运行全仓 `nix fmt`、系统构建或 switch，因为未改运行配置且工作树有大量已有修改。

| 输入 | 本轮核对 revision |
| --- | --- |
| Noctalia | `fc2af27c0e616006bf858cad3b7c9711a028e501` |
| Mango | `1cfb497eea7b18a2fb8372321b7927629208436a` |
| Noctalia greeter | `05fc8e3763de7940233358b5e0b1a5ae1967bcf1` |
| 官方插件 | `9aec34181e46789b281263942092ac552f661d1a` |
| 社区插件 | `7691612a091ac903cab79ffa5b3f740a04808ef1` |

BongoCat 的 evtest/input_devices/audio_spectrum 与布局插件的 show_text/show_glyph 来自相应 locked `plugin.toml`；它们继续使用现有权限与依赖，不新增私有插件 API。配置查证覆盖 Noctalia palette、bar/per-monitor/group/widget、工作区、shell/launcher/control-center、通知、锁屏、greeter，以及 Mango 颜色/标签栏 parser、Kitty hook 和 HM 服务接线；既有模糊/动画字段也对照当前模块。本次 Den 实现已将目标生成 TOML/Mango 配置并通过锁定 validator 和严格结构检查；构建结果见实施记录。所选参数仍须经过真实应用启动和上述 GUI 验收。未验证：外屏硬件与混合 DPI、soft 在明亮/高密度背景上的最终可读性、全部插件同时出现时的面板宽度、锁屏坐标、Qt5/私有应用主题、颜色模板衍生 token 与性能预算。实施中若 pin 改变，应重查这些字段与原有 workaround 原因。
