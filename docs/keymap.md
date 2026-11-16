---
summary: Mango、tmux、Neovim 与项目入口的按键和操作分层
read_when: 查某个快捷键、加改绑定、排查按键冲突
code: [aspects/desktop/mango-session/mango/keybinds.nix, aspects/cli/shell/tmux.nix, aspects/dev/neovim/config/lua/mayon/config/keymaps.lua]
checks: [keys-mayon-bindings, desktop-composition]
---

# 按键与操作

**权威来源是源码**：Mango 按键在 `mango/keybinds.nix`，运行时用 `Super+F1` 或 `mayon-tools keys` 查看由它生成的完整列表。下表是分组速览，与源码矛盾时以源码为准并修正本文。

## 自写工具入口

| 工具 | 按键 |
|---|---|
| Clash | `Super+Shift+C` |
| 工具箱（Docker/Ports/Serial/Keys/Voice） | `Super+Shift+D` |
| Bilibili | `Super+Shift+B` |
| 语音录音 | 专用键 `Super+Shift+XF86Assistant`，松开触发（`bindr`），500 ms 防抖 |

详见 [tools.md](tools.md)。

## 操作层次

| 范围 | 入口 | 规则 |
|---|---|---|
| 桌面窗口与工作区 | `Super` | Mango 拥有，不占用编辑器常用的 Ctrl/Alt 字母 |
| 桌面搜索 | `Alt+Space` | `fuzzel --no-icons`，唯一的启动器。锁定 Mango 的热区默认关闭，打开后是概览 |
| 终端复用 | `Ctrl+a` 前缀，方向键跨层集成 | tmux 管 pane/window/session；`Ctrl+h/j/k/l` 移动、`Alt+h/j/k/l` 调整大小 |
| 编辑器窗口与功能 | `Ctrl+h/j/k/l`、Space leader | smart-splits 用 pane-local `@pane-is-vim` 与 tmux 协作，编辑器边缘可移到相邻 pane |
| shell 与 TUI | 原应用按键 | `Alt+b/f`、`Ctrl+r`、Esc 等正常到达应用 |

tmux 保留前缀窗口管理；无前缀 `Ctrl+h/j/k/l` 根据 smart-splits 维护的 pane-local
`@pane-is-vim` 转给 Neovim 或移动 tmux pane，`Alt+h/j/k/l` 同理调整大小（tmux 每次 3 cell）。
其他无前缀 Alt 字母/数字绑定仍清理；`Alt+b/f`、`Alt+C` 保持应用行为。复制模式保留 tmux 原生 vi 光标与选区键；上述跨层方向绑定属于 root 键表。`Ctrl+a Ctrl+a` 仍发送字面 Ctrl+a 给 shell。

## 桌面主要操作

| 操作 | 按键 | 声明行为 |
|---|---|---|
| 终端 / 文件 / 浏览器 | `Super+Enter` / `Super+E` / `Super+B` | 调用统一默认工具，禁止各入口独立硬编码应用 |
| 临时终端 | `Super+Shift+Enter` | Kitty 命名 scratchpad，首次启动，再次显示/隐藏 |
| 临时文件 / 系统监视 | `Super+Shift+E` / `Ctrl+Shift+Esc` | 分别呼出独立 Kitty class 的 Yazi / btop；普通 Kitty 不受匹配 |
| 特殊工具工作区 | `Super+Shift+S` | 显示/隐藏 Tag 0，默认 scroller |
| 停放 / 取回特殊窗口 | `Super+Ctrl+S` | 将当前窗口放入 Tag 0；在 Tag 0 使用时送回先前普通 tag，不主动跟随 |
| 跨工作区可见 / 置顶 | `Super+Ctrl+G` / `Super+Alt+G` | 两个独立手动状态；前者限窗口所在输出，后者可能覆盖全屏窗口 |
| 剪贴板 | `Super+V` | cliphist-tui 在 Kitty 浮窗里列出 cliphist。图片在下方预览区按原图显示。回车写回 Wayland，再按打开前的焦点应用粘贴（终端 `Ctrl+Shift+V`，其他 `Ctrl+V`）。终端里的图片只写回剪贴板。`Ctrl-X` 删除一条，`Alt+X` 清空整个历史库 |
| 音量 / 亮度 / 麦克风 | 音量键、亮度键、麦克风静音键 | `swayosd-client`（含 `--input-volume mute-toggle`）。媒体键仍是 playerctl |
| 锁屏 | `Super+Alt+L` | 独立 swaylock；没有 DND、防空闲开关或会话菜单。swayidle 没有空闲计时器，只在 logind 睡眠前锁屏 |
| 窗口聚焦 | `Super+j/k/l` 或方向键 | 向左只用方向键。`Super+H` 用来找回最小化窗口 |
| 移动窗口 | `Super+Shift+j/k/l` 或方向键 | 向左只用方向键。`Super+Shift+H` 用来最小化 |
| 移到相邻显示器 | `Super+Ctrl+方向键` | 保留，不为当前锁定版本捏造 HJKL 方向语义 |
| 去工作区 | `Super+1…9` | 编号稳定，不随应用关闭重排 |
| 移窗口并跟随 | `Super+Shift+1…9` | 保留 Mango `tag` 的实际语义 |
| 停放窗口、不跟随 | `Super+Ctrl+1…9` | 保留 `tagsilent`，帮助中说清差异 |
| 最近窗口 / 概览 | `Super+Tab` / `Super+0` | 保留 |
| 带标题预览 / 原生切换器 | `Super+Alt+J/K` / `Super+Shift+T`、`Alt+Tab` | `Super+Alt+J/K` 是当前 tag 的 overcircle 前后；switcher 是缩略图面板，`Alt+Tab`/`Alt+Shift+Tab` 在当前 tag 内正向/反向循环，松开修饰键选中，`Super+Shift+T` 只进下一张 |
| 跳转标签 | `Super+Shift+0` | 保留 togglejump，按 US 布局 HJKL 优先的字母标签选择窗口 |
| 调整大小 | `Super+R`，随后 HJKL/方向键 | 保留模式；模式内 Esc 退出，所有模式下 `Super+Esc` 可退出 |
| 最大化 / 真全屏 | `Super+F` / `Super+Shift+F` | 保留二者差异 |
| 浮动 / 布局 / 主窗口 | `Super+Space` / `Super+=` / `Super+Z` | 布局仍为 tile/scroller/monocle。`Super+=` 循环这三种。主区域比例用 `Super+Minus` 减小、`Super+Ctrl+=` 增大。`Super+Shift+W` 不绑定 |
| 壁纸 | `Super+W` | `wallpaper-pick`：Matuwall 网格列出 `~/Pictures/Wallpapers/managed` 与 `local/`，选中后经 `wallpaper-apply` 写状态并 IPC 切到 sweetbg。取消不改当前图 |
| 关闭窗口 / 重载配置 | `Super+Q` / `Super+Alt+R` | 所有 Mango 模式可达；不全局拦截裸 Esc |
| 最小化 / 找回 | `Super+Shift+H` / `Super+H` | 最小化同时进入 scratchpad；`Super+H` 取回。与命名临时终端不同 |
| 操作帮助 | `Super+F1` | 显示同一份按键数据生成的分组帮助；新增工具键同步出现在帮助中 |

所有 tag 默认使用 tile 布局，主区域比例 60%（`tag_rule = id:*,layout_name:tile`、
`default_master_factor = 0.60`）；没有按用途或 app-id 预设的逐 tag 布局。`Super+=`
循环当前 tag 的 tile/scroller/monocle，各 tag 的布局状态相互独立；任意应用仍能放在
任意 tag。Tag 0 也按同一默认启动，用作临时工具的独立层次。
显示器使用各自真实输出事实，没有硬编码外屏分配或 niri 式自动恢复承诺。

named scratchpad 只有一个可见，呼出另一工具会隐藏前一个；跨屏呼出会使用当前输出。
这些操作只控制窗口显示，不终止其中的 shell、文件操作、监视器或后台任务。
普通最小化池、named scratchpad 与 Tag 0 是三个入口，不互相代替。

Firefox 的英文标题 `Picture-in-Picture` 精确匹配浮动、跨 tag、安静打开，默认 480×270，
靠右下方放置；不默认 overlay，避免主动压住全屏内容。需要置顶时手动 `Super+Alt+G`。
截图、portal 文件选择及 Swayimg 使用相对输出尺寸；Thunar 重命名保留应用尺寸提示。
父窗口关联、模态与 IDE 弹窗沿用 Mango/应用逻辑；未用宽泛规则让整个 IDE 浮动或禁止聚焦。
精确到父窗口中心、跨屏 DPI 无缝恢复和所有应用的焦点策略不是当前实现承诺。

现有进阶操作（master 数量/比例、scroller 比例、隐藏边距、特定显示器开关等）继续保留，归入帮助的进阶分组；只对重复或冲突的入口去重，禁止因未列入主表就静默删除。完整来源是 [Mango 配置](../aspects/desktop/mango-session/mango.nix)。

## 截图、文件和剪贴板

| 操作 | 入口 | 保留的行为 |
|---|---|---|
| 区域/窗口截图与标注 | `Print` | mark-shot，窗口矩形来自 `mmsg` |
| 当前屏幕到剪贴板 | `Ctrl+Print` | 按指针所在输出选择，不能固定 eDP-1 |
| 滚动截图 | `Shift+Print` | `mark-shot --scroll` |
| 区域 / 全桌面 OCR | `Super+Print` / `Super+Shift+Print` | 英文+简体中文；取消选区安静退出，失败有提示 |
| 截图文件位置 | 应用保存动作 | 显示真实目标路径；用户已选路径不被激活脚本重置 |
| 打开 / 看图 | MIME 默认 | Thunar；图片 Swayimg；PDF Zathura 默认、批注用 Zotero 内置阅读器；文本图形默认 VS Code，CLI 默认 Neovim |

保留 Thunar 的“在此打开终端”“复制为图片”“复制路径”“粘贴剪贴板图片”“粘贴为链接”。文件 URI、路径文字、图片像素是三种不同用途，不能为了减少代码把它们合并成一种复制。迁移终端入口时保持当前文件夹作为 cwd，路径包含空格/中文/引号仍正常，不经拼接 shell 字符串。当前实现见 [文件动作](../aspects/apps/file-manager/thunar-actions.nix)、[终端入口](../aspects/apps/file-manager/thunar-terminal.nix)、[截图](../aspects/desktop/mango-session/screenshot.nix)。

剪贴板历史由 cliphist 保存。`Super+V` 打开 cliphist-tui（Kitty 图形协议预览图片），回车后写回 Wayland 剪贴板，并按打开窗口前的焦点 `appid` 用 `paste-key` 粘贴。`paste-key` 先上传一份普通 evdev keymap（wlroots 在这之前拒绝修饰键），再发送 evdev `KEY_V`（47），加上 Ctrl，终端再加 Shift。不用 `wtype`：它的 `-k` 把该键编成 keycode 1，在这套 Mango 上是 Escape，`Ctrl+Shift+Escape` 会打开 btop scratchpad。预览缓存在 `~/.cache/cliphist-tui`，可以删除，不是历史库。选中一条不会从历史里删掉；`Ctrl-X` 删一条，`Alt+X` 清空整个库。Wayland/X11 桥接不是第二个历史库，其退出与轮询策略按 [服务设计](service-policy.md) 核验。保留 WeChat/XWayland 与原生 Wayland 间文字、图片互通。旧 cliphist 数据库不删除、不改路径。锁屏和秘密复制行为先按锁定实现验证，不声称所有密码管理器内容都会自动排除；不输出剪贴板内容到测试日志。虚拟键盘粘贴依赖 compositor 的 virtual-keyboard 协议，失败时内容仍留在剪贴板。

## 终端、项目与远程工作

Kitty 新窗口默认进入普通 shell，不自动套 tmux。用户需要保持项目工作现场时显式运行 tmux；每个常用项目一个 session，window 表示编辑/构建/运行，pane 只用于同时观察。避免同时用 Kitty tab 和 tmux window 管同一项目。

| tmux 操作 | 入口（先按 Ctrl+a） |
|---|---|
| 左右 / 上下分屏 | `\|` / `-`，继承当前 pane cwd |
| pane 聚焦 | `h/j/k/l`；另可无前缀 `Ctrl+h/j/k/l` 跨 Neovim/tmux |
| pane 调整大小 | `H/J/K/L`（可重复，5 cell）；另可无前缀 `Alt+h/j/k/l`（3 cell） |
| 放大 pane | `z`，沿用默认 |
| window 新建 / 前后 / 最近 / 按编号 | `c` / `n,p` / `Tab` / `1…9`；显式把最近窗口绑定为 `Tab`，让 `l` 专用于 pane 向右 |
| 复制模式 / 选区 / 复制 | `[` 后 `v`、`y`，沿用 vi 模式 |
| session/window/pane 搜索 | `F`，保留现有 tmux-fzf |
| 离开但不结束 | `d` |
| 重载 | `r` |

终端视觉采用 Astra 设计稿 §8：Kitty 使用不透明 deep 阅读面、brightFg 正文、12 padding，
两个及以上标签才显示 separator 标签栏；当前标签 selection/blue，普通标签 deep/fg。
无需 Mango 客户端透明/模糊规则。tmux 底部使用字体圆端胶囊，正常/前缀/复制/放大均保留中性底；
窄于 100 列隐藏时间，窄于 80 列隐藏路径。圆端缺字时可设 tmux `@rounded-caps off` 回退方括号。
Starship 为两行：目录、分支、变更计数、耗时与环境信息在首行，第二行 `❯`；失败显示退出码，
用户/主机只在 SSH 或 root 会话出现。没有强制重载已有 Kitty/tmux/shell 实例。

tmux 会话恢复继续保留布局与编辑会话，禁止保存 pane 滚屏文本。恢复不等于重启数据库、容器、SSH 或付费 AI 任务；不能把“恢复窗口”实现成无条件重放历史命令。见 [现有恢复设置](../aspects/cli/shell/tmux.nix)。

Zsh 的 `Ctrl+R` 由 Atuin 搜索本地命令历史，使用 compact 视图、全局默认筛选，并保留上箭头的原生 shell 搜索行为；候选需要再次按 Enter 才会执行。Atuin 同步与更新检查关闭。fzf 保留 `Ctrl+T` 文件选择和 `Alt+C` 目录选择。Atuin 数据库属于运行态用户数据，首次配置完成后如需导入旧历史，由用户在应用后显式执行；配置构建与隔离按键检查不会导入或读取真实历史。

项目的依赖、编译器和 SDK 版本由项目 `flake.nix`/`flake.lock` 拥有；全局只提供确认保留的基础工具和交互工具。direnv/nix-direnv 负责目录环境缓存：新的或变化的 `.envrc` 需用户信任，首次缺依赖时下载是正常行为，不承诺进入项目零等待。编辑器、语言服务器必须从项目 cwd/环境启动；桌面打开目录不能假装自动获得其 devShell。全局 clangd 用 PATH，项目可覆盖，已有语言接口不把所有工具写死成 store 路径。

远程默认在服务器内用 tmux 持续工作，笔记本只作 SSH 客户端。SSH 不嵌套自动启动 tmux；有意嵌套时文档说明如何发送前缀。服务器远程 workspace 不附带 GUI、Kitty 或本地剪贴板 daemon，参考 [服务器规划](server-plan.md)。

## 项目与长任务入口

启动器搜索“Nix 配置工作台”可打开真实项目目录中的终端；项目目录
不存在时报错，不创建或退回其他位置。命令行支持 `workspace-project list`、
`workspace-project dotfiles editor`、`workspace-project dotfiles files`。editor 使用 CLI
默认编辑器，首次进入目录视图；`--` 后的文件参数按 argv 传递。有 `.envrc` 时用
`direnv exec`，不自动 allow、不绕过信任失败，不自动运行构建或恢复历史命令。

启动器“长任务终端”及 `workspace-task -- 命令 参数` 仅在命令运行期间持有 sleep inhibitor，
结束后自动释放。它不阻止手动锁屏，不是后台常驻模式，也不能保证抵抗断电或强制
睡眠。没有独立的防空闲开关；长任务用自己的 inhibitor，不能当成对手动休眠或盖盖子行为
的全面保护。两个入口不自动套在已有任务上。

通知由 mako 直接显示，没有勿扰/历史面板；Kitty 有前台任务时关闭窗口会请求确认；
tmux/编辑器不会被强制重载。

## Neovim 键位

Leader 为 Space（下表 `␣`），localleader 为逗号。which-key 分组为中文与统一 Nerd Font 图标。
未列出的 Vim 原生移动、窗口、编辑和折叠键继续可用；`s` 为明确自定义入口。

| 键位 | 行为 |
|---|---|
| `␣␣` / `␣/` / `␣,` | 智能找文件 / 全文搜索 / 切换缓冲区 |
| `␣e` / `-` / `␣.` | 文件树 / Oil 父目录 / 草稿 |
| `␣w` / `␣qq` | 保存 / 智能关闭窗口或缓冲（保留未保存确认） |
| `Ctrl+S`（普通 / 插入 / 可视） | 保存；覆盖插入模式原生的签名帮助，签名帮助用 `gK` |
| `␣fr` / `fn` / `fy` | 最近文件 / 新建 / Yazi |
| `␣fR` / `fD` / `fc` / `fp` | 安全重命名文件 / 确认移入回收站 / 配置 / 项目 |
| `␣su` / `␣qr` / `␣xw` / `␣uL` | 原生撤销树 / 保留 UI 重启 / 收集工作区诊断 / 按需显示 CodeLens |
| `␣sw` / `ss` / `sS` | 光标词 / 文档符号 / 工作区符号 |
| `␣sh` / `sk` / `sr` | 帮助 / 键位 / grug-far 替换 |
| `␣sd` / `sc` / `s.` | 诊断 picker / 命令历史 / 恢复 picker |
| `␣ca` / `cr` / `cf` | 代码动作 / 符号重命名 / 格式化 |
| `␣co` / `ci` / `cO` / `cl` | 大纲 / 调用者 / 被调用项 / lint |
| `␣c[` / `c]` | 与上一个 / 下一个参数交换 |
| `␣gg` / `gd` / `gf` / `gb` | LazyGit / CodeDiff 工作区审阅 / 当前文件历史 / 当前行 blame |
| `␣gD` / `gC` / `gT` | 输入提交或分支比较 / 当前文件冲突逐块解决 / 原生双目录 DiffTool |
| `␣gs` / `gr` / `gp` | hunk 暂存（可视模式为选区）/ 还原 / 内联预览 |
| `␣gS` / `gR` / `gq` / `gB` | 暂存整个文件 / 还原整个文件 / hunk quickfix / 远程浏览 |
| `␣ad` / `ai` | DeepSeek 对话 / 内联改写（普通或可视） |
| `␣ae` / `at`（可视）/ `am` | 解释诊断 / 为选区写测试 / 起草提交信息 |
| `␣ap` / `ah` | 中文 prompt library / 对话历史 |
| `␣au` 或 `␣ua` | copilot → deepseek → off 补全切换 |
| 内联改写 buffer `,a` / `,r` | mini.diff 接受保留未保存内容 / 拒绝还原 |
| `␣xx` / `xX` / `xq` / `xl` / `xt` | Trouble 工作区诊断 / 当前文件 / quickfix / loclist / TODO |
| `␣uw` / `us` / `uh` / `uz` | 折行 / 拼写 / inlay hints / zen |
| `␣uf` / `ud` / `un` | 保存格式化 / 诊断显示 / 相对行号 |
| `␣tt` / `tv` / `th` | 浮动 / 右分 / 下分终端 |
| `␣ps` / `pl` / `pp` / `pd` | 恢复当前会话 / 上次会话 / 切换项目 / 不保存当前会话 |
| `Ctrl+h/j/k/l`；`Alt+h/j/k/l` | smart-splits 移动至 nvim/tmux 面板；调整大小 |
| `s`；可视 `an/in`、`]n/[n`、`]N/[N` | Flash 跳转；原生 Treesitter 节点选择/导航，无 parser 时 an/in 使用 LSP selectionRange |
| `[d ]d` / `[h ]h` / `[t ]t` / `[q ]q` | 上下诊断 / hunk / TODO / quickfix |
| `[c`；`[m ]m [M ]M`；`[[ ]]` | 上层上下文；函数首尾；类开头 |
| `af/if`、`ac/ic`、`aa/ia`、`al/il`、`ai/ii`（可视/操作符） | 函数、类、参数、循环、条件块文本对象（mini.ai；f/c/l/i 用 Tree-sitter） |
| `aq/iq`、`ab/ib`、`at/it`、`aF/iF`、`ag/ig`；`aN`/`aL` 前缀；`g[` / `g]` | 任意引号、任意括号、标签、函数调用、整个缓冲；下一个 / 上一个对象；跳到对象左右边缘 |
| `Ctrl+a` / `Ctrl+x`（普通/可视，`g` 前缀递增） | 数字、十六进制、日期、`true/false`、semver、`&&/\|\|`、`and/or`、`yes/no`、`on/off`、Markdown 标题级别（dial）；tmux 内按两次 `Ctrl+a` |
| `␣mn/mN` / `ms/mS` / `mj/mk` | 下/上匹配加光标 / 跳过匹配 / 下/上行加光标 |
| `␣ma` / `mt` / `mq` / `mg`；多光标层 `␣mx`、左右箭头、Esc | 所有匹配 / 光标开关 / 清空 / 动作添加；删主光标、切换、退出 |
| `gd` / `gD` / `grt` / `gi` / `K` / `grx` | LSP 定义 / 声明 / 类型 / 实现 / 文档 / codelens |
| `␣lh` / `ll` / `lr` | 源/头文件切换 / 诊断虚拟行 / 重启语言服务 |
| Markdown `,x`（普通可带计数 / 可视） | 切换任务框 `[ ]`↔`[x]`；普通列表项或文本先变成 `- [ ]`；插入 Enter 续写 `- [ ] ` |
| Markdown `,tm` / `,tr`；表格模式内 `\|` | 表格模式开关 / 重新对齐；输入 `\|` 自动对齐（vim-table-mode，前缀 `,t`） |
| Markdown `,p` | 粘贴剪贴板图片到笔记旁 `assets/` 并插入图片标记（img-clip，`:PasteImage`） |
| `gx`（普通/可视） | 打开光标/选区链接；`:Urls` / `:UrlsBuffer` 搜索链接 |
| 插入 `Tab` / `Shift+Tab` | 接受整条 AI 幽灵文本 → 原生片段跳转 → 缩进；反向片段跳转或反缩进 |
| 插入 `Ctrl+y` / `Enter`；`Ctrl+n/p`；`Ctrl+e` | 显式确认所选项（Enter 未选择则换行）；上下选择；关闭菜单 |
| 插入 `Ctrl+Space`；`Ctrl+x Ctrl+f`；C++ `Ctrl+x Ctrl+u` | 原生 LSP 补全；原生路径补全；仓库 C++ 片段源 |
| 插入 `Ctrl+→` 或 `Alt+l`；`Esc` / `Ctrl+]` | 接受 AI 一个词；拒绝幽灵文本（无建议时 Esc 退出插入） |
| 插入 `Alt+]` / `Alt+[` | 轮换 AI 建议 |

原生 LSP 菜单不预选；选中候选时 popup 显示文档，边框跟随 rounded。输入 `(` / `,` 自动签名帮助。
AI 只显示灰色幽灵文本，不进入补全菜单；菜单显示期间隐藏 Copilot/Minuet 幽灵文本。
窗口原生 `Ctrl+w` 与折叠 `zR/zM/zc/zo` 保留。所有破坏性文件操作继续走已有 fileops 保护。
CodeCompanion 的 `ga` 切 adapter；聊天内 `gh` 浏览历史、`,h` 保存当前聊天。
