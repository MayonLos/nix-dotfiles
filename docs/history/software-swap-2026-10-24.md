# 第十轮：软件替换、Neovim 启动页和 Lua LSP 实测

日期：2026-10-24。按用户已确认的九项任务实施；本轮只构建，不激活系统。
未执行 sudo、nixos-rebuild、Git stage/commit/push/stash/reset、输入更新或数据迁移/清理。
未改 r9 独立 worktree 负责的 Mango、Noctalia、greeter 文件，也未改 desktop-design.md。
微信、Discord、Typora 原有配置、登录、聊天和文档数据均保留。

## 软件与语言

- `aspects/communication/im.nix`：`pkgs-unstable.wechat-uos` 改为
  `pkgs-unstable.wechat`。锁定 unstable 为 **4.1.13.26**，stable 为 **4.1.1.4**，
  保留 `# unstable:` 原因。依据是锁定 nixpkgs 的
  `pkgs/by-name/we/wechat/{package,linux}.nix` 和构建产物中的 AppRun/desktop 文件。
- `aspects/communication/default.nix`：Discord 改为 stable
  **Vesktop 1.6.5-unstable-2026-07-16**，显式 `withSystemVencord = true`。
  包名带 unstable 字样，但来源是 stable pkgs。`withMiddleClickScroll` 保持包默认 false。
  锁定 `pkgs/by-name/ve/vesktop/package.nix` 对 Linux 包含 PipeWire/venmic，
  Electron 43 wrapper 在 `NIXOS_OZONE_WL` 和 `WAYLAND_DISPLAY` 同时存在时加入
  Wayland/IME 参数；实际主机 HM 的 `NIXOS_OZONE_WL = "1"` 已求值确认。
  没有写 Vesktop 用户设置或可选 QuickCSS seed。
- `aspects/languages/{support,data}.nix` 和 Neovim `lsp/servers.lua`：Python
  改为 stable **basedpyright 1.39.3**，命令 `basedpyright-langserver --stdio`，
  根标记含 `pyrightconfig.json` / `pyproject.toml`。核对锁定 nvim-lspconfig **2.9.0**
  的 `lsp/basedpyright.lua`，使用 `basedpyright.analysis`，解释器仍用
  `python.pythonPath`，保留项目 `.venv` 优先级。
  `typeCheckingMode = "basic"` 保持原 Pyright 级别，避免切换时直接采用 BasedPyright
  更严格的默认；不再强制 `useLibraryCodeForTypes`，遵循锁定定义并让项目配置优先。
- 同一 languages 契约新增 stable **Taplo 0.10.0**：`taplo lsp stdio` 和 Conform
  `taplo` formatter（锁定实现为 `taplo format --stdin-filepath $FILENAME -`）。
  `python-support` 通过 Den `includes` 选入独立的 `toml-support`，用于 pyproject.toml；
  防止只修改独立 Neovim 包默认贡献、却漏掉真实 host。HM 包和真实 Neovim 生成数据均已确认。
- `aspects/system/maintenance/tools.nix`：启用 **sudo-rs 0.2.15**，明确关闭旧 sudo。
  继承原策略：wheel 需密码、`execWheelOnly = false`、`SETENV`、root/wheel
  `ALL=(ALL:ALL)`；sudo/sudoedit wrapper 权限不变。锁定 NixOS 模块也为 sudo-rs
  提供 `NIXOS_NO_CHECK` 和 TERMINFO 的 env_keep，生成的 sudoers 经 visudo 构建检查。
  仓库无另一个旧 `security.sudo` 策略消费者需要搬移。实际 `nr` alias 是
  `nh os switch`；锁定 nixos-rebuild-ng 按 PATH 查找 `sudo`，未固化旧实现路径。
- `aspects/documents/default.nix` 移除 Typora 包与主题 import，删除
  `aspects/documents/typora-theme.nix`。主题只是 fetchFromGitHub 配方，没有 flake input，
  **flake.nix / flake.lock 均未修改**，没有执行 lock/update。
  Markdown 默认改为 `obsidian.desktop`：documents 用 mkForce 实现这一单项 MIME
  覆盖，普通文本/shell 的 default-tools 账号绑定保持原状；此归属例外同步到
  `docs/config-ownership.md`。用户可写范围不包含 inventory/default-tools，因此未改它们。
- `nix/dev.nix`：deadnix 增加 `no-lambda-pattern-names = true`，保留 Den 按 lambda
  参数形状分派所需的未使用参数；statix 保持原状。最后一次 fmt 前后逐一比较全部 Nix
  文件，变化为 **0**，没有删 lambda 参数。此前 fmt 的修改仅是 Lua 排版。

### 微信逐项接线与 r9 交接

| 项目 | 旧 UOS → 官方包的处理 |
|---|---|
| 执行文件 | 仍为 `wechat`；官方 AppImage 通过 nixpkgs FHS wrapper 启动 |
| 输入法 | 旧 UOS wrapper 的 XMODIFIERS→QT_IM_MODULE/GTK_IM_MODULE 映射不再存在；未盲目复制到不同的 Qt/AppImage 运行时。官方 ELF/bundle 有 Fcitx 与 Wayland text-input-v3 支持，实际输入待验 |
| Wayland/X11 | 取消旧包隐含的 `QT_QPA_PLATFORM=xcb` 强制；官方 wrapper 未强制任一协议，交给程序探测。静态支持不等于已在本机跑原生 Wayland |
| 剪贴板 | 原会话共享的 X11↔Wayland 桥保留；本轮没有删除、重建或迁移任何历史库。图片/文本双向复制仍需实机回归 |
| Desktop ID | `com.tencent.wechat.desktop` → **`wechat.desktop`**；构建产物为 `Exec=wechat %U` / `Icon=wechat`，无 StartupWMClass |
| app_id/class | 没有将 desktop ID 当成实际 app_id/class。当前 Mango/Noctalia/greeter 源码中不含微信或 Discord 显式规则，r9 **需改位置清单为空**；登录后实际 class/app_id 仍待观测 |

现存 `audio.nix` 的 `~wechat.*` 是通用进程匹配，不需随 desktop ID 改动。
如用户曾手工固定旧 UOS 桌面入口，应在运行新版本后重新固定；本轮不写其面板状态。

## Neovim 启动页

`config/lua/mayon/ui/dashboard.lua` 改为六行 ANSI Shadow **MAYON**，第三字母为 Y；
每行独立使用 palette 蓝→青 RGB 插值。ColorScheme 事件会刷新这些高亮。
使用 Snacks **2.31.0** 默认的垂直居中算法，并显式横向居中 header。
最近文件改为“文件名 + 弱化父目录”：优先项目相对路径，否则相对 `~`，过长时从左截断。
项目根显示 `.`，页脚仍为 `MAYON · 配置 xx.x ms`。

正式 Git 包 headless 渲染：[完整行捕获](software-swap-dashboard.txt)。120×45 的 Neovim
界面中，dashboard 可用高 43、内容高 23、偏移 10，即 floor((43−23)/2)。
六色依次为 `#4fa6ed #4ea8e3 #4caada #4bacd0 #49aec7 #48b0bd`。
`config/tests/interface.lua` 验证字形、居中、渐变各异、ColorScheme 刷新和路径格式；
相关测试已随正式 `checks.neovim` 构建通过。GUI 字体观感仍属于实机验证。

## LuaLS / emmylua_ls

**保留 LuaLS 默认。** Emmy 的诊断与补全明显更快，但未达到“不劣的诊断质量”条件。
没有仅凭实现语言或一次启动时间替换默认。

版本：Neovim **0.12.4**、LuaLS **3.18.1**、Emmy **0.23.1**、lazydev
**1.10.0-unstable-2026-03-14**。脚本在
`aspects/editing/neovim/benchmarks/{run.py,lua-servers.lua}`，完整机器信息、源文件哈希和
可执行 store 路径见 [metadata.json](software-swap-2026-10-24-data/metadata.json)。

### 口径

- 各三次独立 Neovim 冷进程，HOME/XDG 目录全新且脚本拒绝复用；不清 OS page cache。
  顺序 AB、BA、AB；比较工作区为 `aspects/editing/neovim/config`。
- 用正式 Git flake 的 Neovim dev wrapper，保留生产插件和 lazydev；默认配置没有修改。
  初步探索采用路径源的结果不进入下表。该路径源的忽略文件已核对，只有本轮 `.team/r10`
  测试状态；交付检查和产物均重新使用显式 `git+file:///home/mayon/nix-dotfiles`。
- 锁定 lazydev 确实支持 `lua_ls` / `emmylua_ls`。但它将本配置的 `lua/` 加为 library
  并写 ignoreDir；Emmy `lua_diagnostic.rs` 对非 main workspace 直接跳过诊断。
  临时适配对**两者**都从 library/ignoreDir 去掉本地源码、补本地模块搜索路径，保留外部
  Neovim/插件按需库。脚本断言适配已生效；这段适配未写入生产默认。
- Headless 不运行交互 pull refresh 周期，因此在最终 initialize 参数中为两者禁用 pull，
  统一观察 push。LuaLS 对零诊断文件不发送首个空列表，因此在内存中于 return M 前插入
  已知 undefined-global 探针；不写工作区文件，必须观测探针才算有效完成。
- Attach 从 Neovim 初始化前计时到客户端 initialized+attached。首诊断是探针通知时间；
  “稳定估计”是无进行中 progress 且诊断/progress 静默 2 秒后的时刻减 2 秒，
  **不是协议提供的精确全工作区诊断结束时间**。性能目标为 `lua/mayon/lsp/servers.lua`。
- 每次连续请求 10 次相同位置 `vim.lsp.` 补全，全部成功且非空；保留首次较慢请求，
  取这 10 次的中位数。该文件原诊断两者均 0；补全分别有 65 / 63 项。
- RSS 每 10ms 采样 `/proc`，是观测峰值，不能保证捕获每个瞬时峰；共享页会重复计入。
  总峰包含 Neovim+后代，LSP 峰为全部后代之和；质量扫描的内存不混入性能数据。

### 三次原始结果

时间单位 ms，RSS 单位 MiB。每个 JSON 保留全部 10 次延迟、诊断/progress 事件及配置。

| Server | 次数 | Attach | 首诊断 | 稳定估计 | 10补全中位数 | 总RSS峰 | LSP及子进程RSS峰 |
|---|---:|---:|---:|---:|---:|---:|---:|
| lua_ls | 1 | 134.86 | 2017.09 | 3146.73 | 2.627 | 389.8 | 355.7 |
| lua_ls | 2 | 142.40 | 2046.98 | 3237.24 | 3.520 | 391.3 | 357.4 |
| lua_ls | 3 | 132.11 | 2041.54 | 3312.54 | 2.845 | 590.6 | 557.3 |
| emmylua_ls | 1 | 128.94 | 549.72 | 1027.87 | 0.740 | 241.7 | 206.4 |
| emmylua_ls | 2 | 123.44 | 549.66 | 1027.97 | 1.134 | 256.5 | 220.4 |
| emmylua_ls | 3 | 124.45 | 534.47 | 1029.70 | 0.805 | 259.1 | 224.1 |

原始数据：[LuaLS 1](software-swap-2026-10-24-data/lua_ls-1.json)、[2](software-swap-2026-10-24-data/lua_ls-2.json)、[3](software-swap-2026-10-24-data/lua_ls-3.json)；
[Emmy 1](software-swap-2026-10-24-data/emmylua_ls-1.json)、[2](software-swap-2026-10-24-data/emmylua_ls-2.json)、[3](software-swap-2026-10-24-data/emmylua_ls-3.json)。

三次中位数：Attach **134.86 / 124.45ms**（LuaLS/Emmy，仅 1.08×）；
首诊断 **2041.54 / 549.66ms**（3.71×）；稳定估计 **3237.24 / 1027.97ms**（3.15×）；
补全 **2.845 / 0.805ms**（3.53×）；总 RSS 峰中位数 **391.3 / 256.5MiB**。
LuaLS 第三次出现 590.6MiB 观测峰，原样保留，没有删除离群样本。

### 诊断质量

另各启动一次，在同一工作区逐个打开八个相同文件，使用只存在于内存第 1 行的探针确认
诊断有效，再从统计移除探针并还原行号。只读取被测 LSP namespace，排除 luacheck。
这不是简单把“诊断更少”判为更好。

| 文件 | LuaLS | Emmy |
|---|---:|---:|
| init.lua | 0 | 1 |
| lua/mayon/config/bootstrap.lua | 0 | 0 |
| lua/mayon/lsp/servers.lua | 0 | 0 |
| lua/mayon/ui/dashboard.lua | 0 | 3 |
| lua/mayon/plugins/lua.lua | 1 | 3 |
| lua/mayon/plugins/completion.lua | 3 | 15 |
| lua/mayon/plugins/ai.lua | 1 | 1 |
| tests/lua_workspace.lua | 0 | 9 |
| 合计 | **5** | **32** |

完整诊断：[LuaLS](software-swap-2026-10-24-data/quality-lua_ls.json)、
[Emmy](software-swap-2026-10-24-data/quality-emmylua_ls.json)。
抽查 Emmy 对 `lazydev.setup` 报缺 `debug/runtime`，对 Blink 的部分用户配置多次报缺字段；
但锁定 lazydev `config.lua:61` 与 Blink `config/init.lua:117` 都与默认配置深合并，
这些是合法配置上的诊断噪声。不能把全部 32 条都宣称为误报；已有抽查足以说明质量条件
未满足。独立 reviewer 复核了数据、库语义及结论，故不切换生产 LuaLS/lazydev 设置。

复现时先构建 `.#neovim-dev`，使用 metadata 内的两个 LSP 可执行文件，传入不存在的
输出目录；`BENCH_TRIALS` 默认 3，质量扫描另用 `BENCH_TRIALS=1 BENCH_QUALITY=1`。
脚本拒绝旧缓存和不完整结果，并校验 10 次补全非空、探针与 lazydev 适配有效。

## 验证与边界

- `git diff --check`、`nix fmt` 通过；核对 fmt 前后全部 Nix 文件无变化，
  没有删除 Den lambda 参数。statix 仍启用且未改变设置。
- `nix flake check --no-build --no-write-lock-file` 通过，只有既有未知 flake output 警告；
  这是求值证据。
- 构建全部 **18 项** `checks.x86_64-linux`、`.#neovim`、`.#neovim-dev` 和主机 toplevel，
  使用 `--no-link --no-write-lock-file --print-out-paths`，正式 Git flake 构建返回 0；[输出清单](software-swap-2026-10-24-data/build-outputs.json)。
  首轮测试发现 dashboard 项目根测试依赖 cwd 的缺陷，已换独立 pyproject fixture 并重跑通过；
  不能把此前未格式化或失败的构建当作通过。
- [主机求值](software-swap-2026-10-24-data/host-evaluation.json) 证明 sudo-rs=true、
  sudo=false、wheel 密码策略不变；home.packages 有 wechat/vesktop，无
  wechat-uos/discord/typora/pyright。
  [真实主机 Neovim 语言证据](software-swap-2026-10-24-data/host-language-evidence.txt)
  来自 HM 实际生成文件，包含 basedpyright 与 taplo。
- 软件包装、sudoers 和 Neovim 启动/补全/LSP/TOML 格式化均有构建/沙箱行为证据；
  不等同于已应用或 GUI 成功。

新 toplevel：`/nix/store/28djn8im6xib00ra5ak780ajrm9sphm4-nixos-system-nixos-btw-26.05.20261021.da6dc0e`。
Neovim：`/nix/store/mj06apg9lqgmzx5cs3qp06f4cf6k3mmb-neovim-0.12.4`；
dev：`/nix/store/b2piwmf0kqkw6y82hfzfhb7jx857pgdr-neovim-0.12.4-dev`。

应用后待验：微信登录、中文预编辑/候选窗、文本/图片剪贴板和实际后端/class；
Vesktop Wayland 窗口、Portal 屏幕/音频分享；sudo-rs 密码认证、`nr`/`nh` 正常提权；
Obsidian 对 vault 内外独立 Markdown 文件的打开行为，以及启动页实机字体和不同尺寸布局。
本轮未激活配置，未运行这些实机验证。

## 改动文件清单

| 范围 | 文件 |
|---|---|
| 通信 | `aspects/communication/default.nix`、`im.nix` |
| 文档应用 | `aspects/documents/default.nix`；删除 `aspects/documents/typora-theme.nix` |
| 语言契约 | `aspects/languages/data.nix`、`support.nix` |
| 系统与格式化 | `aspects/system/maintenance/tools.nix`、`nix/dev.nix` |
| Neovim 运行时 | `aspects/editing/neovim/config/lua/mayon/lsp/servers.lua`、`ui/dashboard.lua` |
| 行为检查 | `aspects/editing/neovim/config/tests/{interface,lsp,samples,startup}.lua`、`nix/neovim.nix`、`tests/composition/system.nix` |
| 基准脚本 | `aspects/editing/neovim/benchmarks/{run.py,lua-servers.lua}`（新增） |
| 当前文档 | `docs/README.md`、`application-review.md`、`config-ownership.md`、`neovim-rebuild-execution.md` |
| 本轮证据 | 本记录、`docs/history/software-swap-dashboard.txt`、`docs/history/software-swap-2026-10-24-data/` 内 JSON/语言证据（新增） |

新增文件未 stage，遵守本轮 Git 禁令；Git flake 不包含它们。它们是独立运行的基准脚本和
文档/原始数据，不是未纳入构建的运行时模块。脚本已实际执行，新增文本/JSON 的链接、
格式与尾随空白已另行检查。
