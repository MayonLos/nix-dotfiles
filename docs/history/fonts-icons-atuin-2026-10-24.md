# 第三轮：字体、图标、指针与 Atuin（2026-10-24）

本轮只修改声明、文档并做隔离构建检查，没有应用配置、导入历史或删除用户数据。
开始时工作树干净；按用户明确要求新增本记录，未执行 stage/commit/push。

## 实现与归属

- `aspects/appearance/onedark-darker.nix` 与 `contract.nix`：公共字体分为 sans（Inter）、
  cjk（Noto 简中无衬线）、mono（Maple NF CN）、serif；增加文件夹颜色字段 blue，
  光标改为 Modern Classic、尺寸仍为 24。外观只拥有数据。
- `aspects/interactive-session/host/fonts.nix`：安装 `maple-mono.NF-CN`、`inter`，
  移除不再有消费者的旧等宽字体包；保留独立 Symbols Nerd Font Mono 回退包。
  fontconfig sans-serif 为 Inter 然后 Noto 简中，monospace 跟随公共 mono。
- `aspects/interactive-session/input-method.nix`、`aspects/media/mpv.nix`：候选与中文
  字幕消费 cjk，OSD 消费 mono；无 palette 时用通用 fontconfig 家族，不硬编码外观选择。
  `aspects/documents/zathura.nix` 的无外观界面回退同样使用 sans-serif。
- `aspects/interactive-session/gtk.nix`、`xorg/appearance.nix` 各自将
  `papirus-icon-theme.override { color = palette.iconFolderColor; }` 交给消费者，
  `xorg/default.nix` 的 Dunst XDG 路径也指向同一变体。主题名仍为 Papirus-Dark。
  blue 对应当前蓝色焦点；本轮未另选 bluegrey。
- `aspects/interactive-session/greeter.nix` 增加可在登录前访问的 Inter 包；字体与
  Bibata 光标仍消费 host palette。GTK、Mango/XCURSOR、Xorg 与 greeter 的指针均跟随公共字段。
- `aspects/interactive-session/xorg/dwm/package.nix`、`configure.py` 将 mono/cjk 作为
  参数传入，取消私有字体硬编码；保留 9.5 pt。dmenu、Dunst 和 Xorg 锁屏原有公共字段继续生效。
- `aspects/interactive-session/qt.nix`：除了新配置 seed，增加旧完整字体默认序列的有界
  迁移，仅在 Fonts 段精确匹配时替换。跳过 symlink，保留自定义字体和其他 GUI 键；没有运行激活。
- `aspects/command-line/default.nix`、`zsh.nix` 通过 Home Manager 启用 Atuin：
  `--disable-up-arrow`、`auto_sync = false`、`update_check = false`、compact、20 行、
  `enter_accept = false`、默认 global、shell up filter 为 session。主题由本应用从 palette
  生成到 `atuin/themes/onedark-darker.toml`，配置引用同名主题；无 palette 的纯 CLI 组合
  不生成主题，但仍可使用本地历史搜索。数据库归运行时用户数据，不自动 import。
- `aspects/command-line/checks.nix` 检查最终 Ctrl+R / Ctrl+T / Alt+C / 上箭头和配置主题；
  `aspects/interactive-session/checks.nix` 检查字体选择；`xorg/checks.nix` 更新隔离字体和
  图标包；`tests/composition/desktop.nix`、`protocols.nix` 覆盖字体字段类型、消费关系、
  Qt 旧值迁移、自定义保留和幂等。
- 文档：`docs/desktop-design.md`、`workflow-design.md`、`config-ownership.md`、
  `README.md` 与本记录同步。

Kitty、Noctalia 面板时钟、Qt fixed、mpv OSD 与 dwm 均消费 mono；终端 tmux/Neovim
没有单独 GUI 字体，继承 Kitty。Kitty 保持 11 pt：内屏 2560×1600 / 1.5 约有 1707×1067
逻辑空间，仅换家族不能决定缩字号，需真实窗口比较行宽/行距。原配置没有 symbol_map，
Maple 自带 Nerd/CJK 字形，不新增覆盖；另保留独立 Symbols 字体给其他消费者回退。

Inter 用于面板、控制中心、GTK、Qt、greeter、锁屏、Mango 装饰、图片信息与文档应用 UI；
Fcitx 候选和 mpv 中文字幕继续使用完整中文家族，避免中文正文依赖混合字体度量。

## 锁定源码与字体证据

锁定 nixpkgs 为 `da6dc0e7b26060f2f71ce3ef7088fb56ee44fa36`。
Noctalia `fc2af27c0e616006bf858cad3b7c9711a028e501` 已采用 C++，
`src/render/text/cairo_text_renderer.cpp` 调用 `FcInit`、`pango_cairo_font_map_new`、
`pango_font_description_set_family`、`pango_layout_set_text`，没有关闭 Pango 缺字回退。
因此 Inter 的家族请求可以对中文回退；不能沿用旧 Quickshell/QML 实现的假设。
隔离字体检查使用真实 host 的生成 fontconfig 规则，仍需真实混合文字视觉验收。

锁定 Home Manager `24f2190` 的 `modules/programs/atuin.nix` 支持 themes、Zsh flags 和集成；
`fzf.nix` 以 `mkOrder 910` 提前初始化，为 Atuin 接管 Ctrl+R 让出顺序，其他 fzf 按键保留。
Atuin 18.15.2 支持本轮设置和主题颜色角色；主题色来自公共 palette，没有增加外观对应用的依赖。

字体独立构建实际成功：

```sh
nix build --impure --no-link --no-write-lock-file --print-out-paths --expr \
  'let f = builtins.getFlake (toString ./.); p = import f.inputs.nixpkgs {system="x86_64-linux";}; in [ p.maple-mono.NF-CN p.inter ]'
fc-scan --format '%{family}; %{style}\n' /nix/store/6h0dvbxmjk96hq5yqnq4j9kp8b9z3hyr-MapleMono-NF-CN-7.9/share/fonts/truetype/MapleMono-NF-CN-Regular.ttf
fc-scan --format '%{family}; %{style}\n' /nix/store/2cksf1q8lqpgvcllipn5p56q7njbj9ly-inter-4.1/share/fonts/truetype/Inter.ttc
```

Maple 常规 face 返回 `Maple Mono NF CN; Regular`，Inter TTC 首 face 返回 `Inter; Regular`，
与配置完全一致。Inter 的两个 variable TTF 名为 Inter Variable，但同时安装的 TTC 提供 Inter，
所以不能只扫描 TTF 就断言名称不匹配。另实际用 `fc-query` 读取 charset，并检查 U+4E2D、
U+F07B、U+E0B0 均存在，证明中文、Nerd 文件夹与 Powerline 字形可用。

## 验证结果

实际执行并通过：

1. `git diff --check`；`nix fmt`；格式化后再次 `git diff --check`。
2. `nix flake check --no-build --no-write-lock-file`，最终退出 0、all checks passed。
   保留已有 `unknown flake output 'denful'` 警告；这是求值证据，不是系统应用证据。
3. 下列脚本实际执行，枚举当前全部 18 项 checks，加上真实 host 的 toplevel 构建，最终退出 0：

```python
import json, os, subprocess
checks = json.loads(subprocess.check_output([
    "nix", "eval", "--json", "--no-write-lock-file",
    ".#checks.x86_64-linux", "--apply", "builtins.attrNames"
], text=True))
os.execvp("nix", ["nix", "build", "--no-link", "--no-write-lock-file", "--print-out-paths"]
          + [".#checks.x86_64-linux." + name for name in checks]
          + [".#nixosConfigurations.nixos-btw.config.system.build.toplevel"])
```

18 项为 command-line-runtime、desktop-composition、editing-composition、embedded-composition、
embedded-home、embedded-tools、embedded-udev、interactive-session-config、local-services-composition、
neovim、project-workbench、protocols-composition、remote-workspace-composition、
rime-technical-runtime、system-boundaries、treefmt、workspace-composition、xorg-session-runtime。
包含构建沙箱内的 Xvfb/Xorg 行为检查，不等同于笔记本桌面验收。

新系统输出：

```text
/nix/store/7znxsgz6hldwy7n3521lhcim4991jsz1-nixos-system-nixos-btw-26.05.20261021.da6dc0e
```

构建产物已读回：

- `/nix/store/axjki8yx2chaaib1a9br2apcffzymbc1-interactive-session-config/` 的
  sans-family.txt、mono-family.txt、cjk-fallback.txt 分别是 Inter、Maple Mono NF CN、Noto 简中。
- `/nix/store/b1h8ihyjx7ziwjkp4ir6xrl9qrxs0wdj-den-interactive-session-composition/`
  保存 Qt 迁移、保留自定义字体及现有 palette 的结果。
- `/nix/store/i47w9g92ch31xy58710mxhji8cp7jdng-command-line-runtime/`
  的 zsh-ctrl-r 为 atuin-search，zsh-fzf-bindings 包含 fzf-file-widget、fzf-cd-widget、
  up-line-or-beginning-search。测试将生成 zshrc 的绝对 home/秘密文件路径重定向至隔离 HOME；
  不导入或读取真实历史。
- Papirus 构建包 `/nix/store/5vm57z2rc9dcywhmq3bxyjd9av2xj7d5-papirus-icon-theme-20250501`
  下 Papirus 与 Papirus-Dark 的 `48x48/places/folder.svg`，实际 `readlink` 都返回 folder-blue.svg。

初次求值曾暴露纯 CLI fixture 的 null palette 主题错误，修正可选主题后全量重跑通过。
独立 reviewer 还发现 Qt seed 不更新旧配置，补上有界迁移并通过组合检查；最终复核无未解决阻断。
改动文档的本地链接已用 Python 逐个检查目标存在，README/desktop/workflow/ownership 分别有
29/17/15/11 个本地链接。本记录按用户明确请求新增且未 stage，因此不在 Git flake 源快照内；
本轮配置与检查均是已跟踪文件，以上构建已包含，未使用 `path:.` 扩大源范围。

## 名称残留逐条核对

实际运行用户指定三个名称的递归 grep（排除 Git 元数据），结果如下。
旧鼠标主题名无匹配；旧等宽名字仅存在于 Qt 迁移匹配与其测试输入，不再作为当前字体选择。

| 文件与行 | 保留原因 |
|---|---|
| `aspects/appearance/onedark-darker.nix:8` | 中文专用公共字段，是保留的中文字体选择 |
| `aspects/interactive-session/qt.nix:113` | 只用于识别旧 UI 默认值，输出来自当前 palette |
| `aspects/interactive-session/qt.nix:114` | 只用于识别旧 fixed 默认值，输出来自当前 palette |
| `tests/composition/desktop.nix:355` | 旧 UI 字体迁移的测试输入 |
| `tests/composition/desktop.nix:356` | 旧 fixed 字体迁移的测试输入 |
| `aspects/editing/host.nix:10` | IDE 自带原生库的兼容原因，与字体无关 |
| `aspects/editing/jetbrains.nix:3` | IDE 包 RPATH workaround 原因，与字体无关 |
| `docs/desktop-design.md:75` | 记录界面中文回退规则 |
| `docs/desktop-design.md:138` | IDE 项目 launcher provider，与字体无关 |
| `docs/desktop-design.md:180` | 记录中文公共字段的准确 family |
| `docs/desktop-design.md:187` | 记录 sans-serif 回退顺序 |
| `docs/desktop-design.md:192` | 记录旧字体包已移除，不是安装声明 |
| `docs/desktop-design.md:199` | 记录中文字体选择检查的预期结果 |
| `docs/config-ownership.md:21` | 记录 Qt 旧默认值有界迁移的范围 |
| `docs/config-ownership.md:27` | IDE/编辑器配置与用户数据归属 |
| `docs/application-review.md:87` | 保留 IDE 功能的源码入口 |
| `docs/application-review.md:200` | 保留 IDE 项目 provider 的评估 |
| `docs/history/refactor-plan.md:144` | 历史 IDE 保留选择 |
| `docs/history/refactor-plan.md:153` | 历史 launcher 插件清单 |
| `docs/history/refactor-plan.md:238` | 历史 IDE 精简章节标题 |
| `docs/history/refactor-plan.md:268` | 历史软件取舍决定 |
| `docs/history/refactor-plan.md:329` | 历史应用/会话入口清单 |
| `docs/history/refactor-plan.md:353` | 历史 provider 保留决定 |
| `docs/history/refactor-plan.md:364` | 历史 provider 与工具依赖边界 |
| `docs/history/den-execution.md:41` | 历史编辑器功能迁移证据 |
| `docs/history/execution-handoff.md:85` | 历史完整编辑器/语言批次交接 |

## 应用后的实机待验

- Kitty 11 pt 的宽度、连字、Nerd/CJK 混排行距，tmux/Neovim 和 mpv OSD。
- Noctalia 面板、中文 launcher/控制中心、锁屏及 greeter 的缺字回退、裁切和数字宽度。
- GTK/Qt 字体、Qt 旧配置迁移后 GUI 保存与重启读回，Papirus 蓝色文件夹，以及 Mango/Xorg/
  XWayland/greeter 的 Classic 24 指针；混合 DPI/外屏仍待取得真实输出事实。
- 新 shell 的 Atuin Ctrl+R、Enter 仅返回编辑、上箭头原生搜索、fzf Ctrl+T/Alt+C 和主题。
  需要旧历史导入时由主代理应用配置后显式执行，保留原历史及 Atuin 数据库。
