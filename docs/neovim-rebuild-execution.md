# Neovim 重建与 Astra 工作台重设计

## 当前重构（2026-10-20）

用户再次要求完整重构、优化和美化，明确由 Astra 设计，参考社区配置，保留 One Dark Darker，并允许重做配置结构与交互。实际 Astra 查阅 LazyVim UI、AstroUI、NvChad base46 与 Noice 原始源码，给出完整方案；主代理组织实现与集成，Luna 负责组件，独立 reviewer 复核跨组件行为。下方 2026-10-18 的实现和应用记录作为历史保留，新状态以本节为准。

本次保持 Nix 固定插件和 parser，继续使用原生 Lua，不引入发行版或另一层插件下载器。功能边界保留：文件重命名/覆盖保护与回收站、会话与草稿、URL、公式唯一渲染器、LSP 按需库和项目 PATH、格式化/lint、Git/Diffview、Flash/多光标/文本对象、CodeCompanion DeepSeek 与 Codex/Grok CLI。OpenCode CLI 移除及 Quill Go 直连的在途改动保留，用户数据不随重构迁移或清理。

### 设计与实现

- 普通浮窗、补全、Noice、Snacks/Fzf 选择器、通知共用正文底色 `#1f2329`，边框与内容同底色；选择行统一中性 `#30363f`。蓝青用于前景与细指示，补全类别/来源不再带独立背景块。严重度仍以通知标题/图标颜色区分。
- 命令框移至底部居中，宽度随屏幕变化，上限 76 列；清除各格式默认标题，底栏搜索保留。针对锁定 Noice/NUI 的缓存视图同步几何，配置尚未初始化时的 resize 回调也有保护。
- Blink 关闭预选和自动插入：菜单出现不改正文，明确选择候选后再确认。原有 Tab/snippet、Ctrl-Space、文档与签名键保持；文档延迟 300ms。窄屏先去描述和来源，保留候选本身。
- Markdown 保留插入时整篇渲染，但光标行显露真实标记；Visual 使用源字符。标题不再铺整行彩色底，代码区用统一 surface，短代码块最小宽降为 20 列，公式仍由 Snacks/math-preview 单独负责。
- Picker 与 Explorer 均使用正文底色，以项目标题、树形、边界和中性选中行区分区域；使用 Snacks 原生窗口高亮，不增加窗口生命周期适配。普通选择器窄屏去预览，Explorer 极窄时使用浮层；Fzf 的预览也按窗口宽度降级。
- Heirline 状态栏和标签栏按 120/80/40 列分级，去掉行列胶囊；CJK 截断和 `%` 转义抽到 `ui/text.lua`。保留重名消歧、侧栏焦点下的活动文档、未保存/只读标记、录制和并发 AI 状态。路径消歧按缓冲区签名缓存，真实 buffer 列表保持即时查询。

社区参考只用于设计，字段与运行行为核对本仓库锁定版本：

- [LazyVim UI](https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/plugins/ui.lua)：按用途排列的状态信息与 Snacks 交互。
- [AstroUI](https://github.com/AstroNvim/astroui/blob/main/lua/astroui/config.lua)：主题覆盖集中管理与活动文件层级。
- [NvChad base46 Blink](https://github.com/NvChad/base46/blob/v3.0/lua/base46/integrations/blink.lua)：补全、文档、签名及类别前景的完整适配。
- [Noice views](https://github.com/folke/noice.nvim/blob/main/lua/noice/config/views.lua)：命令与搜索的视图边界；未直接照抄 main 的新 API。

### 本次验证与应用状态

重构前安装包在隔离 XDG 目录中 headless 启动三次为 76.339、74.092、74.955ms。这是 warm 文件缓存下的有限样本，不代表大型工程启动时间。重构后相同方式三次为 78.141、75.523、75.179ms；与原样本接近，不能宣称启动加速。

已通过 Neovim 专项、treefmt 与编辑器组合检查。新增检查覆盖 colorscheme 重载后的表面一致性、补全分段不遮住整行选中底色、CJK/字面 `%` 的宽度预算；40/60/80/100/160 列并发 AI、49 个错误和 50 个警告与未保存/只读标记同时出现的回归也通过。独立复核通过，无剩余阻断发现。

真实嵌入 UI 已检查 160/100/80/60/40 列命令框：旧配置在 60/40 列边框越界，新框均在窗口内，标题为空，底部位置稳定。真实 Kitty 临时文档已查看 Markdown、命令框、补全和 Explorer，Astra 实际查看四张最终截图并通过视觉验收。真实补全交互确认未选择时 Enter 换行，Tab 选择后 Enter 接受候选；Explorer 60→40→60 列切换、底色与选择行一致性和关闭清理检查通过。测试只使用临时中文文档，未打开个人工程或真实历史。

已执行 `sudo nixos-rebuild switch --flake .#nixos-btw`，成功应用 `/nix/store/j2ssn58y789ikkqc8y9qc4cydpljqqxr-nixos-system-nixos-btw-26.05.20261012.7993f34`。最终 flake 求值、Neovim/treefmt/编辑器组合检查构建与主机 toplevel 构建均通过。Home Manager 的 Result 为 success；安装后的 Lua 与工作树源码一致，隔离启动的正文/浮窗底色、选择行、CodeCompanion DeepSeek 与 Codex/Grok 入口及实际补全交互验证通过。

OpenCode 两个命令已从新环境移除；Quill 持久声明为 Go 直连，旧三项运行时覆盖已对账清除，运行时 API Key 保留。Noctalia 随 Home Manager 正常重启；Mango 与原有终端继续运行。未清除历史、项目或模型，未关闭用户编辑器；已打开的旧编辑器需用户保存后重新启动才加载新包。未声称已验证个人大型工程性能或 Quill 的完整 GUI 模型交互。

## 2026-10-18 基线与历史

日期：2026-10-18。用户提供 Markdown 实机截图，指出当前实现相较最初 Nixvim 有多处问题，
明确要求推翻重做并按原效果配置。该要求覆盖之前“仅手写替代、不要恢复插件”的历史取舍。
本轮以 Git 中实际 `a9d5614:nixvim/` 为布局、组件和交互参考，不把迁移文档的功能对等描述
当作证据。用户再次确认：主题继续采用当前 One Dark Darker（`#1f2329`），旧 Nixvim 的
TokyoNight 只属于历史；不恢复其主题选择器或主题 state。

可回退起点为干净提交 `051579e`（已同步 origin/main）。保留现有 undo、会话、草稿、AI
历史、项目、凭据及其他用户状态；不关闭用户现有编辑器、不影响 mod 任务。不改其他桌面
功能、不升级无关输入。继续沿用 Nix 固定依赖、Den 语言/palette 贡献与唯一配置入口。

原生多代理：Luna 并行核验历史和当前缺陷、恢复明确范围的编辑选项；实际 Astra 以原基准和社区源码
重新设计界面组件；主代理负责插件/入口/交互/检查集成，跨模块由独立 reviewer 复核。

## 已核实的回归

原 `nixvim/options.nix` 未禁用默认折行；当前全局 `wrap=false` 由后续提交 `1c46de6` 引入，
造成截图长段落右侧裁切。空 `[No Name]` 标签来自自写文件模块生成的 listed 空缓冲与标签
模块直接列出它的组合；不能以 parser/headless 检查通过宣称实际界面没有问题。

## 当前实现

用户随后要求超出原样恢复，允许完整重新设计。实际 Astra 完成了新 OneDark 工作台：深色侧栏和浮层、蓝青强调、与实际侧栏宽度对齐的页签、当前/可见/后台三级文件状态、小面积模式提示、紧凑 LSP 状态和右侧位置胶囊。默认侧栏 38 列，调整宽度后项目区也会跟随；空占位不显示，未保存文件继续可见。Markdown 保留正文折行，蓝/青标题、轻量代码区与表格；Visual 模式显示源字符。补全采用图标/名称/来源三列，去掉重复类型，最多九项，文档窗限制为 60×18。

实际查阅并采用的社区设计依据：

- [NvChad tabufline](https://github.com/NvChad/ui/blob/v3.0/lua/nvchad/tabufline/modules.lua) 的侧栏偏移关系；
- [LazyVim UI](https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/plugins/ui.lua) 的 Snacks 布局与 buffer 操作；
- [AstroUI Heirline](https://github.com/AstroNvim/AstroUI/blob/main/lua/astroui/status/heirline.lua) 的文件状态层级；
- [lazydev.nvim](https://github.com/folke/lazydev.nvim) 的 Lua 按需工作区库和 Blink 模块补全。

社区当前源码只作为设计参考，最终 API 按本仓库锁定的插件源码核对；没有引入发行版、运行时插件下载或另一套主题。插件与 parser 继续由 Nix 固定，保留 Den 语言贡献、项目 PATH 和普通/开发两个 wrapper。

移除自写的四个大型 UI/文件/图片实现，接入 Snacks、Heirline、Navic、完整 onedark.nvim、render-markdown 和 Trouble。保留独立的小功能：同目录草稿、会话保护、URL、公式浮窗、C++ snippets、AI 历史及原有格式化/LSP。PDF 继续外开；公式触发器和自动图像渲染不重复认领内容。普通 LSP 进度进入状态栏，警告与错误仍可见。

核对锁定 Snacks 2.31 源码后增加必要的文件操作适配：重命名不强制删除修改中的 buffer、不覆盖已有目标/符号链接/已打开目标；重命名后首存校验外部变化，并交由原生 write 执行一次保存钩子，保存失败会阻止 `:wq`。目录删除检查所有已打开子文件；缺少或执行失败的回收站命令一律保留文件，没有永久删除回退。

LuaLS 原配置将全部 runtimepath 加入每个工作区，现改用锁定 lazydev 1.10 按 `require` 逐步加载；关闭其会覆盖 root_dir 的默认 lspconfig 集成，保留原生根探测。项目及祖先目录有 `.luarc.json` / `.luarc.jsonc` 或全局禁用时不注入。此修改针对扫描范围，不把隐藏进度等同于性能提升，也不宣称所有项目的耗时已测量。

## 验证与应用

已完成以下验证，均使用当前锁定输入，没有改动 `flake.lock`：

- 全仓 `nix flake check --no-write-lock-file --max-jobs 1 --cores 2` 成功，当前 x86_64-linux 的 17 项检查通过；其他平台不因此视为构建或部署成功。
- `checks.neovim` 实际执行完整配置启动、SQLite、Blink C++ snippet 加载/展开/跳转、Lua 模块候选、StyLua 格式化、Unicode/宽度/侧栏/buffer 保护、真实 CSSLS 诊断和真实 LuaLS 按需库/项目排除；runner 的故意失败用例确认断言会令构建失败。
- 文件操作检查包括重命名后普通保存、钩子各执行一次、钩子失败和外部改写时 `:wq` 不退出、符号链接/目标 buffer 冲突、目录子文件及真实 Explorer 删除调用链保护。
- reduced-motion、普通和开发 wrapper 分支通过；大文件禁用 completion/Tree-sitter/fold 的边界通过。上述均为隔离临时目录，没有使用个人工程或真实历史做 fixture。
- 独立 reviewer 复核跨模块接线、文件安全、失败退出、LuaLS 根探测和补全源继承，未发现最终阻断。

Astra 已只读检查真实 Kitty 测试窗口的长中文 Markdown、表格、标题、侧栏聚焦与页签对齐。行末偶见的 `>` 是 Neovim 宽字符剩余一格时的原生提示，完整字符移到下一行，不是截断丢字；已核对实际 wrap/listchars 和 [Neovim v0.12.4 drawline.c](https://github.com/neovim/neovim/blob/v0.12.4/src/nvim/drawline.c#L2041)。

真实 Kitty 公式 smoke 另使用临时 Markdown：`\frac{1}{s} + x^2` 完成 pdflatex→PDF→PNG 并实际显示，普通公式采用 brightFg；`\badcommand{x}` 显示 LaTeX 错误浮窗，没有静默展示残缺图片。中文/Markdown、补全和公式截图分别保留于本机临时路径 `/tmp/codex-nvim-community-final.png`、`/tmp/codex-nvim-completion-final.png`、`/tmp/codex-nvim-math-neutral.png`，它们不是长期归档资源。

最后公式颜色与说明调整后，重新构建 `checks.neovim`、`checks.treefmt`、`checks.editing-composition` 和真实主机 toplevel，全部成功。完整系统产物为 `/nix/store/39ny1hnzlzdi18w2km7rha2qqnjr28rr-nixos-system-nixos-btw-26.05.20261012.7993f34`。应用前比较 greetd、NetworkManager、nix-daemon unit 均与旧系统相同。随后按既有自主应用授权执行 `sudo nixos-rebuild switch --flake /home/mayon/nix-dotfiles#nixos-btw --no-write-lock-file --max-jobs 1 --cores 2`，退出码 0；`/run/current-system` 与上述构建产物一致，`home-manager-mayon.service` 为 active / Result=success / ExecMainStatus=0。

应用前保存进程 PID 与内核 starttime，应用后 12/12 均保持相同身份：5 个 Java、3 个 Codex、1 个 Mango、3 个终端。Noctalia、Fcitx、Mango target、greetd、NetworkManager、nix-daemon 的状态及相关 MainPID 与应用前相同；另核对真实 `clipboard-bridge.service` active。没有杀 mod 进程、注销、重启桌面或重启机器。新安装普通 Neovim 在临时 HOME/XDG 中冷启动，通过 OneDark 背景、lazydev 原生根探测接线和真实 Blink provider 加载检查；此检查经仓库 runner 失败退出，避免 `:qa!` 吞掉错误。已运行的用户 Neovim 不强制重载，重新打开编辑器才能使用新插件布局。

全仓与专项构建日志、nr 日志分别位于本机 `/tmp/codex-nvim-final-flake-check.log`、`/tmp/codex-nvim-final-host.log`、`/tmp/codex-nvim-rebuild-switch.log`；临时运行元数据不入仓。文档相对链接和 `git diff --check` 通过，最终文档再经 treefmt 检查后本地提交。

可回退提交按语义保存：`8291bb0` 记录基准、`ceb06bf` 恢复完整功能、`37a7d85` 修复保存钩子、`d9caca6` 落实 Astra 新布局、`b1b176a` 按需 Lua 库及补全、`82bb691` 公式配色。旧系统 `/nix/store/yfp33chaag8955n5rlfwk2jq5850anf1-nixos-system-nixos-btw-26.05.20261012.7993f34` 与 NixOS generation 保留，不执行清理。

Java 大项目、AI 联网、其他图片/媒体格式、tmux 内图片以及多屏尺寸仍需分别验收；未取得证据的项目不会标为完成。headless 及小 fixture 不代表所有个人工程性能，最终观感由用户验收。
