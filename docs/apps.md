---
summary: 已安装软件的去留决定、理由和备选方案
read_when: 想新增、替换或删除软件之前
code: [aspects/default.nix, aspects/apps]
checks: []
---

# 保留应用逐项评估与补充候选

软件取舍记录，首次核对于 2026-10-18，之后逐项更新；具体日期以 Git 历史为准。依据是源码、`flake.lock` 与官方文档，未做应用间性能基准。自写工具的去留见 [tools.md](tools.md)。

## 建议先看这些

| 优先级 | 项目 | 建议与条件 |
|---|---|---|
| 高 | 数据备份 | 若没有仓库之外的备份，先设计 Restic；本地/SSH 且偏好 GUI 可比较 Borg + Vorta。选一套，不叠加多个引擎。 |
| 高 | 密码管理 | 若尚无统一密码库，选 KeePassXC 或 Bitwarden；已有外部方案则接入即可。 |
| 高 | Zotero Connector | 已使用 Zotero 和 Firefox，适合补齐浏览器论文/网页采集；先核对是否已经手动安装。 |
| 已定归档 | File Roller | GTK4 归档 GUI，Thunar TAP 固定其可执行路径；替换旧 Xarchiver。 |
| 已移除 | Okular | 用户决定不安装；PDF 默认 Zathura，PDF 批注使用 Zotero 内置阅读器。 |
| 已修改 | `cliphist` | 删除两个 watcher，日常历史统一使用 Noctalia；保留旧数据库和 X11↔Wayland 剪贴板桥。 |
| 已修改 | `pamixer` | 移除无消费者的安装声明；音量键继续走 Noctalia。 |
| 已修改 | `pavucontrol` | 移除安装声明与浮窗规则；Noctalia 覆盖日常混音，高级声卡 profile/端口操作使用已有 wpctl/pw-cli。 |
| 已修改 | Discord → Vesktop | 用户确认替换；使用 stable 包及系统 Vencord，Wayland/PipeWire 接线已构建，实际分享待验。 |
| 按需 | 跨设备同步、远程开发 | 有第二台设备/服务器后，再选 Syncthing、Remote-SSH、Tailscale；不提前把所有服务打开。 |

固定方向继续沿用：Mango + Noctalia、Kitty + tmux、One Dark、原生 Lua + Nix 管理 Neovim 插件、混合工具链、Den 实体与绑定。本文不重新打开这些选择。

## 日用桌面

仓库入口：[应用清单](../aspects/default.nix)、[应用模块](../aspects/)、[MIME 与图片配置](../aspects/apps/media/images.nix)、[Mango 配置](../aspects/desktop/mango-session/mango.nix)。

| 应用 | 判断 | 更优解、收益和代价 |
|---|---|---|
| Firefox | 保留 | 已有 Dark Reader、受管深色主题和界面接线。后续统一 One Dark；没有证据支持为优化而换浏览器。迁移会重做扩展、登录和界面。 |
| QQ | 保留当前包与 wrapper | PipeWire、Wayland、输入法及桌面入口已有处理。官方 Linux 包仍维护，但换包装不等于解决当前 Nix 兼容问题。 |
| 微信 Linux | 已替换 UOS | 使用 unstable 官方版 4.1.13.26；按锁定 AppImage/FHS wrapper 保留官方后端探测，登录、中文输入及剪贴板待实机回归。旧数据保留。 |
| Vesktop | 已替换 Discord | 用户确认使用系统 Vencord；锁定包包含 PipeWire/venmic，Wayland wrapper 跟随会话环境。实际音频与屏幕分享仍待验证，Discord 数据保留。 |
| 原生 mayon-clash | 保留 | Mihomo service + TUN 覆盖整机应用，TUI 管理订阅、节点和设置。 |
| Thunar | 保留 | GUI 拖放、GVFS、缩略图及自定义菜单有独立价值。换 Dolphin 要迁移菜单、快捷键、终端及 MIME，未发现足够收益。 |
| Yazi | 保留 | 终端文件管理、Git/文档预览和 Kitty 图像与 Thunar 互补。换 lf/ranger 要重写插件与预览，不是现成精简。 |
| Swayimg | 保留，完善现有配置 | 锁定版本是 **4.7、INI 配置**，已有 gallery、动画及多格式支持。不要直接套主线新版 Lua；可在当前版本内调整缩放、背景、导航和 MIME。 |
| mpv | 保留 | 现有 Anime4K、Vulkan、NVDEC、字幕和播放脚本值得保留。更有价值的是按内容/电池状态使用不同播放 profile，避免始终启用高成本 shader；收益需实测。 |
| mark-shot | 保留 | 框选、注释、置顶以及 Mango 窗口检测已有接线。Noctalia 可承接简单截图，但不证明完整等价。 |
| wayscrollshot | 保留 | 专职滚动拼接。锁定 mark-shot 仍将非 niri 滚动截图列为不完整测试功能，不能据其功能表直接删除本项。 |
| Tesseract OCR | 保留 | 现有中英 OCR 是独立功能；Noctalia 截图能力不能自动替代语言数据与识别流程。 |
| Noctalia 剪贴板历史 | 保留，作为日常入口 | 当前锁定的 5.2.1 已有独立、加密持久化的历史，Super+V 已使用此界面。 |
| cliphist | 已修改：移除 | 用户确认精简后删除两个 watcher 及其包引用。Noctalia 使用独立历史，不迁移/删除原 cliphist 数据。 |
| X11↔Wayland 剪贴板桥 | 保留 | 解决跨协议同步，和历史界面职责不同；QQ/微信图像粘贴链路仍需回归。 |
| Fastfetch | 保留 | 终端快照，不与实时监视器等价；若以后发现启动拖慢，再测量并改成显式 `ff`，当前不假定存在延迟问题。 |
| btop | 保留 | 进程选择、资源排序和结束进程不同于 Noctalia 的资源概览；暂不另加 Mission Center。 |
| pamixer | 已修改：移除 | 仓库无命令消费者，删除安装声明；音量键仍直接使用 Noctalia IPC。 |
| pavucontrol | 已修改：移除 | 已核对锁定源码的设备、音量和应用输出路由；移除安装声明及浮窗规则。Noctalia 未提供等价的硬件 card profile 菜单，高级操作改用 wpctl/pw-cli，命令见 README。 |
| brightnessctl | 保留 | 笔记本背光命令后端，不因面板有亮度滑块就视为重复。 |
| ddcutil | 保留 | 外接显示器 DDC/CI 后端，与笔记本背光不同。无支持设备时不会凭空带来功能。 |
| playerctl | 保留 | MPRIS 媒体控制接线，不是另一个播放器。 |
| Lenovo Legion 工具 | 保留主机专属 | 面向该笔记本；后续放入 host 硬件能力，服务器不继承。不能仅凭包名判断硬件功能已生效。 |

资料：[Mozilla 定制](https://support.mozilla.org/en-US/kb/firefox-advanced-customization-and-configuration)、[QQ Linux](https://im.qq.com/linuxqq/index.shtml)、[Discord 分享限制](https://support.discord.com/hc/en-us/articles/360040816151-Go-Live-and-Screen-Share)、[Vesktop 排障](https://vesktop.dev/wiki/linux/troubleshooting/)、[Mihomo TUN](https://wiki.metacubex.one/config/inbound/tun/)、[Yazi](https://yazi-rs.github.io/docs/configuration/yazi/)、[Swayimg v4.7](https://github.com/artemsen/swayimg/blob/v4.7/README.md)、[mpv 手册](https://mpv.io/manual/stable/)、[btop](https://github.com/aristocratos/btop)。

版本证据：[锁定 Noctalia 的 clipboard 配置说明](https://raw.githubusercontent.com/noctalia-dev/noctalia-shell/5f864d472676c77e5310881b243f15cc371bb223/docs/user/configuration/shell.mdx)、[锁定 mark-shot](https://raw.githubusercontent.com/jswysnemc/mark-shot/fd481ed87902a26600b872ed33a9e951dd637423/README.md)、[锁定 wayscrollshot](https://raw.githubusercontent.com/jswysnemc/wayscrollshot/703474ad7b94a504306d7a93d21668ee162ebf1c/README.md)、[Noctalia Audio](https://docs.noctalia.dev/noctalia/control-center/)。音频文档的控件范围不能代替本机面板验证。

社区边界：[Vesktop Wayland 分享 issue #1207](https://github.com/Vencord/Vesktop/issues/1207) 是需要验证 Portal 行为的具体案例，不是当前机器必然故障的证明。

## 创作、办公、笔记与阅读

入口：[应用清单](../aspects/default.nix)、[Blender](../aspects/apps/media/blender.nix)、[OBS](../aspects/apps/media/obs-studio.nix)、[LibreOffice](../aspects/apps/documents/default.nix)、[Thunderbird](../aspects/apps/communication/thunderbird.nix)、[Zathura](../aspects/apps/documents/zathura.nix)、[Musicfox](../aspects/apps/media/musicfox.nix)。

| 应用 | 判断 | 更优解、收益和代价 |
|---|---|---|
| Blender | 保留 | 通用 3D 创作没有直接等价的轻量替代。Cycles CUDA/OptiX 选择应结合实际 GPU/显存测试，不能把 NVIDIA 存在当成最佳后端已配置。 |
| GIMP | 保留 | 通用位图编辑；Krita 更偏绘画，darktable 偏 RAW，不是等价替代。没有 RAW 工作流就无需额外补照片软件。 |
| OBS Studio | 保留，比较捕获源 | 已配 wlrobs 与 obs-vkcapture。可在 Mango 上比较原生 PipeWire 与 wlrobs 的画面、帧率和卡顿，再决定是否移除插件；游戏捕获也需单独验证。 |
| Kdenlive | 暂留，用户考虑中 | 如果没有剪辑需求，删除比换另一套剪辑软件更合理。若只是裁剪/转码，可先用现有 FFmpeg；要时间线编辑则保留。Resolve 不是更轻更省事的默认替代。 |
| Thunderbird | 保留 | 邮件、日历、联系人集中入口；网页邮箱会改变离线和多账户流程，没有明确替换收益。 |
| LibreOffice | 保留，统一处理 Office 格式 | DOC/DOCX、XLS/XLSX、PPT/PPTX 与 ODT/ODS/ODP 均由 LibreOffice 默认打开，分别使用 Writer、Calc、Impress。复杂文档仍应使用真实文件检查排版，不凭格式支持宣称兼容性普遍更好。 |
| Zotero | 保留，优先补 Connector | 文献库和论文注释已有一体化流程；浏览器扩展可减少手动录入。不要用普通文件同步器同步正在使用的数据目录。 |
| Obsidian | 保留 | 本地 Markdown 知识库、链接和检索有明确角色；无需为减少应用数量直接并入单文档编辑器。 |
| Typora | 已移除声明 | 用户确认删除包与受管主题；Markdown 默认 Obsidian，CLI 编辑仍遵循 default-tools。Typora 配置、文档与历史保留。 |
| Zathura | 保留 | 键盘式 PDF 阅读与 SyncTeX；PDF 批注使用 Zotero 内置阅读器。若另有手写批注需求，再评估 Xournal++，不安装 Okular。 |
| Quill | 保留 | 面板快记、todo 与主笔记库分工。先明确哪些内容应长期进入 Obsidian，避免同一事项在两处维护。 |
| Musicfox | 保留 | 网易云终端入口；不承担通用本地音乐库，无需因为已有 mpv 就删除。 |
| FFmpeg | 保留 | 视频/音频转换、截取和工作流后端；OBS 自带库不等于 shell 有可用命令。 |
| ImageMagick | 保留 | Thunar 图片动作及编辑器 PDF/图像处理有消费者；不要因存在 GIMP 就删命令行图像后端。 |

资料：[Blender GPU](https://docs.blender.org/manual/en/5.0/render/cycles/gpu_rendering.html)、[OBS 捕获源](https://obsproject.com/kb/display-capture-sources)、[wlrobs](https://github.com/zsien-debian-repo/wlrobs)、[Kdenlive](https://apps.kde.org/kdenlive/)、[Thunderbird](https://www.thunderbird.net/en-GB/)、[LibreOffice 格式](https://help.libreoffice.org/latest/ug/text/shared/guide/ms_user.html)、[Zotero Connector](https://www.zotero.org/support/connector)、[Typora](https://support.typora.io/Quick-Start/)。

## 编辑器、终端与 Git

入口：[JetBrains](../aspects/dev/jetbrains/jetbrains.nix)、[VSCode](../aspects/dev/vscode/vscode.nix)、[Neovim](../aspects/dev/neovim/default.nix)、[Kitty](../aspects/cli/terminal/kitty.nix)、[tmux](../aspects/cli/shell/tmux.nix)、[Git](../aspects/cli/shell/git.nix)、[Shell](../aspects/cli/shell/zsh.nix)。

| 项目 | 判断 | 更优解、收益和代价 |
|---|---|---|
| IntelliJ IDEA | 保留 | JVM 主 IDE；可以覆盖部分其他语言，但插件和订阅决定完整能力，不据“一套 IDE”口号重新扩装。 |
| PyCharm | 保留；可选合并入口 | IDEA 官方有 Python 插件。只有现有许可、插件和 Python 工作流都满足时，才值得试把 PyCharm 项目放入 IDEA；会改变独立设置与窗口习惯。用户已确认常用，本轮不删。 |
| CLion | 保留 | C/C++ 项目模型、调试与嵌入式支持不是 clangd 的等价功能；无需额外安装 DataGrip 才能获得全部基础数据库入口，具体能力看 IDE 功能和许可。 |
| VSCode FHS | 保留 | 为扩展附带的二进制和 USB/调试库提供兼容环境。改普通包会重新承担逐个扩展追依赖的工作。Remote-SSH 是否已手动安装需核对。 |
| Neovim | 已迁移到原生 Lua + Nix 包 | `aspects/dev/neovim/config/` 承载配置，`aspects/dev/neovim/` 固定插件/parser 和 wrapper；保留插件由 Nix 提供，不使用在线插件管理器。专项包检查已通过；见[迁移计划](history/neovim-migration-plan.md)了解尚待核验项目。没有性能比较结论。 |
| colorizer | 已改原生 | 移除外部插件，使用内建 LSP documentColor 和 `<leader>uc` 当前 buffer 开关；不再独立扫描无相关 LSP 的文件/Tailwind 类名，没有新写 CSS 解析器。 |
| vim-matchup | 已改原生 | 移除外部插件，使用内建 matchit/matchparen；不保留 matchup 离屏 popup、专有 surround/transmute，独立 nvim-surround 保留。 |
| Heirline | 已恢复固定插件 | 按旧 Nixvim 效果参考重建状态栏、标签和宽度收缩，保留同名消歧、未保存保护和 LSP/Git/AI 状态，主题保持 OneDark。 |
| Kitty | 保留 | 图形协议、Yazi/Snacks Neovim 图片预览和主题已有接线；服务器终端可用 `kitten ssh` 处理 terminfo，不需换整个终端。 |
| tmux | 保留 | 会话持久化和远程复用。passthrough 用于图像；后续按实际终端能力核对宽泛 overrides，而非直接关闭造成预览退化。 |
| tmuxp | 保留 | 项目工作台的会话布局工具；`workspace-project PROJECT workspace` 用它创建或复用编辑器加两个 shell 的 tmux 会话。tmux server 负责会话持久化。 |
| Git | 保留 | 基础版本控制和 diff3 冲突上下文；现有编辑器/IDE 已有差异工具，不再默认添加另一个 diff GUI。 |
| GitHub CLI（gh） | 保留 | PR、仓库等 GitHub 操作；与本地 Git 分工。只有不使用这些命令时才有删的理由。 |
| lazygit | 保留 | 交互暂存、提交和 rebase；`lg` 已接线，和 gh 分工不同。 |
| delta | 保留 | diff pager，不是另一个完整 Git 客户端；删除会简化显示而非删除 Git 能力。 |
| direnv / nix-direnv | 保留 | 自动加载用户自己的项目 flake，缓存进入环境的工作。首次下载仍取决于项目依赖及缓存，不承诺首次进入零等待。 |
| nix-index / comma | 保留 | 文件/命令所属包查询及临时运行共享同一数据库。不能只删数据库却保留依赖它的 command-not-found/comma 接线。 |
| nh / nix-output-monitor | 保留 | 重建、清理与构建展示已有 `nr`/`nc` 工作流；不需再堆一套 Nix 管理前端。 |
| Zsh / 自动建议 / 语法高亮 | 保留 | 属于当前交互体验；迁移 Fish 会重做 shell 函数和脚本习惯，未见足够收益。 |
| Starship | 保留，统一主题 | 原生 Zsh prompt 可以重写当前信息布局，但会把现成模块维护转为自维护；用户选择精致丰富，暂不为删包重做。 |
| fzf | 保留 | 历史、文件和目录选择器已有接线。 |
| fzf-tab | 保留 | 服务 Zsh 补全菜单，不等于 fzf 历史搜索；删后会退回普通补全。 |
| zoxide | 保留 | 按使用习惯跳目录，与 fzf 选择目录互补。 |

资料：[IDEA Python](https://www.jetbrains.com/help/idea/python.html)、[IDEA 统一发行](https://blog.jetbrains.com/idea/2025/07/intellij-idea-unified-distribution-plan/)、[PyCharm 版本](https://www.jetbrains.com/pycharm/editions/)、[CLion 嵌入式](https://www.jetbrains.com/help/clion/embedded-overview.html)、[CLion 数据库工具](https://www.jetbrains.com/clion/features/terminal.html)、[VSCode Remote-SSH](https://code.visualstudio.com/docs/remote/ssh)、[matchup](https://github.com/andymass/vim-matchup)、[Heirline](https://github.com/rebelot/heirline.nvim)、[Kitty FAQ](https://sw.kovidgoyal.net/kitty/faq/)、[tmux FAQ](https://github.com/tmux/tmux/wiki/FAQ)、[lazygit](https://github.com/jesseduffield/lazygit)、[delta](https://dandavison.github.io/delta/features.html)、[comma](https://github.com/nix-community/comma)。IDEA 2026.2 文档代表当前上游能力，不能证明本机的订阅、插件及实际功能已经就绪。

## AI 应用与编辑器集成

入口：[AI agents](../aspects/dev/ai-agents/ai-agents.nix)、[Grok Bot](../aspects/dev/ai-agents/grok-bot.nix)、[DSH 包装](../aspects/dev/ai-agents/dsh-desktop.nix)、[CodeCompanion](../aspects/dev/neovim/config/lua/mayon/plugins/ai.lua)。2026-10-20 用户决定删除 OpenCode；Codex、Grok Build、DeepSeek Harness、Grok Bot 和 CodeCompanion 继续保留。配置更新已于 2026-10-20 应用，Home Manager 返回 success，OpenCode 命令已从新环境移除。

2026-10-22：新增 Claude Code 2.1.299，主机 toplevel 与 treefmt 检查构建通过，系统 switch 成功；新 shell 的 `claude --version` 验证通过。程序由 Nix 管理，未修改既有登录、设置或会话，也未发起模型请求。

| 项目 | 当前定位与建议 | 代价或边界 |
|---|---|---|
| Codex | 本地仓库编码主入口候选；原生 CLI、审查、会话和工具集成 | 使用现有原生子代理/MCP 客户端，避免另包一层 `codex exec` 委托脚本。选主力看实际项目体验，不凭模型宣传排名。 |
| Claude Code | 用户于 2026-10-22 要求安装；通过锁定的 llm-agents 输入提供 `claude` | Nix 管理程序版本，登录、设置与会话历史归用户；在项目目录执行 `claude`，按提示完成账号登录。 |
| Grok Build | 保留为本地 TUI/脚本式编码工具 | 可承担备用或交叉核验任务；不要和 Grok Bot 云端电脑混为一项。 |
| OpenCode | 用户于 2026-10-20 决定删除 | 包、命令兼容 wrapper、CodeCompanion CLI 入口和 Quill 的 CLI 调用已从配置移除；Quill AI 改为直接调用 Go。已应用并核验运行时覆盖，保留其他应用及用户数据。 |
| DeepSeek Harness 桌面入口 | 保留为实验性图形入口 | 当前是官方 Web UI + Chromium 应用窗口和私有后端，不是官方 Linux Electron 安装包。预览版变化与自维护包装有成本，不引入同名第三方桌面客户端。 |
| Grok Bot | 保留，承担云端持续任务/流程 | 云端电脑可在本机关闭后继续工作；资格/账户和网络依赖不同于本地 CLI。不是本地终端复用器。当前 Electron workaround 另见使用文档，不能随意删除。 |
| CodeCompanion | 保留 | Nvim 内联/聊天/选区上下文有独立价值；聊天默认 DeepSeek，CLI agent 清单保留 Codex 和 Grok。原生 Lua 配置保留现有历史和快捷键；插件由 `aspects/dev/neovim/plugins.nix` 固定提供。 |
| MCPHub | 用户最新确认删除 | 编辑器面板、CodeCompanion 扩展、专用输入与二次 nixpkgs 接线移除；各 agent 的独立 MCP 设置保留。 |

当前保留的本地编码入口是 Codex、Claude Code、DSH headless 与 Grok Build，图形和云端入口按需打开。进程数、模型费用和实际速度取决于使用方式，单纯安装多个 CLI 不等于全部常驻。各工具的账号/密钥及运行时状态不强制合并进 Nix。

资料：[Codex CLI](https://learn.chatgpt.com/docs/codex/cli)、[Codex MCP 客户端](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)、[Grok Build](https://docs.x.ai/build/overview)、[DeepSeek Harness 官方仓库](https://github.com/deepseek-ai/deepseek-harness)、[Grok Bot 入门](https://docs.x.ai/grok-bot/get-started)、[Grok Bot FAQ](https://docs.x.ai/grok-bot/faq)。本仓库的 [Grok Bot 说明](grok-bot.md)记录当前包装限制。

## 语言工具链、工程与虚拟化

入口：[工具链模块](../aspects/)、[共享版本](../aspects/dev/languages/toolchains.nix)、[Java 版本](../lib/java.nix)、[开发 shell](../nix/dev.nix)、[Docker](../aspects/dev/containers/host.nix)、[libvirt](../aspects/dev/virtual-machines/host.nix)。同组中的工具分别说明，相关安装可按项目长期使用情况再收敛。

| 工具 | 判断与更优解 |
|---|---|
| Clang / LLD | 保留全局常用 C/C++ 编译与链接；项目 flake 可覆盖版本。与 clangd 编辑功能不同。 |
| CMake / Ninja / pkg-config / GNU Make | 保留。项目配置、执行构建和查库分工不同；不因 CLion 存在就删编译工具。 |
| 主机 GDB | 保留原生调试；不是 Cortex-M 交叉 GDB 的替代。 |
| Python 3 | 已简化为基础解释器；项目库留给 uv/项目环境，不恢复全局 IPython 大集合。 |
| uv | 保留，负责 Python 项目依赖/虚拟环境；不替代 flake 的系统库和编译器环境。 |
| Lua 5.4 | 保留轻量脚本入口；LuaLS/格式化等独立维护。Neovim 内嵌 LuaJIT 不要求恢复独立 LuaJIT/LuaRocks。 |
| Node.js | 保留现有脚本/开发入口；编辑器服务自己的依赖不能仅看 shell 的 node 来判断重复。项目仍可固定其他版本。 |
| JDK 8/17/21/25/26 | 已确认全部保留，Prism 与开发共用，默认 25。IDE 自带启动运行时和项目目标 JDK 不等价；不凭 IDEA 自带 JBR 就删这些版本。 |
| TeX Live Full | 用户编译完整文档，保留。项目固定小集合更可控但会持续补包，当前不接受以公式预览用途代替实际文档需求。 |
| Ghostscript | 保留，普通 PDF/文档转换仍有用途；公式预览已通过 Snacks 恢复，渲染与错误提示仍需分别验收。 |
| 编辑器 LSP | 保留按现有语言使用的 bash、clangd、CMake、Docker、Java、Lua、Markdown、MATLAB、Nix、Python、TeX、TS/HTML/CSS/JSON/YAML 服务；迁移时验证启动及项目根识别。 |
| 格式化与检查 | 保留 clang-format、google-java-format、nixfmt、shfmt、stylua、luacheck、ruff、shellcheck；它们与完整 IDE 并非所有调用方都相同。暂不为统一品牌换一整套。 |
| trash-cli | 保留，Neovim 文件树的安全适配需要回收站命令；不是无消费者的杂项。 |
| MATLAB | 保留课程/工具箱/Simulink 工作流；Python 科学计算和 Octave 都不是保证等价的替代，且 Octave 已确认删除。 |
| CUDA toolkit / cuDNN | 继续放 `.#cuda`，不迁入全局。重复 nvcc 声明已经精简，不把共享闭包去重说成额外释放空间。 |
| ARM GCC / 交叉 GDB | 保留 STM32 编译调试；与主机 Clang/GDB 分工。 |
| OpenOCD | 保留通用探针与 GDB server。 |
| stlink | 保留 ST-Link 专用的简短烧录/诊断入口；实际长期不用时再按探针选择精简。 |
| probe-rs | 保留按芯片选择、RTT 等流程；不是所有目标/探针都能替代 OpenOCD。 |
| dfu-util | 保留 USB DFU 引导加载路径。 |
| stm32flash | 保留 UART 引导加载路径，与 DFU 不同。 |
| STM32CubeMX | 保留时钟、引脚和 HAL 工程生成。 |
| STM32CubeProgrammer | 2026-10-29 移除：官方安装包需登录下载，无法自动获取；烧录改用 OpenOCD、st-flash、probe-rs 或 dfu-util。 |
| tio | 保留串口终端；不需再添 minicom/picocom。 |
| Docker rootless | 保留，未来用 SSH context 管远程 Docker。换 Podman 需核对 socket/Compose/Noctalia 插件，不因“无守护进程”就断言更适合。 |
| QEMU/KVM | 保留虚拟机执行和硬件加速。 |
| libvirt | 保留虚拟机、网络、存储管理层，不和 QEMU 二选一。 |
| virt-manager | 保留现有 GUI；命令行 virsh 可补充操作，不需换 Web 管理面板。 |
| swtpm / SPICE USB | 作为当前虚拟机能力保留；是否具体 VM 使用需看 VM 配置，未来服务器 role 不默认继承桌面 USB 重定向。 |

资料：[uv 项目](https://docs.astral.sh/uv/guides/projects/)、[MATLAB](https://www.mathworks.com/products/matlab.html)、[CLion 嵌入式](https://www.jetbrains.com/help/clion/embedded-overview.html)、[STM32CubeIDE](https://www.st.com/en/development-tools/stm32cubeide.html)、[Docker contexts](https://docs.docker.com/engine/manage-resources/contexts/)、[virt-manager](https://virt-manager.org/)。嵌入式工具的选择以探针、芯片和项目为准，本次没有连接开发板验证。

不默认补 STM32CubeIDE：当前已有 CLion 和 VSCode。若确实需要 ST 专属调试界面，先比较其 VSCode 工作流，避免无目的增加第四个 IDE。

## 游戏

| 应用 | 判断与更优解 |
|---|---|
| Steam | 保留，优先使用官方 Proton；特定游戏有问题再指定其他兼容版本，不恢复已删除 ProtonUp-Qt。 |
| Prism Launcher | 保留实例、模组和多 JDK 工作流。Minecraft 性能更应在实例 Java、模组、显卡选择和游戏设置中测量。 |
| MangoHud | 保留，基准测试时显示关键指标；日常可简化 HUD，减少视觉干扰。 |
| Gamescope | 保留按游戏启用；用于分辨率/显示封装，不能保证每个游戏增帧。不默认给 Minecraft 再套一层。 |
| GameMode | 保留，与 HUD/兼容层职责不同。当前 GPU 设备编号等硬件设置应在迁移 host 时核对，不能复制到所有服务器/机器。 |

资料：[Proton](https://github.com/ValveSoftware/Proton)、[MangoHud](https://github.com/flightlessmango/MangoHud)、[Gamescope](https://github.com/ValveSoftware/gamescope)、[GameMode](https://github.com/FeralInteractive/gamemode)。

社区边界：[Gamescope #1596](https://github.com/ValveSoftware/gamescope/issues/1596) 于 **2024-10-26** 开启，最初是 AMD/Gamescope 3.15.9 的 Steam Remote Play 黑屏；2025 年跟帖包含 NixOS/NVIDIA 550.142 案例，2026 年仍有讨论。它针对远程串流场景，不证明当前普通本地游戏或 Minecraft 必然出问题。实际测试应区分裸跑、GameMode、Gamescope、录制/分享。

## Noctalia 插件与系统集成

入口：[Noctalia 配置](../aspects/desktop/mango-session/noctalia.nix)、[输入法](../aspects/desktop/session-support/input-method.nix)、[Portal/keyring](../aspects/desktop/mango-session/host/portal.nix)。R47 按用户要求删除全部社区插件，仅保留本仓库 Launchpad、desktop-menus、legion-conservation；用户笔记、历史与其他运行时数据保留。Alt+Space 使用原生启动器。

| 项目 | 结论 |
|---|---|
| Fcitx5 / Rime / rime-ice | 保留，后续统一候选框配色；GTK/Qt addon 为应用接入，不能因有 Wayland frontend 一并删除。 |
| qt6ct / GTK 设置 | 保留现有外观桥接；One Dark 应集中提供语义颜色，再输出各应用格式，避免每个模块各写一份色值。 |
| GNOME keyring | 保留应用 Secret Service；不是网站密码库或 sops 的替代。 |
| sops | 保留运行时秘密管理；不能把密码管理器主密钥或服务令牌直接写进 Nix 字符串。 |
| Noctalia polkit / 锁屏 / idle / 通知 | 沿用当前统一入口，不再推荐重复的 agent、idle daemon 或通知 daemon。 |
| Portal / 屏幕共享 | 保留当前 workaround。捕获固定 eDP-1；若需共享外接屏，应调整该接线并实测，不是换 Discord 就能解决选择范围。 |

## 常用小工具

主要声明见[应用清单](../aspects/default.nix)、[系统小工具](../aspects/system/maintenance/tools.nix)。这些程序多数按需运行；不把安装数量等同于常驻占用。原生命令可替代基础用法，但会减少交互便利，不建议为删包统一重写。

| 工具 | 判断与用途 |
|---|---|
| bat | 保留高亮查看，现有 `cat` alias 使用它。 |
| eza | 保留文件列表、Git 标记和图标；现有 ls 系列 alias 已接线。 |
| ripgrep | 保留文本搜索，编辑器/picker 也可能调用。 |
| fd | 保留文件名搜索，与 ripgrep 分工不同。 |
| jq | 保留结构化 JSON 处理，桌面脚本有消费者。 |
| duf | 保留文件系统可用空间视图。 |
| dust | 保留目录占用定位，与 duf 不是相同查询。 |
| hexyl | 保留二进制查看；若完全不用可用内建/现有十六进制工具替代基础查看，损失较小。 |
| tealdeer | 保留命令示例；man 更完整但不同于简明用法，和 nix-index 的“哪个包提供命令”不同。 |
| qalc / libqalculate | 保留交互计算；Noctalia 计算入口存在不代表 CLI 多余。 |
| p7zip / unzip / unrar | 保留格式后端；图形归档前端也需要解压工具，不能因加 GUI 就直接删。 |
| wl-clipboard / xclip | 保留两种显示协议接线；当前跨协议桥仍有需求。 |
| grim / slurp | 保留截图与 OCR 后端，不因已有 GUI 截图入口而删除。 |
| wget | 保留基础下载入口，暂不因无明确并行/断点任务额外添 aria2。 |
| lshw | 保留硬件诊断；可按需运行，不需要常驻。 |
| 系统 Vim | 保留应急编辑入口；与 Home Manager 的完整 Neovim 配置生命周期不同。 |

## 缺失推荐：选择标准、成本和落点

下面的“缺口”指**仓库未声明对应完整方案**。如果已有外部方案，应该接入或记录，不能重复部署。标为条件项的工具不建议整批安装。

| 候选 | 补什么、适合什么场景 | 成本与现有功能边界 | 建议落点 |
|---|---|---|---|
| **Restic**（优先） | 用户文档、照片、项目未提交内容和应用数据的版本化备份；未来笔记本/服务器可复用 | 需要备份目的地、保留策略、加密凭据及恢复验证。Nix 世代回滚不包含这些用户数据。 | 共享 backup 能力，host 分别选路径/目的地，凭据走运行时秘密。 |
| Borg + Vorta（备选） | 偏重本地/SSH 备份，想用 GUI 管档案 | 多一个 GUI 集成；不要和 Restic 同时成为默认引擎。Pika 可另作更简化的 Borg GUI 比较，不装三个前端。 | 桌面前端与备份引擎分开。 |
| **KeePassXC 或 Bitwarden** | 跨网站/设备统一密码库、浏览器填充 | KeePassXC 是本地 KDBX，自选同步和备份；Bitwarden 更偏账号同步。Secret Service 和 sops 分别服务应用/部署秘密，不能视作密码库已完整覆盖。 | 桌面应用 + Firefox 扩展；凭据不进入仓库。先不自建 Vaultwarden。 |
| **Zotero Connector** | 浏览器一键收集网页、论文元数据/附件 | 当前仅声明 Dark Reader；可能已手动安装。增量维护小，实际导入仍看站点支持。 | Firefox 扩展声明，保留 Zotero 本体。 |
| uBlock Origin（条件） | Firefox 的广告/内容过滤；尚未使用同类方案时值得补 | 未在仓库扩展清单声明，不代表运行时没有安装。Clash 的整机代理与浏览器内容过滤分工不同；少数站点需单独放行，不盲目叠加大量过滤列表。 | Firefox 扩展；与密码库扩展、Connector 一并整理。 |
| **File Roller（第二十六轮替换）** | 浏览压缩包、选择性解压，与 Thunar archive plugin 配合 | 使用 GTK4 版本，TAP 指向包的绝对可执行路径；不再安装 Xarchiver。 | 桌面文件工具能力；保留 Thunar。 |
| Syncthing（条件） | 第二台电脑间同步文档/Obsidian 等普通文件 | 同步会传播修改/删除，不能替代备份。不要同步正在使用的 Zotero 数据目录、VM 磁盘或任意应用数据库；Zotero 使用自己的同步方案。 | 设备逐个启用，明确目录，避免整个 home。 |
| rclone（条件） | 已有网盘/对象存储，需要批量传输或接入备份目的地 | 云端 API、授权和挂载行为需要维护；没有具体云服务需求就暂不装。 | 需要的主机/用户角色，非默认常驻挂载。 |
| VSCode Remote-SSH（条件） | 后续服务器上的图形编辑/调试 | 服务端组件及系统要求需核对，NixOS 目标也需验证动态库兼容。现有 `kitten ssh` 解决终端接入，不等于远程 IDE。 | VSCode 扩展与目标主机分别配置。 |
| Tailscale（条件） | 多台设备跨网络互联，需要方便地访问 SSH/服务 | 引入账户、控制面和 ACL 管理；只有一台本机时价值有限。Headscale 自建控制面以后有真实需求再选，不同时铺开。 | host 选择网络角色，不复制桌面配置。 |
| fwupd（条件） | 支持 LVFS 的设备固件更新 | 先核对具体设备是否支持。现有 redistributable firmware 是驱动固件分发，不等于 BIOS/设备更新服务。 | 硬件能力；不预设 Lenovo 全部设备可更新。 |
| Okular（第二十六轮移除） | 用户决定移除；PDF 默认仍为 Zathura，批注使用 Zotero 内置阅读器 | 删除包与 MIME association；Zotero 当前锁定版本 9.0.6。 | 不删除 PDF 或应用数据。 |
| Crosspipe（条件） | 可视化 PipeWire 节点连接，例如复杂录音/直播路由 | 日常音量已有 Noctalia，排障可用 wpctl/pw-cli。锁定 nixpkgs 已移除 Helvum 包别名，不照旧推荐它；Crosspipe 仍需验证实际路由。 | 桌面音频工具，按需打开。 |
| EasyEffects（条件） | 明确需要麦克风 EQ、降噪、压缩或输出处理 | 系统不常驻 echo-cancel（曾拖垮蓝牙 A2DP），通话应用自带回声消除。效果链增加调试和处理成本，没有需求先不加。 | 用户级音效能力，避免双重处理。 |
| Heroic（条件） | 确实有 Epic/GOG/Amazon 游戏 | 商店登录和 Wine/游戏兼容另需维护，Steam/Prism 用户不自动需要。 | 游戏桌面角色。 |
| darktable（条件） | 拍 RAW，需要冲洗和照片库 | 与 GIMP 分工；普通截图/网页图片无需增加。 | 摄影角色。 |
| Nvim DAP / Neotest（条件） | 希望断点、变量、测试发现/结果留在 Nvim | IDE 已有对应能力；需要按语言维护 adapter。之前已删除 DAP，不能未经选择重新加入。 | 原生 Lua 迁移完成后，按语言单独决定。 |
| JupyterLab（条件） | Python 实验、数据分析和可交互报告 | PyCharm/VSCode/MATLAB 已覆盖部分场景；优先项目 flake/uv 环境，不扩大全局 Python。 | 具体项目。 |

官方依据：[Restic](https://restic.readthedocs.io/en/stable/010_introduction.html)、[Borg](https://borgbackup.readthedocs.io/en/stable/)、[KeePassXC](https://keepassxc.org/docs/KeePassXC_GettingStarted)、[Bitwarden 同步](https://bitwarden.com/help/vault-sync/)、[Bitwarden 扩展](https://bitwarden.com/help/getting-started-browserext/)、[Connector](https://www.zotero.org/support/connector)、[uBlock Origin](https://github.com/gorhill/uBlock)、[Xarchiver](https://github.com/ib/xarchiver)、[Syncthing FAQ](https://docs.syncthing.net/users/faq.html)、[Zotero 数据目录限制](https://www.zotero.org/support/kb/data_directory_in_cloud_storage_folder)、[rclone](https://rclone.org/)、[Tailscale](https://tailscale.com/docs/concepts/what-is-tailscale)、[LVFS/fwupd](https://fwupd.org/)、[Okular](https://apps.kde.org/okular/)、[Xournal++](https://xournalpp.github.io/)、[Crosspipe](https://github.com/dp0sk/crosspipe)、[EasyEffects](https://github.com/wwmm/easyeffects)、[Heroic](https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher)、[darktable](https://www.darktable.org/)。

早期选型时只读求值过的候选包版本包括 Restic 0.18.1、Borg 1.4.4、Vorta 0.11.0、Syncthing 2.1.3、KeePassXC 2.7.12、Bitwarden Desktop 2026.8.0、Xarchiver 0.5.4.26、Tailscale 1.98.10、fwupd 2.1.4、rclone 1.75.1、Okular 26.04.3、Xournal++ 1.3.4、Crosspipe 0.1.1、EasyEffects 8.2.4、Heroic 2.22.1；这是候选版本记录，不代表当前安装清单。**属性/版本可求值不等于构建、运行和桌面集成已经通过**；在线最新文档也不能替代锁定版本验证。

## 后续执行顺序与验收

1. 软件选型已结束；第二十六轮改为 File Roller、移除 Okular。用户后续决定移除 OnlyOffice，由 LibreOffice 统一处理九种 Office MIME；备份、密码库、Connector 及其他条件项以后有实际需求再纳入，不继续阻塞 Neovim 迁移。
2. `pamixer`、重复 `cliphist` 和 `pavucontrol` 已按用户确认精简配置；验证状态单列在执行计划。不顺带删截图/OCR、剪贴板桥或用户历史。
3. 先删无用，再原生替换；Neovim Lua + Nix 入口现已接入。先前 Heirline/Navic 原生替代已被用户后续重建要求覆盖；现恢复成熟界面插件与公式预览，OneDark 继续固定，主题选择器不恢复。完整 LaTeX 保留。当前状态见[重建记录](neovim.md)，性能结论需独立测量。
4. 在 Den 重构中，把桌面、开发、游戏、备份和服务器能力组合起来；实际主机只启用需要的能力，不把笔记本应用全集给服务器。
5. 每批实现后做模块求值、相关构建；涉及剪贴板、音频、截图、分享、游戏和编辑器交互时做运行验证。应用配置另作明确步骤。

初次评估完成的是仓库/锁定源码阅读、官方与具体社区资料核对、候选包的只读版本求值及文档整理。没有应用性能测量、真实屏幕共享/游戏回归、设备固件支持查询或备份恢复。后续音频/剪贴板清理的独立验证记录见执行计划；不以文档检查或先前系统构建结果代替运行验证。
