# 第七轮：输入法与 CLI 优化（2026-10-24）

工作目录：隔离 worktree `/home/mayon/nix-dotfiles-r7`，分支 `polish-im-cli`，基线
`main` 的 `5e6f59c`。本轮未应用系统配置，未改 `/home/mayon/nix-dotfiles`，未操作
个人 Rime/Fcitx5 运行态、用户词库、Atuin/Zsh 历史；没有 stage、commit、push。

## 实现与社区依据

- `aspects/interactive-session/rime/package.nix`：显式给 fcitx5-rime 提供含 Lua 与
  Octagram 的 librime，Rime-Ice 与模型同属共享数据包。锁定 nixpkgs 的 librime 1.16.1
  将插件合并入 `librime.so`，没有独立的 `librime-lua.so`/`librime-octagram.so`；检查
  实际动态库、导出符号与 C API `find_module`，不捏造单独插件文件。
- 模型：[万象 LTS release](https://github.com/amzxyz/rime-wanxiang-data/releases/tag/LTS)，
  [具体资产](https://github.com/amzxyz/rime-wanxiang-data/releases/download/LTS/wanxiang-lts-zh-hans.gram)。
  原 `amzxyz/RIME-LMDG` 已迁移到 `rime-wanxiang-data`。上游以长期复用的 `LTS`
  标签发布模型，当前编号方案 release（如 v18.1.7）只提供方案压缩包，模型链接仍指向
  LTS。这里固定 2026-10-19T03:42:47Z 资产快照，大小 **398497836 bytes**，
  SHA-256 **9eedac1d836f3fdafb61b162035c8937253aedc106be40b2b957d9ab64e9ed89**，
  SRI `sha256-nu2sHYNvP9r7YbFiA1yJNyU67cEGvkCyuVfZq2Tp7Yk=`。实际下载与 release
  digest 一致；标签下替换资产会触发 hash 失败，不能静默升级。
- `input-method.nix`：七项候选页；保留专业复合字典、`rime_ice.userdb` 与所有现有
  Lua 功能。语法参数采用[白霜 README](https://github.com/gaboolic/rime-frost#使用语言模型)
  的 max/min length 5/2、collocation penalty -14、non-collocation penalty -4，
  contextual suggestions=true，homophones/homographs=4/2。
  另对照了[雾凇官方语法 recipe](https://github.com/iDvel/rime-ice/blob/main/others/recipes/grammar.recipe.yaml)：
  同样使用万象 LTS，但其当前 contextual suggestions=false；本轮按任务要求选用白霜的启用组合。
- `rime/theme.nix`：借鉴 [Catppuccin Fcitx5](https://github.com/catppuccin/fcitx5)
  的 SVG nine-slice 背景，palette 生成 panel/highlight/prev/next/radio/arrow；
  1px 描边、圆角和更宽文字边距，保留 blue/black 选中语义与 DPI 修正。
- `aspects/command-line/onedark-darker-bat.nix`：生成共享 `.tmTheme` 与 Nix 构建期
  缓存，作用域色参考 [onedark.nvim darker](https://github.com/navarasu/onedark.nvim/blob/master/lua/onedark/palette.lua)。
  [bat 自定义主题/缓存](https://github.com/sharkdp/bat#adding-new-themes)；
  `BAT_CACHE_PATH` 指向 store，HM 激活不重建。现有用户 cache 不删除。
  现有 interactive-session/environment.nix 在本轮可写范围之外，仍声明 BAT_THEME=base16；
  tools.nix 对这一旧单值使用带原因的 mkForce，让 CLI 与桌面读同一主题。后续归属整理
  可移除桌面的旧声明并撤去此覆盖，本轮未越界修改。
  Delta 0.19.2 的[缓存目录源码](https://github.com/dandavison/delta/blob/0.19.2/src/utils/bat/dirs.rs)
  只看 XDG cache 根目录、忽略 BAT_CACHE_PATH；[加载逻辑](https://github.com/dandavison/delta/blob/0.19.2/src/utils/bat/assets.rs)
  从该目录的 bat 子目录读预编译缓存。专用 Delta wrapper 将其进程的 XDG_CACHE_HOME
  指向含同一 cache 的 store 根目录，不修改用户全局 XDG_CACHE_HOME，也不重编译 Delta。
- `sysinfo.nix` / `onedark-darker-btop.nix`：CLI-only btop 自有主题，Mango 继续
  选择 Noctalia 主题；两个 theme 路径分开，HM 生成 btop.conf。未选择外观数据的
  独立组合仍用内置主题/ANSI；新增组合检查同时覆盖显式 palette 与 null。主题格式参考
  [btop 官方 OneDark 主题](https://github.com/aristocratos/btop/blob/main/themes/onedark.theme)。
  fastfetch 使用小号 Nix logo、统一 Nerd 图标、系统/硬件框线分组与 palette RGB；
  保留原有所有信息模块，参考 [Fastfetch 官方配置文档](https://github.com/fastfetch-cli/fastfetch/wiki/Configuration)。
- `tools.nix`：生成 eza 主题（[官方主题字段](https://github.com/eza-community/eza/blob/main/docs/theme.yml)）、
  glow palette JSON（[Glamour StyleConfig](https://github.com/charmbracelet/glamour/blob/master/styles/dracula.json)）；
  tealdeer 开启每周按使用自动更新缓存，依据[官方缓存设置](https://tealdeer-rs.github.io/tealdeer/config_updates.html)。
- `kitty.nix`：保留字体、1.0 opacity、padding 8；cursor trail 蓝色、4 格阈值、
  80–160 ms 衰减、reducedMotion 时关闭；powerline/slanted tab、thick-sparse undercurl。
  参数核对 [Kitty 官方配置](https://sw.kovidgoyal.net/kitty/conf/)。
  Zsh/Starship/fzf/lazygit/Yazi 既有角色色符合 palette/ANSI，没有修改键位。

## 验证

验证中先修复了两处组合/工具问题：null appearance 的 portable CLI 必须保留 ANSI/内置主题；
fastfetch RGB format 需要 `{##4fa6ed}`，已用实命令验证多一个 `#` 会退出 223，check 改为
`--pipe false` 以覆盖颜色 parser。首次全量构建的 treefmt check 因 `path:.` 带入 worktree
`.git` 指针而退出 128，未运行格式检查本体；`nix/checks.nix` 现仅为 treefmt 去掉该 Git
元数据，保留未跟踪源码，让它在沙箱内创建自己的 Git fixture。没有访问指针目标或操作
真实仓库 index。bat 的 HM 主题声明改用 src 属性，消除旧 string 主题弃用警告。

实际完成的命令（均在本 worktree 执行，退出码 0）：

```sh
git diff --check
nix fmt
nix flake check --no-build --no-write-lock-file path:.
nix build --no-link --no-write-lock-file --print-out-paths --impure --expr '
  let f = builtins.getFlake ("path:" + toString ./.);
  in (builtins.attrValues f.checks.x86_64-linux)
     ++ [ f.nixosConfigurations.nixos-btw.config.system.build.toplevel ]
'
```

全部 **18 个 checks** 构建成功：command-line-runtime、desktop-composition、
editing-composition、embedded-composition、embedded-home、embedded-tools、embedded-udev、
interactive-session-config、local-services-composition、neovim、project-workbench、
protocols-composition、remote-workspace-composition、rime-technical-runtime、system-boundaries、
treefmt、workspace-composition、xorg-session-runtime。未修改 Neovim 源码。
`flake check --no-build` 是求值证据，随后上述 `nix build` 才是实际构建证据。
仅保留已有的 `unknown flake output 'denful'` 提示；bat 主题弃用警告已消除。
文档记录补齐后另构建 treefmt 检查；其路径随本文内容变化，不在本文硬编码。

新 toplevel（已构建，未激活）：

```text
/nix/store/adjp1fwc8v47s7gzsbpb004717xiiwf3-nixos-system-nixos-btw-26.05.20261021.da6dc0e
```

重要证据产物：

| 内容 | 实际 store 输出 / 结果 |
| --- | --- |
| Rime 隔离部署检查 | `/nix/store/3h92g2wp96giaffyk56j8dqa6ivlqbsw-rime-technical-runtime` |
| CLI 解析与渲染检查 | `/nix/store/v52vq9rjvysamm8h59hhmsjjjc8yqnia-command-line-runtime` |
| 专业词、普通词、英文、纠错 | 8 组输入均 PASS；schema 检查七项页、grammar、contextual_suggestions、4/2 上限及原 user_dict |
| 模型共享目录 | `/nix/store/wa9ck4r23sknniypbq6ynvhn7kfy85j5-fcitx5-rime-5.1.13/share/rime-data/wanxiang-lts-zh-hans.gram` 是链接，大小/hash 均通过 |
| 模型实际加载 | `deploy.log` 有 `use grammar: wanxiang-lts-zh-hans`、共享路径 `loading gram db`、`found double array image of size 99624448`，无 error/failed/cannot/could not |
| librime 与插件 | `/nix/store/hl5h6j4dxbams0dpvk2sx5cy4wrfpc6i-librime-1.16.1/lib/` 中实际为 `librime.so.1.16.1`、`librime.so.1`、`librime.so`；`nm -D` 可见 `_Z23rime_require_module_luav` 与 `_Z28rime_require_module_octagramv`，C API 查找两模块成功 |
| Fcitx5 主题 | `/nix/store/k9rghbr8z4bwhcj2vlkza9fnwpi3f4vl-fcitx5-onedark-darker-theme`；INI 解析及 8 个 Image 引用全部通过，6 个 SVG 用 rsvg-convert 渲染成功 |
| bat 缓存 | `/nix/store/d39y5xyh2js1m4rrzc5bhrsdgygz74nn-onedark-darker-bat-cache` 有 themes.bin/syntaxes.bin；batCache 激活为空 |
| bat 实际渲染 | 构建的 bat 0.26.1 用该 BAT_CACHE_PATH 执行 `--list-themes --color=never`，grep 命中 `One Dark Darker`；Python 样例渲染成功，另用 COLORTERM=truecolor 渲染仓库 kitty.nix 得到 9544 bytes、包含 24-bit RGB escape |
| Delta 实际渲染 | `/nix/store/f4ly0mwh5j78pmh9p9pn9f1fjqpvgil3-delta-onedark-darker` 能列出并用同名主题渲染 diff 样例，包含 RGB escape |
| 其他 CLI | Kitty 原生 parser、palette/字体/padding/opacity/拖尾/标签断言通过；fastfetch 真彩配置完整运行，eza 加载 theme 无错误，Glow 样例正常退出，tealdeer TOML 自动更新与禁用 timer 断言通过；原 Zsh/Atuin/fzf/tmux 键位检查保留并通过 |

直接重现 bat 渲染（只读文件输入）：

```sh
BAT_CONFIG_PATH=/dev/null \
BAT_CACHE_PATH=/nix/store/d39y5xyh2js1m4rrzc5bhrsdgygz74nn-onedark-darker-bat-cache \
/nix/store/18wwww4lniqzx72yfga536wrv70aggpw-bat-0.26.1/bin/bat \
  --list-themes --color=never | rg '^One Dark Darker$'

COLORTERM=truecolor BAT_CONFIG_PATH=/dev/null \
BAT_CACHE_PATH=/nix/store/d39y5xyh2js1m4rrzc5bhrsdgygz74nn-onedark-darker-bat-cache \
/nix/store/18wwww4lniqzx72yfga536wrv70aggpw-bat-0.26.1/bin/bat \
  --no-config --theme='One Dark Darker' --color=always --style=plain \
  aspects/command-line/kitty.nix
```

## 改动文件

```text
aspects/interactive-session/input-method.nix
aspects/interactive-session/rime/package.nix (新增)
aspects/interactive-session/rime/theme.nix (新增)
aspects/interactive-session/rime/README.md
aspects/interactive-session/rime-checks.nix
aspects/interactive-session/resources/rime-smoke.c
aspects/command-line/default.nix
aspects/command-line/tools.nix
aspects/command-line/git.nix
aspects/command-line/sysinfo.nix
aspects/command-line/kitty.nix
aspects/command-line/checks.nix
aspects/command-line/onedark-darker-bat.nix (新增)
aspects/command-line/onedark-darker-btop.nix (新增)
tests/composition/protocols.nix
tests/composition/workspace.nix
nix/checks.nix
docs/desktop-design.md
docs/config-ownership.md
docs/history/im-cli-polish-2026-10-24.md (新增)
```

`docs/README.md`、`docs/workflow-design.md`、flake.lock 和其他 worktree 未修改。
独立 reviewer 已复核跨模块边界、可选外观回退、Delta 缓存及 treefmt 源过滤；
指出的 Noctalia undo 限制已写入本记录和当前归属文档。所有新增源文件保持未跟踪，未使用
`git add -N`；因此求值/构建使用 `path:.`。使用前检查 `git status --short --ignored`，
没有被忽略的运行态数据或明文秘密；源范围内 `secrets/` 仍只有仓库已有的加密输入。

## 待实机验证

构建和隔离 smoke test 不代表实际桌面验收。本轮未 switch/test/激活。

- 连续整句、专有词、英文混输的实际准确率与延迟，学习库延续体感。
- Mango 与 Xorg 下候选框圆角、七项页高度、箭头/菜单、蓝底黑字、150% 缩放。
- Kitty 快速光标跳转的拖尾、tmux/编辑器中运动量、reducedMotion；多标签可读性。
- CLI 在新会话中的 BAT_CACHE_PATH 和 delta wrapper、Nerd glyph 回退、窄窗口布局。
- Noctalia btop 的 apply/undo 仍需现场验证：上游 undo hook 试图重写 btop.conf，
  既有 HM store symlink 下预计失败；本轮未更改桌面 hook，也未声称 undo 已通过。
