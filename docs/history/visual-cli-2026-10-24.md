# 第十四轮：终端与命令行视觉

工作目录 `/home/mayon/nix-dotfiles-v-cli`，2026-10-24。仅修改 CLI 功能、相关检查及终端操作文档；
没有修改 Neovim、其他 worktree、共享 palette 或桌面 renderer，没有应用系统配置。

## 设计与实现边界

唯一视觉依据为用户确认的 Astra `design-spec.md`（2026-10-24），已对照 `mockup.png`、
`panels-full.png` 与离线 HTML 的终端示意。以下属于 §2 的共享颜色与 §8 的原生配置/格式接口：

- Kitty：deep/brightFg 不透明阅读面，padding 12；原生 separator 标签栏，选中 selection/blue，
  普通 deep/fg；光标 brightFg、拖尾 blue、选区 selection/brightFg，reducedMotion 关闭拖尾与闪烁。
- tmux：deep 底与 selection 圆端字符胶囊；当前窗口 blue，后台 fg，前缀 cyan、复制 yellow、
  放大 blue，最多两个模式提示。100 列以下隐藏日期时间、80 列以下隐藏路径；日期中文月日。
  `set -g @rounded-caps off` 回退方括号。保留前缀、tmuxp、resurrect/continuum 及不保存滚屏的策略。
  移除 prefix-highlight 插件，由格式表达式直接渲染四态，无主题插件。
- Starship：两行目录/分支/变更短数字/耗时/环境信息与 `❯`，失败红色符号和退出码；SSH/root 身份条件显示。
- bat/delta：共享构建期主题缓存，deep 阅读面；diff 底色使用 green/red/blue 叠 deep 8%，
  字内变化 12%，diff 正文 brightFg（§2、§9 diff 规则）。不创建登录时缓存 writer。
- eza、glow、btop、lazygit、Yazi、Atuin、fzf、fastfetch 均从共享 palette 渲染；必要说明采用 fg，
  选中底色优先 selection，不用大块高饱和蓝色。名称 `onedark-darker` 本轮保留。

smart-splits 的八个根键表绑定来自只读的 Neovim 分支交接记录 §“给主代理的 tmux 片段”。
Ctrl+h/j/k/l 由 `@pane-is-vim` 决定转发或 pane 移动，Alt+h/j/k/l 转发或调整 3 cell；
复制模式保留原生 vi 光标/选区语义。原有 Ctrl+a 前缀导航、可重复大写 resize、tmuxp 入口保留。
不探测进程名，不强制重载或关闭已有 session。

未采用终端透明、Mango 客户端模糊、Kitty 自绘圆角标签：§1/3/8 明确以正文可读性和原生
separator 为准，因此无需新增 Mango 规则。圆端是字体字形，不声称为窗口圆角。
Atuin 的原生选中背景与 TUI 固定布局受程序接口约束，不能把 HTML 的 CSS 当成可用配置。
btop 在 Mango 中既有 Noctalia 主题接线仍有效：本分支只调整独立 CLI 回退主题，不改变其 writer 边界。

## 分工与复核

三名 `luna-worker` 并行：tmux.nix；zsh.nix（Starship/fzf/Atuin）；其他 CLI 主题。
主代理负责 Kitty、palette 接线、README、操作文档、相关测试及集成。
独立 reviewer 复核与最终命令结果在完成后补记。

## 对比度

按 WCAG sRGB 线性化与相对亮度计算；以下为实色平面值，不含字形抗锯齿。正文门槛 7:1，短标签/次级信息门槛 4.5:1。

| 前景 | deep | surface | selection |
|---|---:|---:|---:|
| brightFg | 12.33 | 10.03 | 8.41 |
| fg | 8.10 | 6.59 | 5.53 |
| blue | 7.31 | 5.95 | 4.99 |
| cyan | 7.29 | 5.93 | 4.97 |
| yellow | 9.99 | 8.14 | 6.82 |
| green | 8.56 | 6.97 | 5.84 |
| orange | 7.01 | 5.70 | 4.78 |
| purple | 5.86 | 4.77 | 4.00 |
| red | 5.40 | 4.40 | 3.69 |
| muted | 4.63 | 3.77 | 3.16 |
| border | 2.86 | 2.32 | 1.95 |

muted/border 仅装饰；red/purple 在 deep 上低于正文门槛 7，不能用于代码正文；关键字改 cyan、标签改 brightFg。red 在 surface/selection、purple 在 selection 上亦低于次级信息门槛 4.5。

| diff 背景（派生） | 8% / brightFg | 12% / brightFg |
|---|---:|---:|
| green | #222827 / 10.70 | #272f2b / 9.81 |
| red | #282127 / 11.21 | #30252a / 10.53 |
| blue | #1e2731 / 10.79 | #212d39 / 10.00 |

## 集成修正与证据边界

独立 reviewer 检出并已修正方括号低对比、长路径挤占右栏、bat/glow 红紫代码正文、
delta 样本未覆盖新增样式。路径限 24 字符、右栏限 64；回退括号 fg/deep 为 8.10:1。
Yazi copied/cut/marked 保留 green/yellow/cyan 小标记，均用 selection 中性底。

真实 PTY 检查进一步检出 tmux 条件分支中的样式逗号会截断提示，已拆成独立 style tags；
路径多修饰符采用原生分号分隔。圆端开关需精确比较 `on`，字符串 `off` 在普通条件中仍为真。
Starship 隔离检查补齐 Git PATH 与 PWD，并按原生 snowflake/impure 文案验收 nix_shell，
不把测试环境缺命令或测试预期文本错误算成产品故障。

`resources/visual-check.py` 用真实 tmux PTY 与独立 socket 检查根键表导航、Vim 标记分支、
Alt 调整大小和模式提示；这不证明另一分支 Neovim 实际收到键，也不证明退出/恢复标记清理。
TUI 原生加载检查只复制公开配置到构建 HOME。btop 的可写副本单独切换到自有
`One Dark Darker`，因此验收的是 CLI 回退主题，Mango 的 Noctalia 主题仍需现场检查。
原生 parser/PTY、构建与最终待验项在下面分别记录。

LazyGit 0.61.1 普通 diff 经原生 `git.pagers` 调用同一个 Delta wrapper 和 Git 样式，
避免 gui.theme 之外仍使用原生红绿全文。逐行 staging/custom patch 会绕过 pager，
其上游渲染把增加/删除正文直接设为 ANSI green/red，本轮不补丁上游；因此不宣称
逐行暂存界面也达到中性正文/8% 底色目标。精确版本依据为
[pager_config.go](https://raw.githubusercontent.com/jesseduffield/lazygit/v0.61.1/pkg/config/pager_config.go)、
[staging_helper.go](https://raw.githubusercontent.com/jesseduffield/lazygit/v0.61.1/pkg/gui/controllers/helpers/staging_helper.go)
与 [patch/format.go](https://raw.githubusercontent.com/jesseduffield/lazygit/v0.61.1/pkg/commands/patch/format.go)。

## 改动文件

| 区域 | 文件 |
|---|---|
| Kitty | `aspects/cli/terminal/{kitty.nix,README.md}` |
| shell / tmux / Git | `aspects/cli/shell/{default.nix,tmux.nix,zsh.nix,git.nix,README.md}` |
| CLI 主题 | `aspects/cli/shell/{color-mix.nix,onedark-darker-bat.nix,onedark-darker-btop.nix,tools.nix,sysinfo.nix,yazi.nix}` |
| 验证 | `aspects/cli/shell/runtime-check.nix`、`aspects/cli/shell/resources/visual-check.py`、`tests/composition/{protocols.nix,desktop.nix}` |
| 文档 | `docs/workflow-design.md` 的终端/tmux 段、本记录 |

共 19 个文件。`color-mix.nix`、`visual-check.py` 与本记录为未跟踪新文件，按分支约束不 stage/commit。
没有修改 `docs/README.md`、`aspects/dev/neovim/**` 或其他 worktree。

## 最终验证

新文件存在，验证采用 `path:.`。执行前检查未跟踪/忽略项；临时 fixture 仅在本 worktree 的
`.work/cli-native-*`，验证结束清除，最终源码范围不含该目录、result 或运行时秘密。
TUI fixture 禁用显示服务器和会话总线；配置、数据库及历史均在隔离 HOME。没有应用配置。

| 命令或检查 | 实际结果 |
|---|---|
| `git diff --check` | 通过 |
| `nix fmt --no-write-lock-file -- aspects/cli tests/composition/protocols.nix tests/composition/desktop.nix` | 通过；格式化限制在本分支可写范围 |
| `nix flake check --no-build --no-write-lock-file path:.` | 通过，包含求值期 architecture；只有既有 `unknown flake output 'denful'` 提示 |
| `nix build --no-link --no-write-lock-file --print-out-paths --keep-going`，逐一指定全部 21 个 `path:.#checks.x86_64-linux.<name>` 与 toplevel | 已实际运行；19 checks 与 toplevel 成功，以下 2 checks 失败 |
| 同一 build 命令明确指定其余 19 checks 与 toplevel | 退出 0，输出 20 个 store 路径 |
| CLI runtime 原生验证 | 构建成功；Kitty `load_config`、bat/delta/eza/glow/fastfetch/fzf、Zsh 按键、Atuin/Yazi TOML、btop/Yazi/LazyGit/Atuin PTY 启动退出通过 |
| tmux / Starship fixture | 前缀/复制/放大、圆端回退、根键表转发/调整大小、79/80/99/100/120 列右栏条件、路径截断；Starship `?1`、退出码 42、耗时、SSH、Nix shell 均通过 |
| 旧颜色扫描 | `aspects/cli/**` 无用户列出的 13 个旧色值 |
| WCAG / 文档 | 本记录上表为实际 sRGB 计算；本轮文档本地链接和可写路径范围已核对 |

完整构建的失败点：

- `interactive-session-config`：未改的 `aspects/desktop/mango-session/runtime-check.nix:245`
  仍断言 palette bg 为旧色 `#1f2329`；同文件第 343 行也有同类断言，首处失败后未执行到。
  桌面分支应随其 renderer 一起更新。这不是本轮 CLI parser 失败。
- `neovim`：未改的 `aspects/dev/neovim/config/tests/startup.lua:5` 断言 Normal.bg 为
  `0x1f2329`。用户明确禁止本分支修改 Neovim，由 Neovim 分支更新；本分支不宣称该 check 通过。

成功的 19 checks：architecture、command-line-runtime、deadnix、desktop-composition、
editing-composition、embedded-composition、embedded-home、embedded-tools、embedded-udev、
local-services-composition、project-workbench、protocols-composition、remote-workspace-composition、
rime-technical-runtime、statix、system-boundaries、treefmt、workspace-composition、xorg-session-runtime。

本分支系统 toplevel：

```text
/nix/store/gwp3fsbi8xlw5li0r3mil0gz8b7yf6fn-nixos-system-nixos-btw-26.05.20261021.da6dc0e
```

独立 reviewer 最后复核无新增阻断项。没有重复执行重型构建；审查了全部 diff 与新文件、
锁定 LazyGit pager/staging 接口、tmux 手册语义、归属/nullable 组合和验证边界。

## 待实机验收

- 新 generation 中 Kitty 在 150% 缩放下的 Maple 字体、12 padding、标签、beam、拖尾与选区；
  reducedMotion 的真实动画关闭。未启动真实 Kitty 窗口验证画面。
- Neovim 与 tmux 的真实双向跨边缘导航/resize，Neovim 退出/恢复后 pane 标记清理，tmuxp 项目工作台。
  PTY 只用标记 fixture，不等同于另一分支 smart-splits 的端到端验收。
- Maple 圆端字形接缝、中文长窗口名与多窗口窄屏。自动检查证明右栏条件/截断，未证明整个窗口列表的视觉排版。
- Starship 本地 root 身份实际显示、SSH 长主机名及各项目语言环境；root predicate 已声明但没有提权进行 root 实测。
- LazyGit 普通 diff 的真实阅读及逐行暂存的原生差距；Yazi 标记类别；Atuin 的原生前景主题与终端底色。
- Mango 场景下 btop 的 Noctalia 主题由桌面分支验收，不把本轮 CLI 回退主题启动检查算作 Noctalia apply/undo 验证。
