# 配置、运行时状态与秘密的写入归属

本文是后续 Den 接入和逐项迁移的执行设计，不代表主配置已整体切换到 Den，也不授权超出已批准功能范围的系统切换或用户数据清理。当前 Nix 配置和锁定输入是声明式内容及生成规则的依据；实际存在的用户文件、GUI 覆盖和认证状态必须在迁移时检查，不能从模块声明推定其当前内容。

## 归属规则

1. 先定义功能输入及绑定作用域，再决定该功能有哪些最终输出。默认值数据不会单独安装应用、启用功能或授权用户。
2. 每个最终路径只有一个 renderer / 写入者。多个 aspect 可以合并类型化数据，但只能交给一个功能最终序列化目标文件。若 Noctalia 模板负责动态调色板，该路径就不再由 Home Manager 同时生成；若选择 Nix 生成固定文件，则禁用 Noctalia 对该文件的模板和 hook。
3. 将只读 Nix 输出、可变应用设置、历史/缓存/模型数据、解密凭据分开。应用状态不能因移除功能而被配置删除；秘密不能进入 Nix 字符串、日志或 store。
4. 账号偏好和授权落在账号绑定；硬件事实及共享系统服务落在主机。不同账号的默认应用、主题覆盖和秘密不隐式互传。共享 host 支持只合并一次，授权仍按选择该功能的账号计算。
5. Den aspect 拥有完整功能及其相关片段；公开 schema / quirk 只表达确需跨功能共享的数据，不拥有第二份应用配置。renderer 是每个最终输出路径的单一 owner。对应用自写文件，只允许文档化、幂等且限定到单个键/标记块的 Nix patch；其余字段仍由应用拥有。

架构依据是 [架构设计](architecture-design.md) 的“少量公开数据协议”“合并、覆盖与写入者”和功能验收条件；[重构计划](refactor-plan.md) 说明当前迁移状态和回退要求；[桌面视觉设计](desktop-design.md) 固定外观目标及 Noctalia/Mango 适配边界；[服务策略](service-policy.md) 记录用户 unit 与生命周期验收。`aspects/embedded-workbench` 已作为完整实现被旧 HM/hardware/package 兼容入口复用，归一化后的 udev 规则也进入当前主机构建路径；Den 主配置尚未接管其账号绑定。`appearance`、`default-tools`、`languages` 是隔离接口/消费者样本，尚未迁移真实 Kitty、Neovim、MIME 或 LSP 接线。不能把四者统称为未接入主机的样本。

## 当前输出清单

路径均相对于目标账号的 XDG 目录或 Home。表中“当前 owner”是现在从模块和锁定源确认的写入者；“目标 owner”是完整 Den feature 接入时应采用的边界，不表示现在应添加第二套配置。目标主题已确定为：固定 One Dark Darker 语义 palette 由 Nix 数据提供，Noctalia 通过 HM 声明的 custom palette 消费；Kitty 最终配置由 Nix renderer 独占，Noctalia 不再写 Kitty 主题文件或改 Kitty 主配置。

| 声明来源 | 最终路径或范围 | 当前单一 owner / 写入方式 | 迁移归属与边界 |
|---|---|---|---|
| `modules/home/wm/mango/config.nix` + 锁定 Mango HM module + `aspects/appearance` 数据 | `~/.config/mango/config.conf` | Mango Home Manager module 将 `settings`、`extraConfig`、keybinds 和非空 `autostart_sh` 渲染为配置并放入 HM profile；该文件是声明式只读链接。 | **目标确定为 Nix renderer：**Den desktop/session feature 消费语义 palette 并为 Mango 所有颜色字段渲染最终配置（含 tab/group/jump label）；不拆出第二个可写主题 include。通过锁定 Mango parser 和实机视觉检查确认覆盖完整。 |
| `modules/home/wm/mango/noctalia.nix` + 锁定 Noctalia Mango template | 旧路径 `~/.config/mango/noctalia-colors.conf` | 当前自定义 Noctalia template 输出到该可写运行时文件，post-hook 请求 Mango reload；`config.nix` 以 `source_optional` 加载。Noctalia builtin Mango template 当前未启用，默认目标是 `mango/noctalia.conf`，并会修改主配置。 | 目标关闭 `user.noctalia-mango` 自定义 template，移除 `source_optional`，由 Mango Nix renderer 直接输出所有颜色。旧 palette fragment 先不 include、不自动删除；迁移通过后按普通生成残留清理。原因是锁定 upstream 模板未覆盖 tab bar，且固定主题不需要运行时模板 hook。 |
| 锁定 Noctalia Home Manager module 的 `programs.noctalia.settings` 与 `customPalettes` | `~/.config/noctalia/config.toml`、`~/.config/noctalia/palettes/One-Dark-Darker.json` | Noctalia HM module 将 settings 与 palette 数据渲染为 profile 文件；GUI 可以保存自己的 state override。 | Den appearance feature 的 Nix renderer 以固定 One Dark Darker 语义色生成 Noctalia custom palette；Noctalia 设置固定为 `theme.mode = dark`、`theme.source = custom`、`theme.custom_palette = One-Dark-Darker` 并消费该 palette。不要再选择 Tokyo Night builtin 或让 GUI theme state 覆盖固定选择。接受标准：锁定版 custom palette schema 通过配置校验，GTK/Qt/Firefox 消费者呈现相同语义色。 |
| Noctalia GUI / 插件设置 | `~/.local/state/noctalia/settings.toml` | Noctalia 运行时 state。当前模块注释记录 GUI 插件开关可覆盖 HM 的 `plugins.enabled`。 | 在已授权的外观 feature 迁移中检查并备份 state；只移除与固定 theme/plugin 声明冲突的具体 override，不覆盖整个 state 文件，不随 feature 移除删除使用记录。若该 override 含无法表示且用户依赖的手工设置，先提出针对性处理；普通声明式配置交接不逐文件再求批准。 |
| `modules/home/programs/terminal/kitty.nix`、`aspects/appearance/kitty.nix` | `~/.config/kitty/kitty.conf` | 当前 HM 写只读 `mayon.conf`；可写 `kitty.conf` stub 由 `seed-file` 初始化并 include 两个来源；Noctalia Kitty hook 会先 `touch` 主文件，再写 include 并发 Kitty reload。 | 目标确定为 **Nix 单一 renderer**：Den appearance/terminal feature 接收语义 palette 和 Kitty 设置后生成完整 `kitty.conf`；Noctalia `builtin_ids` 中移除 `kitty`，关闭 Kitty apply/undo hook 与 GUI template override，不再输出 `themes/noctalia.conf`。将 `mayon.conf` 片段并入最终 renderer，消除 stub/双 include。验收：生成配置通过 Kitty parser，颜色与 ANSI 顺序符合 One Dark Darker，Noctalia theme apply 不触碰 Kitty 路径。 |
| 锁定 Noctalia `assets/templates/builtin.toml` Kitty entry | `~/.config/kitty/themes/noctalia.conf` | Noctalia 生成主题内容；Kitty 模块仅在缺文件时 seed 空文件并在 stub 中 include 它。 | 新目标禁用该输出与 hook。迁移时从现有 Kitty 配置保留普通设置，主题值映入 Nix palette renderer；旧生成文件备份后保持不被 include，验收完成前不自动删除。 |
| `modules/home/base/gtk.nix` + Noctalia GTK templates/hooks | `~/.config/gtk-3.0/noctalia.css`、`gtk-4.0/noctalia.css`；两个目录的 `gtk.css` | 锁定 Noctalia 模板写 `noctalia.css`，apply hook 修改 `gtk.css` 以 import 前者；只读 symlink 可能被 hook 删除并替成可写文件。HM 当前负责 GTK3 theme/icon 与 dconf 选择、GTK4 theme 为空，没有声明 CSS 文件。 | 目标 owner 是 **Noctalia**：它消费 Nix 生成的 custom palette，独占两份 `noctalia.css` 与 `gtk.css` import hook；HM 继续只声明 GTK theme/icon/settings，不写 CSS。迁移验收：Noctalia apply/undo 在当前 HM 生成 profile 上成功，目标 CSS 是可写应用文件而非 HM store symlink，重复 apply 幂等；确认 undo 不破坏非 Noctalia CSS 内容。 |
| `modules/home/base/qt.nix`、`base/session-vars.nix`、Noctalia Qt template | `~/.config/qt6ct/qt6ct.conf`、`~/.config/qt6ct/colors/noctalia.conf` | `qt6ct.conf` 由 HM activation 通过 `lib/seed-file.nix` 缺失时写一次，之后交给 qt6ct GUI；Noctalia 生成 `colors/noctalia.conf`。`QT_QPA_PLATFORMTHEME=qt6ct` 在 home 和 systemd user environment 声明。 | 目标 owner：`qt6ct.conf` 是 **qt6ct 应用可变设置**，Nix 只负责首次缺失 seed，之后不得覆盖；palette 文件由 **Noctalia** 消费 custom palette 后输出。验收：Qt 实际读取 Noctalia palette，用户 GUI 设置保留；若锁定 qt6ct/Noctalia 升级改变配置 schema，先通过隔离 profile 的首次启动、GUI 保存、重启读回实验再迁移。 |
| `modules/home/programs/apps/thunar-actions.nix` | `~/.config/Thunar/uca.xml` | HM 生成只读文件，包含已有 Open Terminal Here 与本仓库自定义动作；不能通过 Thunar custom actions GUI 保存。旧 `uca.xml` 曾由 `backupFileExtension = "backup"` 留存。 | 完整 Thunar feature 的 actions 模块是唯一 renderer。迁移须保留旧动作和 ID；普通声明式文件交接属于已授权迁移范围，不逐文件再求批准。 |
| 同上 | `~/.config/Thunar/accels.scm` | Thunar 在退出时重写整个文件；HM activation 只维护 `uca-action-*` 对应的一条 Ctrl+Shift+C 快捷键，删掉旧的同 ID 行后追加目标行，其他快捷键由 Thunar 保留。 | **字段 owner 切分：**Thunar 拥有全文件及默认快捷键，feature 只拥有本仓库的一条 action binding。保留幂等单行 patch，不改成 HM symlink/整文件覆盖。验收：Thunar 保存退出后该键保留、用户其他 accel 行未变。 |
| `modules/home/programs/apps/screenshot.nix` | `~/.config/mark-shot/config.json` | mark-shot 应用 owns 文件其余设置；HM activation 用 jq 仅把 `.windowDetection.command` 指向 Mango helper，并保留其他 JSON 字段。 | 完整截图 feature 只拥有 `windowDetection.command` 这一个键。保留 field patch，不把整个 JSON 声明成 HM 文件；验收：已有非 detector 用户设置逐字段相同，重复 activation 无 diff。 |
| `modules/home/programs/apps/_firefox/`、`modules/home/wm/mango/noctalia.nix` | `~/.cache/noctalia/firefox/userChrome.css`；当前默认 Firefox profile 的 `chrome/userChrome.css`、`user.js` | Noctalia 输出运行时 CSS cache；仓库脚本仅替换有 begin/end marker 的 managed CSS block；Firefox activation 对 `user.js` 的本仓库 marker block 做同样更新。其余 profile、文件内容和未管理部分由 Firefox/用户拥有。 | 完整 Firefox feature 只拥有两个受标记 block；Noctalia 是 palette cache renderer。不得管理/复制整个 profile 或覆盖用户 CSS/偏好。验收：profile 选择正确、symlink/不完整 marker 时拒绝写，非管理内容和权限保留。 |
| `modules/home/base/xdg.nix` | `~/.config/mimeapps.list` | HM XDG MIME consumer 输出明确 MIME → desktop ID 映射；Swayimg Desktop Entry 由同一声明构造并覆盖包内不可见 entry。 | 默认工具 feature 只接管其 terminal/editor/browser/fileManager 相关 MIME；PDF、图像、视频和特殊 scheme 保留各自应用 feature 的映射。每个 MIME 项合并前检查实际 desktop ID 与生成 profile 中的文件。 |
| `modules/home/base/session-vars.nix`，被 Mango 消费 | HM session vars、systemd user session environment、Mango `env` 项 | 当前基础模块是共享环境变量和 `EDITOR/VISUAL=nvim`、`BAT_THEME` 的声明来源；Mango 读取 `config.home.sessionVariables` 并过滤含 `$` 或超过长度限制的值。systemd 与 home 环境不是完全相同集合。 | Den feature 仅贡献自己拥有的环境键。`default-tools` 可拥有 `TERMINAL/EDITOR/VISUAL/BROWSER`，但接入前要移除旧 `EDITOR/VISUAL` 来源；不要把所有 home 变量无差别复制到 systemd。Mango env 是消费/过滤输出，不应成为第二份变量来源。 |
| `modules/home/shell/zsh.nix` | HM 生成的 Zsh 初始化配置；`~/.zsh_history` 等应用数据 | HM 声明 Zsh、插件、别名和 Java 函数；初始化时读取 `/run/secrets/deepseek-api-key` 并导出 `DEEPSEEK_API_KEY`。历史由 Zsh 运行时追加，不是 Nix 生成内容。 | 命令行 feature 拥有 shell 配置；shell history 和 shell 插件运行状态留在用户数据。禁止在生成的 `initContent` 中展开 secret 内容。 |
| `modules/home/programs/dev/nvim.nix`、`pkgs/neovim/`、`config/nvim/**` | store 中固定 Neovim 配置树；`~/.config/nvim/init.lua` 链接 | `config/nvim/` 是原生 Lua、主题、queries、snippets 和测试的源；固定 wrapper/package 组成运行时；HM 只链接 `init.lua`，其余 Lua 从包的配置目录加载。 | 完整编辑器 feature 接管实际 Lua、Nix 包装、插件/parser 和测试。语言 aspect 只提供有序 server 数据，不能再写第二份 `programs.neovim.initLua` 与现有 Lua LSP 配置重复启用。当前 appearance/languages Neovim 适配器只是样本，不是迁移后的完整配置。 |
| `modules/home/programs/dev/ai-agents.nix`、`grok-bot.nix` | profile 中应用/desktop entries；用户 OAuth、配置、模型与应用 state | Nix 安装固定程序并声明 `grokbot`/`sand` scheme handler；Codex 配置、OpenCode 配置/凭据、Grok OAuth/XAI API key 等留在各工具管理的用户状态或授权运行时。Dsh Desktop 明确使用 `$XDG_DATA_HOME/dsh-desktop/harness`。 | AI feature 可以拥有包和非敏感默认配置；认证 state 由应用/用户身份拥有。不同账号不复用 token；scheme 默认只定义入口，不把 secret 写入 `Exec` 或 Nix 配置。 |
| `modules/system/security/sops.nix`、`secrets/secrets.yaml`、`modules/system/core/nix.nix` | 加密输入；`/run/secrets/deepseek-api-key`、`/run/secrets/github-token`；SOPS template path | `secrets.yaml` 是密文输入；主机 SSH age key 解密；两个 secret 指定 owner `mayon`。Nix access-token template 运行时渲染，owner `mayon`、mode `0400`，由 Nix daemon `!include`；token 不放入 `nix.settings` 或 store。 | 凭据归拥有该账号且获主机解密授权的 secret feature。跨机器迁移需分别检查目标 host age key、recipient、运行时 owner/mode；只传密文，不在文档、构建输出、日志、Nix 字符串中复制明文。普通 secret 的有效 mode 以当前锁定 sops-nix 生成结果核验，不能从未指定的字段推断。 |
| `modules/home/wm/mango/noctalia.nix` | `~/.local/state/noctalia/hook-battery-percent`；Noctalia/插件自身状态 | 低电量 hook 在 Noctalia state directory 记录上次百分比；插件 GUI 数据和选择也位于运行时 state。 | 仅该服务/插件拥有自己的 state；移除功能时停用生产者，默认保留 state。迁移评估后单独处理可移植数据、cache 和模型。 |
| `aspects/embedded-workbench/` | `dialout` 账号组、host udev rules | 完整 aspect 向选择者授予 `dialout`，并向 host 提供一次共享 udev 规则。该授权不会撤销其他模块已授予的组；USB `uaccess` 仍按活动 seat，不承诺按 Den binding 隔离。 | 维持 feature → 账号授权和具名 host-support → host 共享规则。多个账号选择时规则只生成一次；移除最后一个 consumer 才撤销共享 host 支持。权限验收必须看最终规则 mode/tag 与真实组名单，不只看包名。 |
| `modules/system/security/polkit.nix` + Noctalia `polkit_agent` | 系统 polkit policy / 用户图形认证 agent | NixOS 启用 polkit；当前 Mango 会话选择 Noctalia 内置 agent。Noctalia agent 是登录图形会话中的认证 UI，不应当作替代 host policy 或扩大用户组授权。 | interactive-session feature 可安装 agent；host security feature 管 system policy。任一时刻仅保留一个实际 GUI agent，按锁定会话启动行为验证。 |

### 默认工具与 MIME 的专项边界

当前 [xdg.nix](../modules/home/base/xdg.nix) 声明目录由 Thunar 打开、文本/Markdown/shellscript 由 `code.desktop` 打开、HTTP(S)/HTML 由 `firefox.desktop` 打开，并维护 PDF、图片和视频的独立映射；Mango 快捷键又分别硬编码 `kitty`、`firefox`、`thunar`。当前 session `EDITOR`/`VISUAL` 是 `nvim`，没有对应的 `TERMINAL`/`BROWSER` 变量。

隔离的 [default-tools contract](../aspects/default-tools/contract.nix) 将命令定义为不可拼接的有序 `argv`，CLI editor 与 GUI `desktopId` 分开。consumer 安装 wrapper 并透传参数，但不安装被引用的应用；Desktop ID 必须真实存在。完整 feature 迁移时需同时盘点：Mango spawn、scratchpad argv、desktop launcher/MIME、`EDITOR/VISUAL/TERMINAL/BROWSER`、GUI 桌面 ID。不要把 Desktop Entry 的 `%F`、`%U` 参数宏当 shell argv，也不要让 Nix 对同一 MIME 生成重复默认项。对带启动参数的终端/浏览器，分别验证快捷键 shell parser 与 wrapper argv；路径含空格、引号、`$` 或空参数时不可经过二次 `eval`。

## 账号、主机、服务和授权边界

- **身份与偏好：**跨主机语义稳定的外观偏好可在个人身份级输入；某台主机没有应用、使用不同显示器或采用不同浏览器时，用绑定覆盖。默认工具通常需要绑定级选择，因为应用安装/desktop ID 可随主机而异。只有一个功能被绑定选择后才渲染设置，不让 schema 数据反向启用功能。
- **主机事实与策略：**设备地址、显示器标识、平台和硬件扫描是 host facts；图形会话、驱动、电源、系统服务和 udev 是 host implementation/strategy。不要把主机特有设置复制到用户身份，也不要把 host 共享包/规则重复投递给每个账号。
- **用户服务：**Home Manager user service 的配置与启动属于选择该服务的用户 feature；StateDirectory/RuntimeDirectory、socket、pid 和服务自身缓存应按 systemd 实际目录归服务，不被 Nix 作为静态文件覆盖。多个账号的用户服务状态天然隔离。[Noctalia 的目标服务接线](service-policy.md) 是 HM 启用其 systemd unit，并以 `PartOf`/`After`/`WantedBy = mango-session.target` 定向绑定 Mango session，不全局改 `wayland.systemd.target`；Mango `autostart_sh` 暂保持非空（如 `:`）作为补充导入钩子；C 实现也会更早请求启动同一 target，不能依赖 autostart 先后顺序。保留安全共享键的 `systemd.user.sessionVariables`/environment.d 和同源 Noctalia 显式服务环境，旧 user manager 需明确同步或完整重登录；移除直接启动 Noctalia 的 `noctalia &`，只导入 Noctalia/launcher 所需 QT、输入法等白名单变量，不复制全部 home vars 或 secret，并启用 `launch_apps_as_systemd_services`，使已启动应用不随 shell 重启退出。验收需检查生成 unit 的依赖/环境和 Mango session 实际启停顺序。服务移除后先停用 writer，按迁移计划备份/保留配置，再清理明确可再生 cache；不删除历史、项目、数据库或模型权重作为配置副作用。
- **权限：**用户组授权按 binding 选择生成；host 设备规则按 host 去重。区分持久组成员（如串口 `dialout`）、polkit 动作授权和 logind 活动 seat 的临时 ACL；一种机制不证明另一种机制的隔离。迁移前后比较生成后的用户 groups、最终 udev 规则、service User/Group 和文件 mode，使用最小范围授权。
- **凭据：**密文可以进入 Nix 输入，解密值不能。用 runtime secret 文件或受支持的模板，记录 reader、owner、mode、更新/撤销步骤；不要用环境变量/日志/生成配置代替 secret manager，除非应用仅能通过该接口读取且由运行时安全地注入。

## 安全迁移步骤

迁移应逐完整 feature 执行，不能以一个全局 copy 或 `rm -rf ~/.config/...` 替代写入权交接。已授权迁移范围内，普通声明式生成文件可以随 feature 一次完成归属切换，不需要逐文件再问用户批准；需要检查的是是否误覆盖手工内容或运行时 state。遇到无法表示的用户改动、不可逆的状态格式转换、删除历史/凭据/模型等数据，才暂停该数据操作并征求针对性决定。

1. **基线盘点。**选择实际账号和主机，在隔离桌面外记录目标路径是否缺失、普通文件或 symlink、realpath、owner/group/mode、内容校验和、关联进程/服务、XDG 环境值。对应用状态只记录需要迁移的 schema/路径，不把 token 或内容敏感的日志写进报告。
2. **制定逐文件交接表。**每个 target 写明旧 writer、新 renderer、备份位置、是否可变状态、验证方式、回退命令和保留期限。确认 source of truth 后，先停用旧 template/hook，再启用唯一 renderer；不同时让两个工具轮流写同一路径。
3. **保护现有状态。**对将交给新 renderer 的声明式生成文件保留可回退副本，不把它当成需逐项审批的用户数据；备份放在权限受控且不属于 Git/Nix source 的位置，保留权限、ACL、扩展属性和 symlink 关系，秘密备份仍加密。对可变 Kitty/Qt/Noctalia/Firefox/Thunar/mark-shot 文件只迁移功能拥有的键或带标记块，保留其余应用状态。发现超出已授权范围的手工配置冲突时，先保存两份并提出最小差异处理，不静默丢弃。
4. **暂存并原子发布。**同一文件系统下用临时路径完整生成新内容，先执行格式/应用 parser 和 Nix 评估，再校验目标路径；通过后在单一写入者暂停或锁定时用原子 rename/受控 symlink 更新发布。需要跨文件迁移时按依赖顺序执行并保留旧入口，不能声称多文件原子性。activation helper `lib/seed-file.nix` 只在路径缺失时创建，既不更新也不备份；它不是通用覆盖或迁移机制。
5. **按层验收。**先检查生成 store/profile、desktop IDs、MIME 列表、session env、service units、最终组/udev mode，再在隔离 XDG/HOME 或测试账号启动应用。使用实际 Kitty parser、Neovim headless、Noctalia/Mango config parser 等适合的检查；只构建不算 GUI 运行验证。特别验证 theme apply/undo、缺失目标、现存 symlink 和应用自行改写后的行为。
6. **明确回退。**失败时先停用新 writer，再恢复备份的文件类型、权限与 symlink，并重新启用旧模板/配置；恢复后重新加载/重启相关应用或用户服务。备份保留到用户确认迁移完成、回退路径经过核验之后。旧 state 和 cache 不因新 renderer 接管而自动删除。
7. **最后清理旧声明。**只有新 owner 在目标账号/主机通过检查且保留期结束，才移除旧 Nix 声明、旧 seed 条件；确认可再生且不含用户数据的旧生成残留，可按已授权迁移计划清理，不需为每个文件单独批准。对 Noctalia 的 undo hook 先读锁定源码并验证它会移除什么；不要假设 undo 只清理生成片段。可变 state、历史、凭据、模型或无法判定的手工内容不因 owner 交接而自动删除。

Kitty 是当前最高风险交接：锁定的 Noctalia `kitty/apply.sh` 对 `kitty.conf` 执行 `touch`，随后写入 include，并发 `USR1`；Home Manager store symlink 不可写，正是当前可写 stub 存在的原因。Noctalia builtin template 还会单独生成 `themes/noctalia.conf`。目标已确定 Nix 拥有最终 Kitty 文件：appearance feature 提供固定 palette，终端 feature 消费；迁移时禁用 `builtin_ids` 中 `kitty`，停掉对应 hook，备份 `kitty.conf`、`mayon.conf` 和主题 include，保留普通自定义设置并迁移到 Nix 数据，随后用 Kitty 自带 parser 和隔离运行确认加载正确。已授权范围内完成这些普通生成配置切换，无需逐个文件等待批准；迁移验收后旧副本可按计划保留或清理。

Neovim 交接也不是添加 appearance/languages 样本模块：完整 Lua 主题、LSP 启用、插件、snippets、queries 和 wrapper 输入必须保留。将共享 appearance/语言数据适配进当前单一 Lua renderer，再移除旧配置中对应的重复字段；同一 server 的 `cmd`/root 配置只能有一个最终 consumer。Kitty 和 Neovim 的默认包/应用安装独立于 palette 数据。

## 后续迁移验收

新对话执行具体迁移前，应先检查当时的 git 状态、`AGENTS.md`、Den 锁定源码和本文件中的未决点；不基于本文推测覆盖现有用户状态。每项完整 feature 至少满足：

1. 两主机/两账号样本证明配置、默认值、服务和授权只到达目标 binding；host 支持只生成一次。
2. 对每个声明路径列出唯一 owner、renderer、可写/只读属性、数据分类和 feature 移除后行为；Nix 与运行时输出互斥清楚。
3. 数据本身不启用应用；选择默认工具不隐式安装对应应用；每个 MIME/desktop ID、Mango spawn 及 argv 消费者一致。
4. theme 输入到至少 Kitty/Neovim 两消费者的语义映射有效；Neovim 原生配置功能无回归；Noctalia 动态模板只有选择作为 owner 的路径。
5. session vars 分清 home、systemd user manager、Mango 继承环境及 shell 初始化；不把无关用户变量或 secret 转发进配置。
6. secret 构建产物、store 路径、日志中无明文；运行时 owner/mode、解密 host、读取方和撤销方式均核验。
7. service 作用域、状态目录、用户组、polkit policy 和设备 uaccess 有独立说明；不以软件安装测试替代权限测试。
8. 对改动文件具备受保护备份、可执行回退步骤和检查证据；普通声明式旧文件按迁移计划保留或清理，可变用户数据仅在明确确认其处置方式后处理。

## 已确认与待现场核实

已确认的路径和写入行为来自当前工作树指定模块、Noctalia 锁定输入 `fc2af27c0e616006bf858cad3b7c9711a028e501` 的 HM module/templates/hooks、Mango 锁定 HM module、以及仓库 aspects。Noctalia HM module 写 `noctalia/config.toml`；锁定模板写 Kitty、GTK、Qt palette 输出，GTK apply hook 还改 `gtk.css`；Mango HM module 写 `mango/config.conf`。嵌入式归一化规则通过兼容入口进入当前主机构建，但真实 Den 主配置未接管该 binding。这里核对了锁定源码，没有启动/停止 Noctalia、Mango、Kitty、GTK/Qt 应用或用户服务。

迁移时仍需现场核实：真实 Home Manager generation 是否已应用、XDG 根目录是否被环境覆盖、目标文件是否是手工内容或 symlink、Noctalia GUI/plugin state 的实际覆盖、当前 Firefox 默认 profile 与 managed CSS block、Qt GUI 改动、Kitty 主配置自定义行、各 agent 已有认证/数据、SOPS 在本机的实际权限与 age identity、systemd service 的最终运行用户/目录、当前登录 session 和设备 ACL。没有这些证据时，不宣称目标文件可安全替换或用户数据已备份。
