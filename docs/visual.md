---
summary: One Dark 配色令牌、用色规则、字体和桌面现行尺寸
read_when: 调整任何界面的颜色、字体、圆角、间距、透明度或动效
code: [aspects/appearance/appearance/onedark.nix, aspects/desktop/mango-session/mango.nix, aspects/desktop/noctalia-shell/noctalia.nix, aspects/desktop/noctalia-shell/services.nix, aspects/desktop/session-support/gtk.nix]
checks: [palette-contrast, gtk-qt-theme, unified-noctalia-session]
---

# 视觉规范

**颜色的唯一来源是 `onedark.nix`。** 数值以源码为准，本文记录语义和 2026-11-15 从源码核对的现值。
所有应用固定深色，不从壁纸取色，不新增源色；派生色只由源色和透明度混合得到。

用户偏好：One Dark、低饱和、下划线指示、简洁。不要高饱和整块蓝底、紫粉配色和 Tokyo Night；不要复杂的 IDE 式布局。技术标签（布局名、键名、模式名）保持英文。

## 颜色令牌

| 令牌 | 色值 | 语义 |
|---|---|---|
| bg | `#1e2228` | 默认背景 |
| deep | `#181b20` | 终端、代码阅读面、侧栏 |
| surface | `#272c33` | 卡片、工具栏、浮层内表面 |
| selection | `#323843` | 悬停、选中填充 |
| brightFg | `#d7dae0` | 正文、标题、输入 |
| fg | `#abb2bf` | 次级信息 |
| muted | `#828a95` | 辅助灰字、AI 幽灵文本 |
| border | `#5c6370` | 分隔和描边，不用于需要阅读的文字 |
| blue | `#61afef` | 焦点线、短选中标记、函数 |
| cyan | `#56b6c2` | 类型、信息图标 |
| purple | `#c678dd` | 特殊模式小图标，不作正文或大片背景 |
| green | `#98c379` | 成功、字符串 |
| orange | `#d19a66` | 数字、常量 |
| yellow | `#e5c07b` | 警告 |
| red | `#e06c75` | 错误图标、删除标记 |
| black | `#0e1013` | 阴影、遮罩 |

## 用色规则

- 正文统一 brightFg，次级用 fg。选中态是 selection 底加 blue 短标记，不铺整块蓝。
- 红、紫只做标记，错误句子正文仍用 brightFg。状态要配文字或符号，不只靠颜色。
- 对比度门槛：正文 ≥7，次级 ≥4.5。muted 在 surface 和 selection 上不达标（4.03、3.38），border 不能作文字。`palette-contrast` 检查负责校验。
- 浮层、认证输入、候选框和通知保持高不透明度：Noctalia 通知 0.97、OSD 0.95（不是 1.0），也不加模糊。

## 字体

| 用途 | 字体 |
|---|---|
| 桌面、控件 | Inter，中文回退 Noto Sans CJK SC |
| 代码、终端、读数 | Maple Mono NF CN（Kitty 11 pt） |
| 阅读衬线 | LXGW WenKai Screen |

图标 WhiteSur-dark（蓝色文件夹），光标 Bibata-Modern-Ice 24。正文 14/400，标签 14/500，标题 16/600、20/600；GTK/Qt 10.5 pt 对应 14 逻辑 px。

## 现行尺寸（逻辑 px）

| 项目 | 值 | 位置 |
|---|---|---|
| Mango 边框 / 圆角 | 2 / 16。未聚焦描边用 border，聚焦用 blue。单个平铺窗口和浮动窗口同样保留；只有 monocle 这个整屏堆叠布局去掉边框、圆角和间距 | `mango.nix` |
| 间距 内 / 外 | 10 / 16。单个平铺窗口同样保留（`smart_gaps = 0`），只有 monocle 去掉间距 | `mango.nix` |
| 动画 开 / 关 / 移动 / tag / 焦点 | 220 / 180 / 180 / 280 / 120 ms。开合都是 zoom，起止比例 0.92。开窗透明度从 0 到 1，关窗从 1 到 0。工作区切换是横向滑入。焦点时长只插值边框和 dim | `mango.nix` |
| 非焦点 | 不透明，dim 为 black 的 0x18。浮动窗阴影 size 18、blur 32、下移 10 | `mango.nix` |
| 顶栏 | Noctalia 高 30、完全透明（无背景、不模糊）、贴顶，两个会话共用。左侧工作区编号（当前 blue、占用 brightFg、空 fg，靠颜色层级区分、无下划线）、最小化计数（`hideclients` 插件，eye-off + 数量，muted，0 时隐藏；Mango/Umbriel 各自取数）与窗口标题；右侧托盘、网络、电池、CPU/MEM、通知、控制中心与 `%m月%d日 %H:%M` 时钟 | `noctalia-shell/noctalia.nix` |
| 搜索 | Noctalia launcher 面板居中，不画应用图标；`Alt+Space` | `noctalia-shell/noctalia.nix` |
| 通知 | Noctalia 通知卡片：右上、`background_opacity` 0.97、1 px 边框、无模糊；可见条数由屏幕空间决定（未设 `max_visible`） | `noctalia-shell/noctalia.nix` |
| OSD | Noctalia 音量/亮度/麦克风胶囊：底部居中（`bottom_center`，`offset_y` 48），避开右上通知；锁定键提示由合成器 IPC 转发 | `noctalia-shell/noctalia.nix` |
| 壁纸 | Noctalia 绘制当前壁纸，背景色 bg；默认图由 appearance 提供。壁纸面板浏览 `~/Pictures/Wallpapers`：`managed/` 为 18 张内置图，`local/` 归用户 | `noctalia-shell/noctalia.nix` |
| 锁屏 | Noctalia 锁屏覆盖层，认证走登录 PAM 栈 | `noctalia-shell/services.nix` |

## 模糊

Mango 的 layer 规则默认 `no_blur:1`，Noctalia 顶栏完全透明；Umbriel 只对 Noctalia 的 bar/面板/通知/OSD 层开放 blur。Noctalia 面板为 solid，不依赖合成器 blur。

通知与 OSD 在 Mango 下保持 `no_blur:1`：半透明卡片再模糊会让底色发灰（2026-10-31 实机确认）。壁纸由 Noctalia 绘制，不参与 Mango 的 layer 模糊。

## 实现边界

配置接口按锁定的 Mango 源码核实，不虚构字段。Mango 没有的能力才打局部补丁（`mango/*.patch`），每个补丁必须有构建期检查，上游升级时失败而不是静默退化。锁屏、壁纸渲染和 GTK/Qt 主题现在都由独立组件或 HM 静态文件提供，不依赖桌面 shell 生成。旧版完整规范（含 TUI 外观细节、Firefox、Thunar、Fcitx 的设计依据）归档在 [history/README.md](history/README.md)（原文 `visual-design-2026-10-30.md`），其中数值可能已过时。
