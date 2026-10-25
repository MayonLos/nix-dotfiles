# One Dark 精修桌面

现行视觉依据为 [Astra 设计稿](visual-design.md)，2026-10-24 用户确认。
第十九轮科技版与壁纸回退见[本轮执行记录](history/ui-v4-2026-10-25.md)；早期实施见[桌面视觉执行记录](history/visual-desktop-2026-10-24.md)。
仅修改声明并验证构建，没有激活系统或改写用户目录。旧轮次设计和测量有其时间范围，
历史取舍见[第九轮记录](history/desktop-polish-2026-10-24.md)。

颜色唯一来源是共享 [palette](../aspects/appearance/appearance/onedark.nix)：
桌面 bg、卡片 surface、选择 selection；正文 brightFg、必要次级文字 fg，
blue 标示焦点和短选中标签。无整块蓝色选中行。桌面字体 Inter，中文回退 Noto Sans CJK SC；
Mango tab/group/title/jump 与科技版读数使用 Maple Mono NF CN。配置接口与职责遵循[架构规范](architecture-design.md)
和[写入归属](config-ownership.md)。palette 文件与运行态主题选择统一名为 `onedark`。

| 界面 | 实施目标（设计稿章节） |
|---|---|
| Noctalia 顶栏 | §3–4：40 高、8/16 外距、12 外圆角；组内 8 圆角、selection 活动工作区蓝字；中文日期，保留托盘/状态入口和低频插件 |
| Launcher / 控制中心 | §5：680 全布局，pinned；控制中心 compact sidebar，浮动右上 offset12；本地源码主题适配将选中行与活动开关改为 selection 底、蓝色小标记，保持 Primary 蓝字语义 |
| 通知 / OSD | §6：380 通知，16/64 定位，最多3条；OSD 底部32、20格分段细轨与等宽数值；均 .98 背景、1 outline；warning 是 normal 消息附文字/图标，critical 保留原生红边 |
| 锁屏 / greeter | §6：共享 `wallpaper-005.png` 默认壁纸，中文日期；锁屏 compact 输入、不显示天气/媒体，blur .40、tint .48、淡入200ms；科技版认证下划线、等宽读数与原生会话选择，局部源码补丁见功能 README |
| Mango | §3、§7：2px 焦点蓝边、12 圆角，inner8/outer16；tab/group/title/jump 的 selection/blue；overview16/32；焦点 blue/.22 柔光、非焦点 black/.32 阴影、offset0/0；正文不透明，无 dim，无 layer blur/shadow/animation |
| 壁纸 | 恢复原冷色 `wallpaper-002/005/008/009/011.png` 五张轮换，默认桌面、锁屏与 greeter 共用 `wallpaper-005.png`；保留用户 `local/` 递归轮换，不生成图像也不下载照片 |
| 可选 Xorg | 仅外观跟随，复用同一默认图；dwm/dmenu/Dunst/Picom 不增加新会话行为 |

壁纸资源为仓库内既有图像，不再有构建期生成器或外部照片来源。`managed` 为只读内置壁纸软链，用户 `local/` 只在应用时缺失则创建；两者在同一父目录中，
Noctalia 递归扫描跟随软链。锁屏使用当前壁纸；其声明默认与 greeter 同为 005。锁定自动轮换也会在 shell 启动时随机选图，锁屏随桌面当前图。

Astra 的 S1–S3 阴影、面板行高/卡片尺寸、72px 锁屏时钟等部分值属于视觉目标；
只使用锁定原生接口或明确的局部源码 patch，不虚构配置项。
精确尺寸、用户卡原生壁纸 tint、禁用态文字、白色窗口后的 .98 合成、多屏缩放、
最长日期/九工作区/五托盘图标、长中文通知、认证失败与性能仍需实机截图验收。

`notify-send` 随本 feature 安装，用隔离审查消息检查普通/警告语义/critical；
构建检查不会发送通知、打开用户状态或应用配置。功能与状态归属另见
[Mango README](../aspects/desktop/mango-session/README.md)、[greeter README](../aspects/desktop/greeter/README.md)
和[Xorg README](../aspects/desktop/xorg-session/README.md)。

## 应用之间的协调

| 消费者 | 实施目标与边界 |
| --- | --- |
| GTK 3 | 按 Astra §10 保留 `adw-gtk3-dark`；共享支持提供 palette 原色模板资产束，Noctalia 仍独占 CSS 与 import hook。Thunar 主面 bg、侧栏 deep、工具栏 surface；选中 selection 底与 2px 蓝色内侧标记，路径/表格/status 读数使用 Maple Mono；sidebar 宽度保留用户窗口状态 |
| GTK 4 / libadwaita | 保留 `gtk4.theme = null` 与 prefer-dark，经同一 Noctalia 资产束提供原色；私有绘制与未暴露的控件几何遵循原生实现 |
| Qt | qt6ct + Fusion，Window=bg、Base=deep、Button/AlternateBase=surface、正文 brightFg、Highlight=selection、HighlightedText=brightFg、Link=blue、PlaceholderText=fg；初始 seed 与 Noctalia runtime 模板一致，既有 GUI 偏好保留。QPalette 不负责圆角 |
| Firefox | Astra §10：地址栏高 32、圆角 8、蓝焦点线 2；地址与标签读数使用 Maple Mono；原生垂直标签高 36、间隔 4、中性选中底与蓝短标记。单一 seed/template hook 同时维护 userChrome/userContent 的标记块；新标签页原生搜索框约 560×48、最多一行 8 个常用入口，网站正文保持自身主题 |
| Fcitx5 | Astra §10：明确横排、每页 7 项、Pango 字号 13 pt，保留 Wayland/X11 DPI 修正；bg/brightFg，序号与注释 fg，高亮 selection/blue 加 1px 蓝边，外圆角 12、选项圆角 8，不增加 compositor 阴影 |
| Swayimg / Fastfetch | Swayimg 信息使用不透明 brightFg/deep，图库 selection 底与 2px 蓝边；Fastfetch 由 CLI 分支负责 |
| 文档、媒体与其他应用 | Zathura 与 Obsidian 改用 documents 拥有的 palette 原色模板，退出同名社区模板选择。Zathura 阅读底不透明，PDF recolor 默认关闭，UI 等宽并显示页百分比；按 `Tab` 进入原生目录索引模式，无常驻目录侧栏；原生不支持左选中条与独立细进度线。Obsidian 只对其注册的 vault 接线同名 snippet。mpv/uosc 使用 brightFg 正文、中性选择面、蓝匹配标记与 2px 蓝色选中条，时间等宽、进度线 2px；uosc 不提供选中标记发光选项，采用平面蓝线。OSC 圆角 8。Thunderbird 无既有自定义主题接线，保留原生暗色/GTK 支持。btop、VS Code、Yazi 由各自分支负责 |

鼠标使用 phinger-cursors-light 32，应用图标保持 Tela-circle-dark，文件夹采用 blue。
外观只拥有 `fonts.sans = "Inter"`、`fonts.cjk = "Noto Sans CJK SC"`、
`fonts.mono = "Maple Mono NF CN"`、`iconFolderColor = "blue"` 等公共数据；GTK 与 Dunst
GTK、Qt 和 Dunst 共用 Tela-circle-dark 默认蓝色图标；不再对 Papirus 做重着色。Dunst 从公开 GTK option 复用相同的名称和包。
GTK、面板、控制中心、Mango 装饰、greeter、锁屏、Swayimg 与 Zathura 界面均用 Inter；
Qt 新配置使用相同字体，既有配置只迁移精确匹配旧仓库完整字体默认值的字段，其他 GUI 偏好保留；
中文优先的 Fcitx 候选和 mpv 字幕用 `fonts.cjk`，mpv OSD 用 `fonts.mono`。
系统 sans-serif 顺序为 `[ "Inter" "Noto Sans CJK SC" ]`，monospace 跟随 Maple；
Noctalia 面板时钟与 dwm 栏使用 Maple，dwm 另有公开 CJK 字段作为回退。
Kitty 保持 11 pt：内屏 2560×1600 / scale 1.5 下约 1707×1067 逻辑空间，
仅更换家族不足以决定缩字号，最终宽度与行距留待真实窗口比较。Maple 自带 Nerd/CJK 字形，
Kitty 原本没有 `symbol_map`，本轮也无需新增；保留独立 Symbols Nerd Font Mono 包供其他应用回退，
没有显式字体的 tmux/终端 Neovim 继承 Kitty，JetBrains Mono 字体包已移除。

当前锁定 Noctalia `5f864d472676c77e5310881b243f15cc371bb223` 的 `src/render/text/cairo_text_renderer.cpp` 使用
`pango_cairo_font_map_new`、`pango_font_description_set_family` 与 `pango_layout_set_text`，
没有关闭 Pango 缺字回退；因此按家族名请求 Inter 不会限制为仅 Inter 字形。
当前 pin 已是原生 C++/Pango，不能按旧 Quickshell/QML 实现推断。构建检查使用真实 host
生成的 fontconfig 规则、隔离 HOME 和 `fc-match 'Inter:lang=zh-cn:charset=4e2d'`
验证中文选择 Noto Sans CJK SC；这证明字体选择，不替代面板中文裁切与混合文本实机验收。
字体文件 family 与全部构建结果见[第三轮记录](history/optimization-2026-10-24.md#第三轮字体图标与-atuin)。

不把 Nerd Font 作为全部桌面文字字体。GTK/Qt 的字体设置需各自适配，不能以设置 Noctalia `font_family` 代替。浏览器与代码编辑区保持足够内容密度，应用自己的标题栏高度不强行伪装为同一个 36 像素条。


## 输入法与 CLI 的统一适配（第七轮）

Fcitx5 保持 Rime-Ice 与两张专业补充词表，候选页改为 7 项。万象简体模型由
[rime/package.nix](../aspects/desktop/session-support/rime/package.nix) 固定 `LTS` release
的 2026-10-19 资产和 SHA-256，作为只读 store 链接加入 fcitx5-rime 的 `share/rime-data`。
上游 `LTS` 标签长期复用，因此可复现性由固定 hash 保证；不在登录时下载或自动换模型。
语法权重采用[白霜推荐参数](https://github.com/gaboolic/rime-frost#使用语言模型)，启用
contextual suggestions，同音/同形候选上限为 4/2。锁定 nixpkgs 将 Lua、Octagram
合并进 `librime.so`；显式保留两插件，Rime-Ice 的 Lua 过滤、纠错与日期功能继续可用。
学习写入仍是原有 `rime_ice.userdb`；不接管个人短语、同步或历史。

候选框借鉴 [Catppuccin Fcitx5](https://github.com/catppuccin/fcitx5) 的 SVG nine-slice
方式：12px 外圆角、1px 边线、8px 高亮圆角；第十四轮按 Astra §10 改为横排、13 pt、选中项 selection/blue，正文 brightFg，序号/注释 fg。
背景切片边距为 12，内容边距 6，文字边距横 10/纵 5；没有新增 compositor 阴影。
SVG 由同一 palette 生成，图标不再依赖 default-dark PNG。构建检查解析 INI、核对所有
Image 路径并渲染 SVG；实际 150% 缩放下的文字位置与圆角仍需现场观察。


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
项目或整个 Noctalia state。运行 mod 任务期间不注销、不切换当前 compositor、不终止业务；只按核验过的边界交接独立服务。

Noctalia 由 systemd 用户服务唯一启动，随 Mango session target 拉起，设置有限 on-failure 恢复预算。
Mango HM 的非空 autostart 是补充同步；C 实现会更早请求 session target。安全静态环境经同源
白名单预先投递给 user manager 与 Noctalia，不依赖 autostart 与 C 启动的先后顺序。
新 manager 环境、冷登录/退出顺序和 `launch_apps_as_systemd_services` 下的应用存活仍需实测。
依据：[Noctalia HM](https://github.com/noctalia-dev/noctalia-shell/blob/5f864d472676c77e5310881b243f15cc371bb223/nix/home-module.nix)、
[Mango HM](https://github.com/mangowm/mango/blob/900b8d7e06c396a20b6d4e56f242c4e240a69dfa/nix/hm-modules.nix)、
[Mango 启动](https://github.com/mangowm/mango/blob/900b8d7e06c396a20b6d4e56f242c4e240a69dfa/src/main.c)。

