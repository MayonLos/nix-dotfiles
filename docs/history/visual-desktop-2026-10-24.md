# 第十四轮桌面视觉实施 · 2026-10-24

依据：[Astra 设计稿](../visual-design.md)，2026-10-24 用户确认。
本分支在 `/home/mayon/nix-dotfiles-v-desktop` 隔离 worktree 实施；没有 stage、commit、push，
没有 sudo、rebuild 或激活。未触碰其他 worktree、Neovim、palette 内容或原有图片。

## 实施与文件

- §3–4：`aspects/desktop/mango-session/noctalia/bar.nix`：40px 顶栏、8/16 边距、实底状态胶囊、中文日期、活动工作区 selection/blue，数字缩放约13px。
- §5：`noctalia.nix` 与 `noctalia/astra-selection.patch`：680 full pinned Launcher；控制中心680/compact、浮动右上12，头像、6个快捷块；Launcher列表/网格选中面、活动Home块和工作区文字用局部原生渲染补丁。Primary仍为blue，正文角色不重映射。
- §6：通知380、16/64、最多3条；OSD底距32；背景.98；critical保留原生红边，warning用normal消息的图标/文案。锁屏compact输入，中文日期，不显示天气/媒体，blur.40/tint.48/淡入200ms；加入libnotify。
- §3、7：`mango.nix`：2px蓝色焦点边、12圆角；inner8/outer16、overview16/32；tab/group/title/jump选中selection/blue；标题字体10.5、jump Maple Bold12；仅浮窗black/.32阴影0/6；动画220/140、move180/tag220、focus0、zoom.96/.98。
- §6：`aspects/desktop/greeter/greeter.nix`：共享默认壁纸、中文日期与LC_TIME，原生小登录按钮。
- §11：`aspects/appearance/appearance/resources/wallpaper/{package.nix,render.py,RECIPE.md,CREDITS.md}`：4张构建期SVG→PNG、4张固定URL/hash Unsplash JPEG、5张原有冷色图；静湾默认。程序化图比设计配方更亮、光晕更明显；全部源色来自palette，LCG噪声固定种子。照片保留原色。
- Xorg仅外观跟随：`dwm/{configure.py,package.nix}`选中底与蓝字；`home.nix`与`lock.nix`共享默认壁纸；锁屏日期中文、透明线色取palette。
- 检查：`mango-session/runtime-check.nix`、`xorg-session/{checks.nix,runtime-check.nix,tests/test_desktop.py}`；`tests/composition/desktop.nix`去掉旧背景常量断言，改为共享palette；相关README与`docs/desktop-design.md`、`docs/config-ownership.md`更新；本文件及`docs/visual-design.md`新增。

壁纸local目录只通过HM activation幂等创建，`managed`由HM管理唯一软链，Noctalia递归扫描共同父目录。
锁定5.3 `wallpaper.cpp` 的 `collectWallpaperCandidates` 与 `FileUtils::walkDirectoryTree` 明确支持目录软链，
以canonical去重避免循环。用户local及其内容不进入store，不移动、覆盖、删除；现有非目录报错保留。
本轮受“不写worktree外”约束，仅实现activation与隔离fixture，真实home目录将在用户应用时创建。
原001/004/006与其他既有图片均保留。

## 未采纳与接口边界

- Greeter小型Primary登录按钮保留蓝底/black字：设计稿§6明确允许的C类原生替代。没有把Primary整体改成暗色。
- S1/S2/S3阴影offset/blur、面板行高、头像/卡片精确大小、锁屏72px时钟等是视觉目标。锁定接口没有全部对应字段，使用原生布局，不虚构配置项。
- 警告不是Freedesktop urgency；不新增warning urgency。通知的应用图标保留原生/发送方身份，语义警告由文案和图标表达。
- Noctalia原生disabled淡化、用户卡壁纸tint及认证错误提示仍需实屏测量。补丁仅覆盖指定Launcher/Home/工作区，不宣称所有原生Primary按钮已逐像素改写。
- 壁纸轮换改变当前图后，锁屏随当前桌面；greeter仍使用静湾默认。锁屏与greeter的声明默认同源；锁定Noctalia自动轮换也会在shell启动时随机选图，不承诺每次启动仍显示默认图。
- 设计稿AI灰字原文保留；用户后续修正“muted+斜体”由独立Neovim分支处理，本分支未改编辑器。

## 并行与独立复核

三个luna-worker互不重叠：Noctalia配置/局部patch/README；Mango+greeter；Xorg+Mango检查。
主代理负责壁纸工厂/资源、home轮换目录、文档、集成、补丁修正与最终验证。
reviewer独立核对整个diff、锁定源码、wallpaper递归语义、writer与Unsplash授权。
发现并修复：Launcher遗留activeRole引用/错误patch context、Home关闭态custom palette残留、
检查字体10→10.5、backdrop应关闭。主代理从锁定原件重新生成统一diff；
`patch --dry-run --fuzz=0 -p1`三文件全部通过。最终复核无阻断缺陷；未代替运行时视觉验收。

## 对比度

Python按sRGB线性化、WCAG相对亮度公式实际计算。下表均为不透明平面值，蓝/青是短标签/图标；
红色用于标记和边线，surface/selection上不作小字正文。border仅装饰，不承担唯一焦点提示。

| 前景 | bg | deep | surface | selection |
|---|---:|---:|---:|---:|
| brightFg | 11.41 | 12.33 | 10.03 | 8.41 |
| fg | 7.49 | 8.10 | 6.59 | 5.53 |
| blue | 6.76 | 7.30 | 5.95 | 4.99 |
| cyan | 6.74 | 7.29 | 5.93 | 4.97 |
| yellow | 9.25 | 9.99 | 8.14 | 6.82 |
| red | 5.00 | 5.40 | 4.40 | 3.69 |

背景bg以.98覆盖白色并按8位取整：brightFg约10.85、fg约7.13；greeter black/blue约8.06。
blue/selection的4.99按短交互标签≥4.5验收，不误称正文≥7。

## 命令与证据

验证不激活配置；`nix fmt`只修改仓库源码。

- `git diff --check`、旧色扫描、文档本地链接：通过。
- `nix fmt`：最终通过。首轮发现新增home重复属性的statix提示，合并home attrset后通过。
- `nix flake check --no-build --no-write-lock-file path:.`：最终通过；仅保留仓库原有unknown output `denful`提示。这是求值层证据。
- 21项checks与toplevel：以`nix build --keep-going --no-link --no-write-lock-file --print-out-paths`实际全部请求构建。首轮有desktop-composition和neovim两项旧色断言失败；desktop断言已修成`${palette.bg}`。第二轮被外部中断（日志为interrupted by the user，未获具体原因）。修正后的desktop-composition与treefmt/statix/deadnix/toplevel已复跑通过：
  `nix build --no-link --no-write-lock-file --print-out-paths path:.#checks.x86_64-linux.desktop-composition path:.#checks.x86_64-linux.treefmt path:.#checks.x86_64-linux.statix path:.#checks.x86_64-linux.deadnix path:.#nixosConfigurations.nixos-btw.config.system.build.toplevel`。
  desktop-composition产物为`/nix/store/w0hfbnmz3s3449wh2gc4cp0imnwjgq67-den-interactive-session-composition`。
  最终toplevel：`/nix/store/hzki8v5jfl0ib55pgsyn21w40p1a6cr9-nixos-system-nixos-btw-26.05.20261021.da6dc0e`。
- Noctalia局部补丁包已编译成功：`/nix/store/fglb5mmdwv8d2iilgndzrg1mmiixnvi5-noctalia-5.3.0`。原先失败的activeRole引用在最终patch中已修复，零fuzz通过。
- `interactive-session-config`通过：`/nix/store/synypqf8csshghgxkgzncbwxcrpyqb28-interactive-session-config`。其中执行实际Noctalia `config validate`、Mango `-c ... -p`、字体fallback、writer/头像隔离fixture、壁纸尺寸和local activation测试。Noctalia显示Config is valid；同时有4条锁定插件manifest的设置遮蔽警告（rss-notifier的show_feed_images，iio_lock的unlocked/locked，mihomo-control的panel_placement），不把它报告为零警告。
- Xorg隔离运行检查通过：`/nix/store/n7ikgjsg64iki678f34mknhsp18ph537-xorg-session-runtime`，包含dwm/dmenu/Dunst/Picom及相关fixture。它不是实机Xorg会话验收。
- 新增8张图片均验证2560×1600；4张PNG的sRGB chunk均实际检查通过。四张程序化图和摄影缩略图已查看，未进行真实桌面截图验收。
- 未修改也未绕过`aspects/dev/neovim/config/tests/startup.lua:5`的`0x1f2329`旧背景断言；它使checks.neovim失败，须由独立Neovim分支修复。全量checks不能宣称全部通过。

新文件未stage；为避免`path:.`把本地scratch带入store，使用Git跟踪文件与未忽略新文件建立
`.work/validation/source`过滤快照，排除`.git`、`.work`、`.team`、`.worktrees`、`__pycache__`、`result*`。
快照只含仓库源码/公开资源/sops密文，随后在快照目录运行`path:.`。

最终收口跨至2026-10-25 00:00（Asia/Shanghai）。基于保留执行权限的最终代码过滤快照，
21项check的outPath逐一用`nix-store --check-validity`核实：20项有效，只有neovim缺失且已记录其构建失败。
最后单独执行`nix build --no-link --no-write-lock-file --print-out-paths path:.#checks.x86_64-linux.interactive-session-config`通过。
报告收尾追加命令结果，不改变已构建的配置代码。最终没有应用配置或创建真实home的local目录。

## 壁纸store路径

| 轮换文件 | 实际store路径 |
|---|---|
| `01-quiet-bay.png` | `/nix/store/w6g6ksxph9dldvlfcwxx6h7z6d5pnb2g-astra-wallpapers-2560x1600/01-quiet-bay.png` |
| `02-strata.png` | `/nix/store/w6g6ksxph9dldvlfcwxx6h7z6d5pnb2g-astra-wallpapers-2560x1600/02-strata.png` |
| `03-orbit.png` | `/nix/store/w6g6ksxph9dldvlfcwxx6h7z6d5pnb2g-astra-wallpapers-2560x1600/03-orbit.png` |
| `04-night-paper.png` | `/nix/store/w6g6ksxph9dldvlfcwxx6h7z6d5pnb2g-astra-wallpapers-2560x1600/04-night-paper.png` |
| `12-starry-sea.jpg` | `/nix/store/7dk5kc3kx31fak8qviq2ac51bhpa1mjm-12-starry-sea.jpg` |
| `13-blue-city.jpg` | `/nix/store/irir9qcrb77f32wq8k9dz1ggj4zy7401-13-blue-city.jpg` |
| `14-night-coast.jpg` | `/nix/store/srclncvywvw2ag4wyjrqzdq71931vfh6-14-night-coast.jpg` |
| `15-mountain-night.jpg` | `/nix/store/p18qa25kylqbd84h29x86cahlb88b19n-15-mountain-night.jpg` |
| `existing-002.png` | `/nix/store/1jvqyxlyr47np31w0rrv44ljbwl7vsgc-wallpaper-002.png` |
| `existing-005.png` | `/nix/store/q4rjlxsx98ahl40zj56b30piy4vv94ai-wallpaper-005.png` |
| `existing-008.png` | `/nix/store/ph3g3rv84x1blw2iia8f61y68ygf1q5b-wallpaper-008.png` |
| `existing-009.png` | `/nix/store/wpgnkaij8s76jxd6pqqdg1pjmmlbi4vl-wallpaper-009.png` |
| `existing-011.png` | `/nix/store/9v2lbjlw78ah0rjqilx7mrayxnmwah3n-wallpaper-011.png` |


## 待实机验收

150%缩放的中文/Maple、1px线和圆角；九tag、最长日期、五托盘图标与插件展开无重叠；
Launcher搜索/键盘选中、Home开关开→关→禁用；音量/亮度滑块；普通/警告语义/critical通知、长中文与action；
白色窗口后的.98合成、OSD；锁屏Caps Lock/错误提示/认证、greeter冷登录与会话选择；
local新图递归轮换、多屏缩放、功耗及帧时间。

## 改动清单

- `aspects/appearance/appearance/README.md`
- `aspects/desktop/greeter/README.md`
- `aspects/desktop/greeter/greeter.nix`
- `aspects/desktop/mango-session/README.md`
- `aspects/desktop/mango-session/mango.nix`
- `aspects/desktop/mango-session/noctalia.nix`
- `aspects/desktop/mango-session/noctalia/bar.nix`
- `aspects/desktop/mango-session/runtime-check.nix`
- `aspects/desktop/xorg-session/README.md`
- `aspects/desktop/xorg-session/checks.nix`
- `aspects/desktop/xorg-session/dwm/configure.py`
- `aspects/desktop/xorg-session/dwm/package.nix`
- `aspects/desktop/xorg-session/home.nix`
- `aspects/desktop/xorg-session/lock.nix`
- `aspects/desktop/xorg-session/runtime-check.nix`
- `aspects/desktop/xorg-session/tests/test_desktop.py`
- `docs/config-ownership.md`
- `docs/desktop-design.md`
- `tests/composition/desktop.nix`
- `aspects/appearance/appearance/resources/wallpaper/CREDITS.md`
- `aspects/appearance/appearance/resources/wallpaper/RECIPE.md`
- `aspects/appearance/appearance/resources/wallpaper/package.nix`
- `aspects/appearance/appearance/resources/wallpaper/render.py`
- `aspects/desktop/mango-session/noctalia/astra-selection.patch`
- `docs/history/visual-desktop-2026-10-24.md`
- `docs/visual-design.md`
