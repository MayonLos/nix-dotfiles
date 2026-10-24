# 第十四轮：应用与会话公共支持视觉重做

工作目录为 `/home/mayon/nix-dotfiles-v-apps`，仅修改应用、会话公共支持及相关测试/文档；验证延续至 2026-10-25。
没有激活配置，没有改其他 worktree、Neovim、inventory、flake inputs 或锁文件；没有改应用登录、历史、学习库、vault 正文等用户数据。

设计依据为用户确认的 Astra `design-spec.md` §2、§3、§10 与 `panels-full.png` 的“浏览与整理”、横排候选样本：
`/tmp/claude-1000/-home-mayon-nix-dotfiles/13f9340b-d643-4d3f-bd2f-97266d0e2965/scratchpad/astra-design/`。
共享颜色只消费 [palette](../../aspects/appearance/appearance/onedark-darker.nix)，没有新增独立调色板。

## 实施与取舍

| 界面 | 对应设计 | 实现与边界 |
| --- | --- | --- |
| GTK3 / Thunar | §10 GTK/Qt；浏览与整理 | adw-gtk3-dark、主面 bg、侧栏 deep、工具栏 surface；选中 selection/brightFg 与细蓝边；路径栏圆角 8、焦点蓝线 2，边框预留避免焦点改变尺寸；状态栏使用 brightFg、次级信息使用 fg。侧栏宽度保留用户状态，不能用主题承诺固定 176–208。 |
| GTK4 / libadwaita | §10 GTK/Qt | 保留原生主题几何与 gtk4.theme=null，以 Noctalia 原有模板生命周期生成原色覆盖。私有绘制或不暴露的控件不承诺统一尺寸/圆角。 |
| Qt6ct / Fusion | §10 GTK/Qt | Window=bg、Base=deep、Button/AlternateBase=surface、正文 brightFg、Highlight=selection、HighlightedText=brightFg、Link=blue、PlaceholderText=fg；初始 seed 与运行时模板一致，既有 GUI 配置不整份覆盖。Fusion 控件保持原生形状。 |
| Papirus 文件夹 | §10 GTK/Qt | 保留 Papirus 图形，对 named blue 文件夹资源从 palette.blue 重着色；其他应用图标不改。Dunst 接线由桌面分支负责。 |
| Firefox 浏览器框架 | §10 Firefox | 地址栏 32 高/圆角 8/实蓝 2px 焦点；原生垂直标签 36 高、相邻间隔 4、中性选中底和蓝短标记。约 208 宽是视觉目标，保留 Firefox profile 的可调整宽度。 |
| Firefox 新标签页 | §10 Firefox；浏览与整理 | about:home/newtab 专属 userContent；安静背景、原生搜索与一行最多 8 个常用入口，关闭推荐内容。通过搜索组件公开 Shadow DOM CSS 变量接线；不注入图稿中的静态文案、时钟、假站点或项目数据。搜索文案由 Firefox 原生 locale 决定。 |
| Fcitx5 / Rime | §10 横排候选 | 明确关闭竖排，7 项/页，Pango 描述为 13 pt；bg/brightFg，序号与注释 fg，selection/blue 高亮与 1px 蓝边；外圆角 12、选项圆角 8，保留 DPI 修正和学习数据。 |
| Zathura | §2 跨应用原色 | 不透明 bg 与 brightFg，输入 deep、状态 surface、选中 selection。PDF 默认保留本色；recolor 仍须原生开关显式启用。主题缺失时 seed 与运行时模板使用同一 palette，已有文件保留。 |
| Obsidian | §2 跨应用原色 | 自有主题模板替换社区派生色；正文 brightFg/bg、侧栏 deep、工具栏 surface、中性激活面与蓝标记；按钮 selection/brightFg，勾选标记 blue。仅处理标准 registry 已登记且存在的 vault；离线/已移动条目跳过，不扫描整个 home。 |
| mpv / uosc | §2 跨应用原色、§3 圆角 | 字幕/OSD 正文 brightFg，深色描边；uosc 8px 圆角、中性选中填充，蓝搜索匹配。有限适配拆分上游共用的图标/进度前景与菜单/按钮选中底；升级后匹配不到源码片段即构建失败。保留 uosc 原生菜单高亮 15%/80% 等 opacity，属于图稿纯 selection 填充的近似。 |
| Swayimg | §2 跨应用原色 | 信息栏 brightFg/deep 全不透明，图库中性选择底与 2px 蓝边。 |
| Thunderbird | “若有主题接线”条件 | 无既有自定义主题接线，保留原生/GTK 支持；没有接管邮件 profile 或注入第二套 userChrome。 |

13 是 Fcitx 配置中的 Pango 点数，不把它宣称为 13 CSS px；实际 150% 缩放视觉大小仍需验收。
GTK/Qt、Firefox 均不改变应用自身的窗口大小、用户浏览历史和已保存侧栏宽度。

## 单一写入者与接口依据

- GTK/Qt 使用 `NOCTALIA_ASSETS_DIR` 原生资产覆盖：从最终选中的 Noctalia package 复制完整资产束，只换 GTK3、GTK4、Qt 三个模板。保持原有 builtin IDs、GTK apply/undo/import hook 与 Qt 输出，未新增同目标的 user template。原色经 `theme.templates.custom_colors`、`blend=false` 提供。
- 共享支持、Firefox、documents 直接导入上游 Noctalia HM option module，仅声明公开选项；Noctalia 默认关闭。Xorg-only 与应用独立选择不会因主题贡献而启动 shell。
- Firefox 保留现有 seed/template/application hook；同一模板分出 chrome/content 两段，更新两个文件各自的 managed block。块外 CSS、其他 user.js 偏好保留；目标/直接父目录软链、重复/损坏标记拒绝处理。
- documents 退出 obsidian/zathura community IDs，改由 feature 拥有的 user templates 渲染。Obsidian hook 只追加 `appearance.json.enabledCssSnippets` 中的 `noctalia`，保留其他 JSON 字段；拒绝软链链路、非普通目标、坏 JSON 和换行路径，原子替换其有限字段。移除功能保留 snippet、启用列表及 vault 数据。
- Qt 与 Zathura 都只在缺失时 seed 同一模板，不覆盖用户既有可变文件。Qt 原有字体精确迁移继续保留。

锁定源码核对：Noctalia 5.3 `src/core/files/resource_paths.cpp`、`src/theme/template_apply_service.cpp`、`assets/templates/builtin.toml`；Firefox 158.0.1 的 `browser/omni.ja` 中 `contentSearchHandoffUI.css`、`contentSearchHandoffUI.mjs`、`activity-stream.css`；fcitx5 5.1.19 的 Classic UI/Pango 配置与主题字段；Thunar 的 `thunar` / `sidebar` / `standard-view` CSS class；Obsidian 1.13.7 包内 `--checkbox-marker-color` 等变量；uosc 5.12.0 的 Menu/Button/TopBar 渲染；当前 Zathura `man zathurarc` 的 27 个颜色键。

## 子代理与独立复核

三个 Luna worker 分别负责 GTK/Qt、Firefox、Fcitx；Fcitx 完成后继续承担互不重叠的 documents 文件。
主代理负责媒体适配、真实 host 集成、公开 check registry、组合测试、设计判断和最终验证。
独立 reviewer 只读复核整个分支，最终未发现剩余 P1/P2 缺陷；指出 Firefox Shadow DOM 搜索框未适配、Obsidian stale registry 会阻断输出的问题，均已修正。

## 验证

- `git diff --check`：通过。
- `nix fmt`：最终重跑通过；未触碰 Neovim 或其他分支文件。
- `nix flake check --no-build --no-write-lock-file path:.`：通过，24 个 checks 均成功求值。上游 `denful` 输出产生 unknown-output warning，未阻断求值。
- `nix build --no-link --print-out-paths -f /tmp/gtk-template-parse-check.nix`：通过，输出 `/nix/store/f4iv871byc9ra3wivrdi62k2r8islkcp-gtk-template-parse-check`。当前 palette 实色替换后，GTK3/GTK4 真实 CSS provider 无 parsing-error。
- Firefox 临时 profile 5 项、Obsidian 临时 vault 10 项：已在 Nix checks 构建日志确认通过；不写真实 profile/vault。
- 全部 24 checks：执行 `nix build --impure --keep-going --no-link --no-write-lock-file --print-out-paths --expr 'builtins.attrValues (builtins.getFlake "path:/home/mayon/nix-dotfiles-v-apps").checks.x86_64-linux'`。22 项通过，2 项失败。此前一轮进程返回 `interrupted by the user`，已重新执行完整构建，未将中断计作通过。
- 两项失败：`interactive-session-config` 在 `aspects/desktop/mango-session/runtime-check.nix:245` 的旧背景常量断言失败（同文件另有一处旧常量断言）；`neovim` 在其 `config/tests/startup.lua:5` 断言失败。两处均在并行分支负责范围，本分支没有修改或掩盖这些失败。
- 对上述成功的 22 个实际 drv 再运行 `nix build --no-link --no-write-lock-file --print-out-paths <22 drv paths^out>`，全部成功并取得下表路径。
- `nix build --no-link --no-write-lock-file --print-out-paths 'path:.#nixosConfigurations.nixos-btw.config.system.build.toplevel'`：通过，输出 `/nix/store/9qlnc6lajlivkslzr5gxdghiasqc4917-nixos-system-nixos-btw-26.05.20261021.da6dc0e`。
- mpv 真实参数解析（null 音视频输出、单帧 lavfi）、uosc Lua 编译、Swayimg INI 与对比度计算由 `visual-apps-config` 执行并通过；Rime runtime、Noctalia/Mango Xorg-only 组合与配置校验通过。
- Papirus 重着色产物为 `/nix/store/ps5gfbb83y681i6jw50wh81ayiyjbnd6-papirus-icon-theme-20250501`；实际核对 48×48 blue folder SVG 含当前 palette.blue，旧源图标两档蓝已替换。
- 指定旧色扫描在 `aspects/apps/**` 与 `aspects/desktop/session-support/**` 为 0；历史文档链接检查通过。

## 对比度

`visual-apps-config` 实际按 sRGB 线性化计算，输出 `contrast.json`；没有把抗锯齿、视频画面或合成器实际屏幕效果算作已测。

| 前景 | bg | deep | surface | selection |
| --- | ---: | ---: | ---: | ---: |
| brightFg | 11.406 | 12.326 | 10.034 | 8.413 |
| fg | 7.494 | 8.099 | 6.593 | 5.528 |
| blue | 6.760 | 7.305 | 5.947 | 4.986 |

这些 palette 平面文字组合均超过 4.5:1；blue/selection 作为短交互候选/图标文字验收，不声称达到 7:1。
Firefox 158 搜索 handoff 的 shadow 内 `.fake-textbox` 原生 opacity=0.54，无公开 opacity 变量；brightFg 叠 surface 后约为 4.05:1，低于 4.5。保留原生组件与该限制，没有用源码补丁或伪占位文本冒充已达标。

边框是装饰；必要文字不用 border 或 muted。mpv 字幕/uosc 叠在视频上的最终对比、原生禁用态淡化和 GTK4 私有控件不包含在上述平面结果中。

## 待实机验收

本轮止于源码、求值、构建和隔离配置检查，没有执行 switch/test、重载或启动真实应用 writer。
需在应用后于 100%/150% 与混合缩放检查：Thunar 侧栏/文件行/状态栏、GTK/Qt 原生和私有控件、Papirus 各尺寸、Firefox 原生垂直标签与搜索焦点/窄窗/站点布局、Fcitx 长中文候选与避边、Obsidian 实际 vault snippet、Zathura recolor 开关、uosc 控件/字幕叠不同亮度视频、Swayimg 图库/信息栏。还需核对 Noctalia apply/undo 与现存用户文件的交接；构建通过不等于这些界面已生效。

## 改动文件

- [aspects/apps/documents/README.md](../../aspects/apps/documents/README.md)
- [aspects/apps/documents/checks.nix](../../aspects/apps/documents/checks.nix)
- [aspects/apps/documents/default.nix](../../aspects/apps/documents/default.nix)
- [aspects/apps/documents/resources/obsidian_theme.py](../../aspects/apps/documents/resources/obsidian_theme.py)
- [aspects/apps/documents/resources/test_obsidian_theme.py](../../aspects/apps/documents/resources/test_obsidian_theme.py)
- [aspects/apps/documents/templates.nix](../../aspects/apps/documents/templates.nix)
- [aspects/apps/documents/zathura.nix](../../aspects/apps/documents/zathura.nix)
- [aspects/apps/firefox/README.md](../../aspects/apps/firefox/README.md)
- [aspects/apps/firefox/checks.nix](../../aspects/apps/firefox/checks.nix)
- [aspects/apps/firefox/default.nix](../../aspects/apps/firefox/default.nix)
- [aspects/apps/firefox/resources/apply-noctalia-userChrome.py](../../aspects/apps/firefox/resources/apply-noctalia-userChrome.py)
- [aspects/apps/firefox/resources/firefox_profile.py](../../aspects/apps/firefox/resources/firefox_profile.py)
- [aspects/apps/firefox/resources/noctalia-userChrome.css](../../aspects/apps/firefox/resources/noctalia-userChrome.css)
- [aspects/apps/firefox/resources/seed-firefox-ui.py](../../aspects/apps/firefox/resources/seed-firefox-ui.py)
- [aspects/apps/firefox/resources/test_firefox_ui.py](../../aspects/apps/firefox/resources/test_firefox_ui.py)
- [aspects/apps/media/README.md](../../aspects/apps/media/README.md)
- [aspects/apps/media/images.nix](../../aspects/apps/media/images.nix)
- [aspects/apps/media/mpv.nix](../../aspects/apps/media/mpv.nix)
- [aspects/apps/media/resources/refine-uosc.py](../../aspects/apps/media/resources/refine-uosc.py)
- [aspects/desktop/session-support/README.md](../../aspects/desktop/session-support/README.md)
- [aspects/desktop/session-support/checks.nix](../../aspects/desktop/session-support/checks.nix)
- [aspects/desktop/session-support/default.nix](../../aspects/desktop/session-support/default.nix)
- [aspects/desktop/session-support/gtk.nix](../../aspects/desktop/session-support/gtk.nix)
- [aspects/desktop/session-support/input-method.nix](../../aspects/desktop/session-support/input-method.nix)
- [aspects/desktop/session-support/qt.nix](../../aspects/desktop/session-support/qt.nix)
- [aspects/desktop/session-support/resources.nix](../../aspects/desktop/session-support/resources.nix)
- [aspects/desktop/session-support/resources/gtk/gtk3.css](../../aspects/desktop/session-support/resources/gtk/gtk3.css)
- [aspects/desktop/session-support/resources/gtk/gtk4.css](../../aspects/desktop/session-support/resources/gtk/gtk4.css)
- [aspects/desktop/session-support/resources/gtk/recolor-papirus-folders.sh](../../aspects/desktop/session-support/resources/gtk/recolor-papirus-folders.sh)
- [aspects/desktop/session-support/resources/qt/qtct.conf](../../aspects/desktop/session-support/resources/qt/qtct.conf)
- [aspects/desktop/session-support/rime-checks.nix](../../aspects/desktop/session-support/rime-checks.nix)
- [aspects/desktop/session-support/rime/README.md](../../aspects/desktop/session-support/rime/README.md)
- [aspects/desktop/session-support/rime/theme.nix](../../aspects/desktop/session-support/rime/theme.nix)
- [docs/desktop-design.md](../../docs/desktop-design.md)
- [nix/checks.nix](../../nix/checks.nix)
- [tests/composition/desktop.nix](../../tests/composition/desktop.nix)
- [tests/composition/visual-apps.nix](../../tests/composition/visual-apps.nix)

## 成功 checks 产物

| Check | 输出 |
| --- | --- |
| architecture | `/nix/store/xd8asxq7n3vmrcvrf5p6rd6765axx8w4-architecture-check` |
| command-line-runtime | `/nix/store/jb64jqm92d874kiz3d0rg7xy4vz342j6-command-line-runtime` |
| deadnix | `/nix/store/3xkmh3aadnzy7cakkr4ypkdymxk0gjq1-deadnix-check` |
| desktop-composition | `/nix/store/ckkgp7r7c2l8jmjrhx7zh663mvzs37z0-den-interactive-session-composition` |
| documents-visual-config | `/nix/store/m5h2l2dd1ln75x0cm72avy8m98hj9asv-documents-visual-config-check` |
| editing-composition | `/nix/store/spaa49v89jzm85rgzclqxdb2wf8wcj5c-den-editing-composition` |
| embedded-composition | `/nix/store/bcr4pfqw1hmg72ip2ijgrd0m4pmxq7df-den-embedded-workbench-composition` |
| embedded-home | `/nix/store/4rh4qxizav1mn302sphd3ygd6iw0bkgp-home-manager-generation` |
| embedded-tools | `/nix/store/mdqqzg9ydky09zinmqdlpsskzyrnr5rk-den-embedded-tools` |
| embedded-udev | `/nix/store/9hq563arg4kaa4adfngys3vdbi8c2gkw-den-embedded-udev` |
| firefox-ui | `/nix/store/0wf5bajv7hi1yx4cmkfixzm0lqxzkhhr-firefox-ui-check` |
| local-services-composition | `/nix/store/3fnphnz3gvvh9wr026g2k9znpj89gyff-den-local-services-composition` |
| project-workbench | `/nix/store/4ll8n8ima07wcck37bcbfc0n211gqpcw-project-workbench-check` |
| protocols-composition | `/nix/store/wjsib0bxv793w1nmz3asyxqmmr9w2z00-den-protocol-composition` |
| remote-workspace-composition | `/nix/store/72sgdk5q97r1bfm5kbbq94h0s4sqdph0-remote-workspace-composition.json` |
| rime-technical-runtime | `/nix/store/jb2wv69012vdgw7zhmgyj0vq1ss2hpr9-rime-technical-runtime` |
| statix | `/nix/store/l090fsbzqsqvw2kwbpl4qbn31d2mxdsx-statix-check` |
| system-boundaries | `/nix/store/98fi9zibzbz5n4a3qjygkcy19d19f7xm-den-system-boundaries.json` |
| treefmt | `/nix/store/r5krd0wqjlbhqdm5kvrdjll2m0i1jrad-treefmt-check` |
| visual-apps-config | `/nix/store/8g6bv2x5k999zf0gk3b25gnfl88344fs-visual-apps-config` |
| workspace-composition | `/nix/store/w2a5jblnwa20mw5qw406ibl8wp8fawxr-den-command-line-composition` |
| xorg-session-runtime | `/nix/store/2nalmbjv9yv32vh4dsnpjysbqcb6hl6s-xorg-session-runtime` |
