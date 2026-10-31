---
summary: One Dark 配色令牌、用色规则、字体和桌面现行尺寸
read_when: 调整任何界面的颜色、字体、圆角、间距、透明度或动效
code: [aspects/appearance/appearance/onedark.nix, aspects/desktop/mango-session/mango.nix, aspects/desktop/mango-session/noctalia.nix, aspects/desktop/mango-session/noctalia/bar.nix]
checks: [palette-contrast, gtk-qt-theme, noctalia-osd-pixels, noctalia-template-runtime]
---

# 视觉规范

**颜色的唯一来源是 `onedark.nix`。** 数值以源码为准，本文记录语义和 2026-10-31 从源码核对的现值。
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
- 浮层、认证输入、候选框和通知不透明。

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
| Mango 边框 / 圆角 | 1 / 16 | `mango.nix` |
| 间距 内 / 外 | 8 / 12 | `mango.nix` |
| 动画 开 / 关 / 移动 / tag / 焦点 | 190 / 150 / 200 / 190 / 0 ms，开窗比例 0.985 | `mango.nix` |
| 非焦点 | 不透明，轻 dim | `mango.nix` |
| 顶栏 | 高 30，不透明度 0.62，贴顶 | `noctalia/bar.nix` |
| Dock | 底部 Smart，不透明度 0.80 | `noctalia/bar.nix` |
| 启动器 | 宽 520 | `noctalia.nix` |
| 控制中心 | 宽 360 | `noctalia.nix` |
| 通知 | 宽 360，右上偏移 28/24，最多 3 条，不透明，1 px 边框，无模糊 | `noctalia.nix`、`mango.nix` |
| OSD | 底部居中，底距 96 | `noctalia.nix` |

## 模糊

只有顶栏、Dock、系统菜单、Launchpad、面板和 OSD 这些指定 layer 开模糊（`mango.nix` 的 `layer_rule`）。普通窗口除 Kitty 等明确例外外不模糊。

通知层必须 `no_blur:1`：卡片半透明加模糊时，背后内容会让底色发灰、出现斑块（2026-10-31 实机确认）。

## 实现边界

配置接口按锁定的 Noctalia、Mango 源码核实，不虚构字段。Noctalia 没有的能力才打局部补丁（`noctalia/*.patch`），每个补丁必须有构建期检查，上游升级时失败而不是静默退化。旧版完整规范（含 TUI 外观细节、Firefox、Thunar、Fcitx 的设计依据）归档在 [history/visual-design-2026-10-30.md](history/visual-design-2026-10-30.md)，其中数值可能已过时。
