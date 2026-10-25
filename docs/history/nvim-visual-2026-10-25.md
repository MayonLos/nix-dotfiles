# 第二十轮：Neovim 视觉对齐与启动页重做

日期：2026-10-25。依据用户确认的 scratchpad `ui2/desktop.html/png` 左侧编辑器、`ui5/dash.html/png` 启动页，以及实机问题截图 `images/6.png`、`images/7.png`。只修改 Neovim、其测试和本文档及视觉规范的 Neovim 段；没有修改 ui4 worktree、应用配置或用户状态。

## 设计与实现

- 启动页移除渐变 ASCII，使用单行 mayon.nvim、项目/分支、72列内容及左48列蓝线段；8动作两列、真正的surface键帽、selection/蓝条选区；RECENT/PROJECTS与右对齐路径；footer靠近底部，状态栏仅NORMAL dashboard与q退出。缺失文件图标留空，不再把类型名当图标。CJK没有额外字距。
- 编辑器与启动页使用bg，sidebar/tabline/statusline/floats使用deep；edge由palette border/deep混色。Explorer仅一次大写根标题，宽30、▸/▾+蓝目录图标、fg文字、无树线、右对齐Git字母、无诊断占位、长文件名保留扩展名。窗口布局与根切换保持标题和rail。
- Tab去掉devicon/关闭按钮/文件数/漂浮overline；活动标签用真实蓝下划线属性近似顶部2px线、未保存orange点。绝对行号，保留zc/zo但无fold箭头；inlay默认关、␣uh切换；移除Satellite标记、自动粘性上下文和非当前作用域缩进线。
- 状态栏使用selection模式块、紫分支、green/yellow Git计数、basename、诊断、单个非Copilot主LSP、AI · Copilot及surface位置块。保留原生进度、请求状态与简洁[+]/RO安全信息。补全kind前置且紫色、类型muted；Claude仍用锁定插件的原生split/diff。
- reviewer发现并推动修正：worktree绝对gitdir、非聚焦dashboard resize误绑定普通文件、recent Enter从错误buffer捕获回调、网格纵向移动丢失右列、Explorer切根标题滞后。测试覆盖这些行为，不调用模型接口。

## 截图迭代

所有输出在 `/tmp/claude-1000/-home-mayon-nix-dotfiles/13f9340b-d643-4d3f-bd2f-97266d0e2965/scratchpad/ui5/`。使用过滤源码快照构建公开 `neovim` 包（与HM同一package.nix normal工厂、palette），临时HOME/XDG、独立tmux服务200×52；通过Neovim RPC/API打开文件、设置217行和视图，不模拟按键。`tmux capture-pane -e -p`经Python按ANSI颜色和终端cell转换HTML，Maple Mono NF CN、zoom1.5，Nixpkgs Chromium155 headless截图2560×1440。没有重绘或伪造截图中的界面内容。

| 轮次 | 截图后发现 | 修正 |
|---|---|---|
| 1 | 内容48列过窄，路径挤掉文件名，中文导致键帽高亮byte/cell错位；直接Explorer入口无标题，root tree节点不是internal | 内容72列，文件名预算优先，按字节定位；统一入口，按cwd过滤root；移除顶部粘性上下文 |
| 2 | keycap分段背景盖住选区；布局重新应用默认wo导致Explorer标题/rail丢失；footer计入原生dist插件 | 选中cell真实overlay span；保持layout.win_opts；以生成插件闭包计数；footer贴底，项目路径缩写 |
| 3 | 非聚焦Explorer rail比较了当前编辑窗口光标；标题仍受缓存布局覆盖；未保存status圆点仍旧 | 持久化布局捕获wo、按被绘制窗口确定rail；目录图标；[+]/RO；修正reviewer边界 |
| 4 | 根标题、扩展名、图标已正确；代码缩进线仍比稿密，非焦点蓝条待最后复核 | 禁用额外缩进线，修正rail窗口选择；补原生补全列顺序与图标 |
| 5 | 实际HM包确认蓝条与无额外线条；界面已接近稿；真实首帧39.38ms | 把首帧无关UI初始化移到既有VeryLazy；冷启动恢复、resize/Enter与CodeDiff fixture同步补回归 |

第一次准备截图时快照恰逢子任务替换dashboard文件，出现缺文件启动错误；该包已弃用，不计入有效轮次。有效迭代的包、ANSI/HTML/PNG、probe JSON和构建日志全部保留。截图历史由隔离fixture提供，只有本仓库项目，不伪造用户的其他项目或Copilot登录。

## 验证与边界

初次最终构建五个目标均exit 0，但提取构建日志后发现原有CodeDiff测试在CodeDiffOpen事件后立即关闭并删除临时仓库，尚未完成的异步buffer加载产生延后错误。已改为等待两侧before/after文本实际加载，再关闭、离开临时cwd并清理；runner额外断言延后错误不得吞掉。Live隔离复跑codediff、interface、workflow、startup、completion、native均通过。随后按完整最终包重新验证，不以第一次exit 0掩盖该问题。

初次HM包新进程中位数20.89ms；另加tmux首帧测量为39.38ms，发现图标表与scroll/input/scope/picker不参与启动页绘制却在UIEnter加载。改为文件首次读入加载图标、已有scheduled VeryLazy事件初始化其余组件；保留同步启动页与快捷键。开发配置预检首帧约25ms，最终不可变包结果见下方补录。完整求值期间曾检测到ui4代理另有Nix构建，主代理立即中断自身求值，随后以进程监视退让：发现其他Nix时等待，其他任务中途启动Nix时中断本任务并排队重试，不干预ui4。后续所有Nix求值/构建由主代理串行执行，`--max-jobs 1 --cores 4`；新文件通过Git已跟踪/非忽略源码白名单复制，排除.work、result、运行时状态，secrets仅接受sops密文；没有使用未过滤path:.，没有git add。

TUI不能混用HTML的30px字标和11px分组字号，也不能绘制任意2px顶线、圆角键帽和独立diff卡片。当前文件第217行的内容、光标实际列和文件总行数与旧图稿不同；状态栏显示真实位置，不写死217:28/64%。Copilot footer表示已配置的可执行提供者，隔离环境不携带真实登录凭据；不把绿色提供者标识当网络认证验收。构建成功不代表已应用到用户桌面。

## 第二阶段：全部工作台表面

用户追加 `ui5/panels.html/png`。恢复第一阶段文件后，继续实际包/TUI 验证，不把恢复的旧日志当最终改动证据。三个 Luna 窄任务分别负责 picker、AI 和辅助面板，主代理接线、运行、截图、修正；独立 reviewer 用锁定源码与原生插件复现边界。

- picker 统一来源/范围/计数、blue prompt/match、选中 rail、deep 预览；文件名/路径分列。最初虚拟 grep 标题经 reviewer 实测会让原生 list.top 与物理视口分离，已改为真实标题条目；30 文件/90 行真实 rg 回归覆盖跨页选择。标题条目保留首个命中路径/位置，可直接打开。Explorer 的 `i` 改为根目录范围的居中文件搜索；原30列导航侧栏保留，回归覆盖范围/布局/关闭后宽度。
- AI 提供者/模型和下划指示、右侧38%面板、用户灰 rail、muted 角色、cyan 工具摘要、原生输入提示；代码与 diff 使用自有淡底高亮，未覆盖全局 DiffAdd/Delete。Claude/Sidekick 首次入口也初始化，普通终端不显示 AI 标签。
- notifier 使用公开 renderer，右上 deep/细级别 rail，无大图标。LSP hover/signature/diagnostics 共用浮窗；完整 complete_info() 才返回 preview_winid，按字段筛选返回空表，已依据实际运行修正。
- Trouble/quickfix/location list 保留原生数据/跳转，计数、分组、CJK 显示宽度截断、位置右对齐；Edgy 配置显式保留自有 winbar，避免覆盖。which-key 无边框标题通过锁定 view.show 渲染后设置本地 winbar，宽度0.999，4列；精确1在锁定插件中是1字符而非比例，已从截图纠正。
- Oil/grug-far/help/health/ui2/终端/lazygit 容器统一；lazygit configure=false，不写 Neovim 生成的 CLI 主题。codediff/MiniDiff/multicursor/Flash/render-markdown 复用 palette。未改 aspects/cli。
- 第一阶段追加：动作图标采用固定显示宽度；RECENT 长路径保留最后两级；Explorer 标题持久；离开 dashboard/普通文件重新进入时恢复 cursorline/both；全窗当前行极淡底，缩进只保留当前作用域。
- 最后逐图复核发现普通终端/lazygit 被 Edgy 收进底部，现按窗口 relative 属性排除浮窗，保留原生居中边框和标题。Claude 替换行改用窗口局部红/绿淡底，`:diffoff` 恢复原样式，WinEnter 不重新污染非 diff 窗口；headless 回归及启动后的真实 RPC fixture 均覆盖 diffoff/重新进入/diffthis。
- 性能最终复核曾测得 tmux 首帧31.417ms（负载1.87/1.75/1.88），截图结束后独立复测30.502ms（负载0.66/1.30/1.69），未当作≤30通过。日志发现 UIEnter 仍同步加载完整 Heirline；改为首帧先绘制同样的 NORMAL dashboard / q退出原生状态栏，下一轮调度加载 Heirline，普通文档 FileType 仍同步。startup 回归检查空启动不加载 Heirline且首帧状态栏齐全；此前样本保留在 `startup-tmux-phase2-first-final/` 和 `before-firstframe-statusline/`，最终测量重新使用逐次新日志，避免旧日志追加影响就绪判定。

第二阶段截图→对比→修正至少三轮：初次检查发现完整路径/重复输入计数、AI窄栏、补全文档无边框；第二轮修正标题覆盖、原生 popup 创建时序、CC角色和提示；第三轮修正 grep 滚动、which-key 1字符宽度、dashboard cursorline 泄漏，并补跨页菜单检查。截图的 hover/消息/诊断/AI 对话是明确的本地内容 fixture，经真实原生 UI/API 渲染，没有网络请求、真实 CLI 回答或真实登录证明。Claude/Codex 终端只检查容器；独立 HTML 卡片、任意像素边线、混合字号仍受 TUI 单元格限制。

最终图片位于同一 ui5 目录，命名 `iter-final-<项>.png`；每张同时保留 ANSI、HTML、probe JSON。阶段1为 dashboard/editor；阶段2为 picker-files/picker-grep/explorer-search、ai-chat/ai-terminal/ai-diff、notifications、hover/signature/diagnostic-float、diagnostics/quickfix、whichkey、completion/completion-scroll，以及 oil/grug-far/health/markdown/terminal/lazygit/codediff/minidiff/multicursor/flash/ui2。

## 两阶段最终结果

- `git diff --check` 通过；工作树仍在 main，暂存区为空，flake.lock 未改。没有应用系统配置或更动用户历史/凭据。
- `nix fmt --no-write-lock-file` 通过。第一次全量构建停在 treefmt：未跟踪的 picker 新文件有一处多字段表未被工作树增量格式化覆盖；对整个 config 运行锁定同版 StyLua 2.5.2 后，重跑最终全量检查通过。失败日志 `all-checks-toplevel-phase2-attempt1.log` 保留。
- 过滤源码快照上的 `nix flake check --no-build --no-write-lock-file` 通过；既有未知输出 denful 提示不改变退出码。显式登记的全部26个 x86_64-linux checks、`neovim` 和 toplevel 以单一串行 `nix build --no-link --no-write-lock-file --max-jobs 1 --cores 4 --print-out-paths` 构建通过；不是只构建受影响子集。
- 包含新 panels_picker/panels_ai/panels_aux/panels_surface 测试：真实30文件/90行 grep 跨页、AI离线原生 chat/terminal、which-key实际渲染与四列位置、qf/loclist/CJK/标题转义、hover与通知renderer、inlay/标签/状态栏/Explorer边界。原生补全20项、上方菜单、第13项选中另由实际 TUI API fixture 断言；无按键模拟。
- 运行日志、源码白名单与哈希、脚本、命令目标列表和退出码均在 ui5；汇总 `verification-phase2.json`、`check-names-phase2-final.json`、`all-checks-toplevel-phase2-final.log`。等待其它工作树 Nix 时没有启动本任务构建；不终止别人的进程。

| 输出 | 最终 store 路径 |
|---|---|
| neovim check | `/nix/store/s32qh1rl21k4qfjni55wcncix5mnykcl-neovim-checks` |
| editing-composition | `/nix/store/8zi30yykv44afdh4kja25b7lfsw4a6ra-den-editing-composition` |
| 独立 neovim | `/nix/store/4c33n2kid8alrc75j2xmaispq4y669q1-neovim-0.12.4` |
| 实际 HM neovim | `/nix/store/0r40fw25bj9nr8wjn0x7l107z84qj7wb-neovim-0.12.4` |
| toplevel | `/nix/store/ar6igigcxpkdh1zqbx2k9h4kv35ml004-nixos-system-nixos-btw-26.05.20261021.da6dc0e` |

最终实际 HM 包测量：headless 新进程20次/预热5次，中位数 21.309ms（20.166–21.755ms）；200×52 tmux 首帧20次/预热3次，中位数 27.953ms（23.563–32.424ms）。两项中位数均≤30ms。四个真实最近文件/一个项目的隔离历史，保留OS/store缓存，没有清空页缓存；不包含终端模拟器字体栅格化。电源 balanced、ACAD online=1；headless负载 ['1.50', '1.33', '1.47'] → ['1.50', '1.33', '1.47']；tmux负载 ['1.50', '1.33', '1.47'] → ['1.38', '1.31', '1.46']。原始样本在 `startup-phase2/report.json` 与 `startup-tmux-phase2/report.json`。

最终28张图均用上表实际 HM 包重新拍摄，`live_config=false`，probe 的 error/load_error 为空；补全跨页、Explorer浮动搜索和 Claude diffoff 断言通过。图集 `iter-final-index.html`，清单/包路径/每张 PNG、HTML、ANSI SHA256 为 `iter-final-manifest.json`。最终构建后核对84个 Neovim 源文件哈希与快照一致；此后只补录本文中的结果。一次已被新源码取代的构建被主动中断，日志 `.superseded` 保留；不把中断当成功。

## 第二十二轮：真实 Kitty 全屏观感

本轮仅负责 Neovim、Kitty 与相关 shell 检查/文档；没有修改 GTK/Qt 主题或另一个 worktree。用户原始截图为 scratchpad `r22/9.png`、`10.png`。上一轮的 tmux→HTML 截图没有覆盖终端内边距与字符网格余数，本轮改用真正的 Kitty Wayland 客户端与 grim 截屏。

- Kitty padding 从12改为4 pt，字符网格靠左上，fractional-scale 余数条使用相邻单元格背景。Neovim 通过 `nvim_ui_send` 在 TUI 进入/配色切换时用 OSC 11 同步 Normal，查询并保留原终端背景；挂起/退出恢复，恢复运行重新同步。tmux 使用转义后的 `DCS tmux; … ST`；保留 `allow-passthrough on` 并增加运行时断言。无回答时回退 OSC 111；迟到查询回复仍保留原色。外部 GUI UI 与 headless 不发送控制序列。
- Explorer 40列、每层2列缩进，文件名按实际cell预算裁切，只有超宽才中间省略并保留扩展名；文件使用彩色 devicons。Dashboard最近文件、picker/grep标题、tabline、statusline同样恢复图标；Explorer聚焦时状态栏统一 `explorer`。
- Tab缩进不显示 `»`；保留行尾空白提示。colorizer 关闭命名颜色，只在Lua/Nix解析hex/rgb。诊断使用minimal预设、muted文字及与当前行相同的底色，无箭头/彩色方括号；gutter为小圆点。
- 第二轮真实截图揭示29条 `accessing undefined variable` 的实际来源是 **luacheck W113**，状态栏中的lua_ls不能证明诊断来源。LuaLS声明vim/Snacks并由lazydev按需提供插件库；luacheck只在store配置和仓库Neovim源码目录声明这两个运行时全局，普通Lua项目仍报告未知全局。测试对实际Lua源码等待LuaLS扫描完成，并用故意拼错的全局作为阳性对照；真实luacheck检查math_preview和普通项目。

隔离环境：独立HOME/XDG、`/tmp/nvim-r22-runtime-1000`、独立Wayland socket，`WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman`。Sway输出2560×1600、scale1.5，Kitty以fullscreen运行，使用构建出的HM Neovim包及HM Kitty配置；保留11pt Maple Mono NF CN。只通过Neovim RPC/API设置场景，未在用户Wayland会话开窗口、发送按键或重启服务。

截图、原始probe、隔离脚本及构建日志均位于 `/tmp/claude-1000/-home-mayon-nix-dotfiles/13f9340b-d643-4d3f-bd2f-97266d0e2965/scratchpad/r22/`。过滤快照只复制Git跟踪文件和显式新增的terminal.lua，清单与SHA256一并保存；没有用工作树 `path:.` 导入忽略目录或运行时秘密。

| 轮次 | 真实截图发现 | 修正 |
|---|---|---|
| 1，iter1 | 基线复现12pt外围框、文件无图标、深层截断、Tab箭头与29条警告 | padding/OSC同步、40列Explorer与文件图标、不可见Tab、minimal诊断与LuaLS配置 |
| 2，iter2 | picker自定义formatter仍无图标；29条警告实际来自luacheck；诊断仍有可见底块 | picker/grep显式图标、按配置源码范围注入luacheck全局、诊断muted与当前行同底 |
| 3，iter3 | 图标/误报修复生效；最长Explorer名称最后一字仍硬切，formatter少算原生leading space和statuscolumn的总占位 | 补齐两个保留cell，增加深层长文件名实际可视宽度断言，再用最终包重拍 |

最终性能核验额外发现：直接Kitty启动中位数43.393ms，tmux27.363ms，headless12.064ms；没有把直接Kitty结果当作≤30通过。锁定Neovim 0.12.4的`options.txt`（`ttyfast`/`NVIM_NOTTYFAST`）和`lua/vim/_core/defaults.lua`表明，配置前的OSC11+DSR探测会同步等待；实测日志该段独占25–32ms。wrapper因此仅对编辑器进程设置`NVIM_NOTTYFAST=1`，由已有固定dark/truecolor与异步OSC11接管，native Progress仍保留。tmux查询使用原生OSC11让回复路由回pane；设置/恢复颜色才使用DCS透传。先前样本完整保存在`startup-before-probe-fix/`，后续使用新wrapper重新测量。

最后进一步把`icons.ensure()`中附带的诊断初始化移到LSP入口，启动页取图标不再加载`vim.diagnostic`；LSP检查断言WARN标记仍为`•`。关闭同步探测后、尚未拆分图标/诊断的真实4条recent样本为Kitty30.779ms，保留在`startup-before-icon-split/`，没有将其当作通过。

最终实际HM包为 `/nix/store/bgi86x1nmdlcbil1cs0r0rq3wjnpi9qd-neovim-0.12.4`，toplevel为 `/nix/store/af3a4h4fkccarg2vg87sv8bzcvy9n2pj-nixos-system-nixos-btw-26.05.20261021.da6dc0e`。包内config与工作树运行源码逐文件一致；wrapper没有使用live config覆盖。

| 最终启动测量 | 20次中位数 | 范围 |
|---|---|---|
| headless新进程 | 12.204ms | 11.643–12.844ms |
| 真实Kitty内Neovim首帧 | 29.263ms | 18.996–41.035ms |
| 真实Kitty→tmux内Neovim首帧 | 26.467ms | 22.307–33.012ms |

每项另有5次预热。`--startuptime`取headless的NVIM STARTED、TUI的first screen update；不包含终端模拟器进程整体启动/字体栅格化耗时。最终脚本在VimEnter注入4条公开路径的内存历史，并逐次RPC确认recent、dashboard、devicons与无启动错误；不读取用户历史。早期Shada准备不能可靠提供这些记录，已改用可断言的内存fixture，不把早期空历史样本当最终成绩。保留OS/store缓存、未清页缓存；ACAD=1、platform_profile=performance，负载3.76/3.23/2.28→6.20/3.92/2.56。三个中位数均≤30ms，不能据此声称每个样本都≤30ms。原始日志与probe为`startup-final/report.json`及同目录逐次日志。

最终6张截图为`iter-final-{dashboard,editor,explorer,picker,diagnostic,tmux}.png`，图集`iter-final-index.html`、SHA256与包/配置清单`iter-final-manifest.json`。Sway输出mode确为2560×1600、scale1.5；逻辑高度取整为1066，grim原始PNG为2560×1599，没有补像素或缩放图片。Neovim实际为195×52，tmux保留一行自身状态栏后为195×51。图中的诊断是显式本地fixture，普通math_preview没有原29条误报；不宣称整个仓库其他Lua功能也无诊断。Maple Mono NF CN 7.9已核对Lua/Nix/Python/Markdown/目录字形覆盖及实际渲染，无需symbol_map补丁。

四份`lifecycle-complete-{direct,custom-direct,tmux-default,tmux-custom}.json`记录真实配色切换、挂起/恢复/退出：Neovim运行为#1e2228，默认shell恢复#181b20，自定义shell恢复#253341；tmux在隔离交互shell中停留约1秒再fg恢复。没有使用用户会话按键或进程。隔离Copilot未登录，不把状态栏提供者标识视为认证成功；没有提交模型请求。

验证：`git diff --check`、`nix fmt --no-write-lock-file`、过滤快照上的`nix flake check --no-build --no-write-lock-file`均通过；全部28个checks、独立Neovim、实际HM包与Kitty/tmux配置、toplevel通过同一条串行`nix build --impure --no-link --no-write-lock-file --print-out-paths --max-jobs 1 --cores 4 --expr …`。清单为`check-names.json`，完整参数/退出码为`verification.json`，输出路径在`all-checks-toplevel.log`。保留首次decorations断言误放入--clean LSP测试而失败的`build-iter3.log`；已移到完整UI测试，之后所有最终检查通过。已有未知flake输出denful提示仍不影响退出码。

未运行sudo、rebuild/test/switch、Git暂存/提交/推送或flake update；没有改用户数据、GTK/Qt主题或另一个worktree。共享main中其他代理的Firefox改动保留，不计入本轮实现。Mango实际激活后的窗口边距、日常字体观感与真实登录状态仍由用户后续应用配置后验收；本轮构建与无头图形验证不是已应用声明。
