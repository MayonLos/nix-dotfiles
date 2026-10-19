# 新对话执行交接

更新：2026-10-19。Den 批次 0–7 已完成实现、文档与构建，详见[实施记录](den-execution.md)。
该初轮没有应用系统；其后用户已 nr 并授权后续自主应用，当前运行与待验项以各轮记录为准。
最新 CLI、媒体与桌面见[系统界面记录](system-experience-execution.md)；Hyprland 当前移除状态见[移除记录](hyprland-removal-execution.md)。
可选 dwm / Xorg 桌面的当前实现、应用及待验项见 [Xorg 记录](xorg-desktop-execution.md)。
用户随后选择 dmenu 的 B 方案并要求全仓整理；最新目录归属、共享会话边界、清理和构建状态见 [整理记录](repository-organization.md)。
用户已自行应用上述整理结果并进入真实 DWM；随后要求实际 Astra 重新设计并完善窗口规则，
当前轮次见 [DWM 视觉与窗口规则](dwm-visual-design.md)。本轮不切换正在运行的会话。
下文起点、旧提交清单和批次执行顺序保留为历史设计依据，不重做已完成迁移或软件选择；
继续工作应先读最新记录中的真实 generation、写入交接和未验证项目。没有部署真实服务器。

后续桌面与窗口优化由实际 Astra 设计实施，独立 goal 的进度和验证见
[桌面优化实施记录](desktop-polish-execution.md)。它延续实现与构建边界，未授权系统应用。

用户随后自行 nr，并授权下一轮优化中自主应用。当前执行以
[系统与编辑器优化记录](system-polish-execution.md) 为准；应用授权和运行结果按该轮记录，
不把此前“不应用”的历史边界误作当前限制。

最后一轮面板/场景与 Rime 收尾见[面板和输入法记录](panel-rime-execution.md)。用户已明确
要求收尾并 push，覆盖此前“仅本地提交”的限制；后续任务仍须以当时授权为准。

用户随后指出 Neovim 的实机回归，要求多代理破坏性重构并由实际 Astra 重新设计，旧 Nixvim
仅作效果参考，OneDark 约束继续。该轮当前状态见[Neovim 重建记录](neovim-rebuild-execution.md)，
此前自写 UI 的设计和验证不能代替新实现的证据。

其后用户要求其余系统界面同样参考社区优化，由实际 Astra 继续设计。最新状态见
[系统界面优化记录](system-experience-execution.md)，具体构建、应用与待验项以该记录为准。

## 阅读顺序与设计依据

1. 仓库 [AGENTS.md](../AGENTS.md)：操作约束、验证与分工；新对话先读当时版本。
2. [架构设计](architecture-design.md)：Den 的实体、绑定、完整功能、用途组合与协议。
3. [桌面视觉](desktop-design.md)：Astra 负责的固定 One Dark Darker 设计。
4. [操作方式](workflow-design.md)：Mango/tmux/Neovim 分层、项目环境、截图与文件工作流。
5. [写入归属](config-ownership.md)：只读配置、可变状态、秘密和逐路径交接。
6. [后台服务](service-policy.md)：声明与运行态差异、启动方、会话边界、测量及生命周期。
7. [未来服务器](server-plan.md)：当前可复用边界与真实机器出现后的实例要求。
8. [重构计划](refactor-plan.md)、[应用评估](application-review.md)、[Neovim 记录](neovim-migration-plan.md)：软件决定及既有迁移证据；其中旧路径、store 路径和旧验证结果均有时间范围。

架构和上述专项设计规定后续目标；历史记录用于说明来由，不覆盖当前源码、锁文件或用户更新的选择。发现矛盾先核实并修正文档，不用 `mkForce` 把边界冲突盖过去。

## 已确定的目标

| 范围 | 执行基线 |
|---|---|
| 框架 | Den，薄 flake-parts 接线；真实 inventory + 完整功能 aspects + 普通 includes bundles |
| 支持对象 | 先迁当前 NixOS 笔记本；架构允许以后按真实实例添加无头服务器及其他 CPU 平台 |
| 桌面 | Mango 与 Noctalia，固定 One Dark Darker `#1f2329`；当前状态见[Hyprland 移除记录](hyprland-removal-execution.md) |
| 终端和编辑器 | Kitty + tmux；原生 Lua + Nix Neovim，保留已完成的自有功能及确认保留的插件 |
| IDE 和应用 | 沿用重构计划已决定的保留/删除；VS Code + IDEA/PyCharm/CLion，不重开一轮全量软件选择 |
| 开发环境 | 全局基础工具 + 项目 flake；项目拥有依赖/SDK 版本，PATH 允许项目覆盖 |
| 操作 | Super 管桌面、Ctrl+a 管 tmux、Neovim 保留自己的 Ctrl/leader；取消 tmux 无前缀 Alt 拦截 |
| 配置 | 一份类型化输入、一个最终 renderer；固定配色不受壁纸改色；保留完整丰富 Lua 主题，不用四项高亮样本覆盖它 |
| 生命周期 | session-only 服务跟随会话；应用/CLI 安装不自动启 daemon；本地容器/VM 与远程客户端分别选择 |
| 数据 | 配置迁移和数据删除分开；模型权重、项目、历史、登录 state、VM/容器卷不能顺手清空 |
| 提交 | 每个可审查闭环及时本地 commit；不 push，不把无关工具配置/用户改动混入提交 |

## 迁移前起点（历史）

已经有 `aspects/embedded-workbench`、`appearance`、`default-tools`、`languages` 和 `tests/composition`。Den 固定在测试子 flake；主根 flake 尚未接入。嵌入式旧入口已引用完整实现，并修正 ST-Link 世界可写规则；外观、默认工具、语言消费者仍是隔离样本。

最近的可回退提交：`7c75b78`（隔离消费者）、`c97d4f9`（语言）、`e8b0e88`（默认工具）、`e2874f6`（外观）、`58dcc18`（嵌入式组合）、`284da94`（ST-Link 权限）。新对话必须查看实际 HEAD，不能假定这份列表是最新提交。

此前的软件精简、完整 Neovim Lua + Nix、部分 README/AGENTS 与工具配置等仍有大量工作树差异。已有检查记录不能代替把实际 diff 审成可回退基线。`.agents/skills` 的删除、`.codex` 角色修改、`.gitignore` 等也在差异中；先查明关联和意图，不能 `git add -A` 或用 hard reset 清理现场。

服务文档记录的运行快照与工作树声明不同：遗留 llama-cpp 和 cliphist 用户 unit 可能还在运行。新对话重新只读检查，不能把旧进程当成当前配置应保留的功能，也不能把删模块当成服务已退出的证据。

独立复核还发现当前 Mango 模块注释中的旧结论已不适用于锁定源码：C 实现会在 HM autostart 执行前自行请求启动 session target，HM 非空 autostart 不是唯一启动路径。批次 5 迁移时一并修正这些注释；Noctalia 所需安全环境在用户管理器/显式服务环境中预先提供，不能只靠 autostart 导入顺序。具体证据和验收见 [后台服务策略](service-policy.md)。

## 执行批次与完成条件

每批依次做边界确认、实现、相关检查、独立复核、文档状态更新、本地提交。实际发现接口不成立可以重做；不要同时改完所有功能后才求值。允许短期兼容入口，但同一 host/account 上不能同时启新旧 renderer。

| 批次 | 工作范围 | 进入下一批的条件 |
|---|---|---|
| 0 保存基线 | 审查既有未提交软件/Neovim 修改与输入删除；按语义分批提交，工具/本地资料单独判断 | 删除项无活动引用；相关包检查及真实 host 求值/构建完成；工作树剩余项有明确归属 |
| 1 真实主机接线 | 把已验证 Den 接口接入根 flake；建立薄 `nix/`、真实 inventory；保留当前硬件、HM stateVersion、账号和秘密接线 | `nixosConfigurations.nixos-btw` 构建；账号/HM/启动/磁盘无非预期变化；测试实体不导出部署项 |
| 2 系统边界 | 主机 facts 与策略拆开；迁网络/Nix/启动/驱动/电源/授权/secret ownership | 笔记本代理、TUN 信任、GPU/显示器事实不泄漏到无头 fixture；binding 授权及共享支持检查通过 |
| 3 命令行工作台 | Zsh、Git、direnv、CLI、Kitty、tmux、默认工具；按操作设计处理入口 | 路径/argv 保真、cwd、MIME/CLI 默认区别正确；tmux 不截获应用 Alt；配置 owner 无重叠 |
| 4 完整编辑器与语言 | 迁丰富 Neovim 实现、VS Code、三个 JetBrains；语言贡献替换重复配置 | 既有 Neovim 专项检查、启动、completion/LSP/formatter 通过；项目环境可覆盖；未选语言/编辑器不反向启用 |
| 5 交互会话与视觉 | Mango、Noctalia、greeter、IME、portal、截图、剪贴板、文件操作；落实 Astra 视觉 token 与固定 renderer | palette/文件/按键静态检查通过；会话启动与退出接线无双重启动；形成实机验收清单；GUI 证据在应用后补齐 |
| 6 其余完整功能 | 按现有保留决定迁嵌入式、MATLAB、LaTeX、本地容器/VM、AI、日用/媒体/游戏 | 每项声明移出旧入口；权限/数据/服务边界明确；保留功能无静默丢失，不重复选软件 |
| 7 整体收口 | 处理真实接线后的协议重复、旧目录/兼容路径、构建输出/文档/CI；完善无头组合与平台约束 | 旧递归导入退出；无闲置输入、双 renderer 和死引用；相关 checks 与完整 host 构建通过 |
| 8 应用与运行验收 | 在有应用授权的执行任务中，使用已构建结果应用，核对文件迁移、退出旧服务、重登录/设备/桌面/游戏/休眠 | 真实行为与资源前后比较有记录；未完成项目明确保留；备份与回退可用，之后才清理确认可再生旧输出 |

批次 3/4/5 的源文件可以独立迁移，但最终共享 palette、默认工具和 session 路由由主代理串行集成。批次 6 可按功能开多个小任务，不必单独等待其余批次所有运行验收；每批都必须保持可求值和可构建。

当前目标不包含真实服务器上线。服务器方案中可在本轮完成的无头隔离/平台参数化纳入批次 2/7；只有拿到真实实例后，才增加磁盘/网络/业务/部署任务。

## tests/ 的职责与投入范围

`tests/` 是自动验证代码，不是系统后台服务，也不是正常开机要启动的额外主机。旧 `tests/den` 隔离子 flake 已整合到根 checks；当前 `tests/composition` 直接组合生产功能，复用根锁输入。

| 检查层 | 验证什么 | 不证明什么 |
|---|---|---|
| 求值/组合 | 两主机两账号隔离、未选功能无输出、共享宿主资源去重、真正冲突拒绝、账号权限范围 | 不证明设备实际可访问或运行耗用 |
| 构建/产物 | 包、HM activationPackage、最终 udev/config/desktop ID、完整 host toplevel | 构建不执行 activation，不代表配置已应用 |
| 隔离程序检查 | Kitty parser、Neovim headless、wrapper spy、真实 clangd 的已知小工作负载 | 不代表完整桌面或全部项目行为 |
| 少量 VM 集成（需要时新增） | 真正依赖 systemd/网络/账号启动的关键路径 | 不模拟真实 NVIDIA、显示器/音频/USB、游戏帧时间 |
| 实机验收记录 | 登录/退出、输入法、屏幕共享、剪贴板、权限、休眠、MC 等 | 只对所记录版本、设备、场景有效 |

专项检查优先跟功能放，跨功能不变量放顶层 tests；不为每个可逆小修改写镜像实现的测试。新增负例应能故意破坏关键保障并触发失败；大而慢的 VM 测试只用于轻量检查覆盖不了的边界。真实秘密不用作 fixture，测试账号不授予真实设备或公网权限。官方测试机制见 [NixOS Tests](https://nixos.org/manual/nixos/stable/#sec-nixos-tests)，当前样本的实测范围见 [tests/composition](../tests/README.md)。

## 多代理分工与集成

主代理负责方案、跨 feature 判断、共享入口、输入锁与真实 host 接线、最终 diff、检查和提交。Astra 已负责桌面视觉规格；如果后续实际视觉实现偏离其设计且需要重新设计，可再委托 Astra，不把名称当作已调用的证据。

Luna 负责窄任务：源码/锁定 API 搜索、单一 feature 小迁移、文件清单和专项文档核对。独立 reviewer 复核账号/权限、数据与服务生命周期、跨模块整合等实质边界。并行实现不共享写入文件；需要改同一文件时主代理集成或隔离 worktree。每个任务列绝对路径、可写范围、事实、验收标准；所有子代理不得回滚他人修改、提交或推送。

独立构建 CLI 如可能争用 checkout、索引或临时状态，应串行或使用隔离 worktree；单纯只读证据收集可以并行。并发量由当前环境槽位决定，不在任务里强制无限子代理。不能因一个 review 报“通过”就省略主代理对实际 diff/执行结果的检查。

## 验证命令和真实应用边界

按当批影响选择，不为纯文档重复整个系统构建：

```sh
git status --short
git diff --check
nix flake check --no-write-lock-file
nix flake check --no-build --no-write-lock-file
nix build --no-link --no-write-lock-file .#checks.x86_64-linux.treefmt
nix build --no-link --no-write-lock-file .#nixosConfigurations.nixos-btw.config.system.build.toplevel
```

旧测试子 flake 已移除；以上检查使用根锁和生产配置，输出以当前源码为准。新文件经审查后进入 Git 可见范围；不要用包含整个脏工作树的 `path:.` 绕过，因为 Git 忽略文件里可能有运行时秘密。需要最小 source snapshot 时明确列出复制范围并检查。`nix fmt` 会修改文件，只在核对已有改动后对明确范围使用。

应用不是构建的隐式后续：本次设计轮不应用；新对话 goal 是否包含应用，以用户当时指令为准。用户明确授权应用后持续执行，不重复请求相同授权；若只要求实现与构建则交付到该边界并列出未做的实机项。系统入口仍是 `sudo nixos-rebuild switch --flake .#nixos-btw`，没有独立 Home Manager switch。`test` 同样会即时改运行系统，不能冒充只读检查。

不得因允许破坏性重构就格式化磁盘、删除用户状态、撤销有效凭据或强杀业务数据进程；这些不属于改仓库结构的自动副作用。备份/旧 generation/构建产物保留至回退边界明确；不在验收前用清理命令删除它们。普通生成文件的归属迁移在既有任务授权内完成，不给每个文件增加多余人工确认。

## 下一对话可直接使用的任务文本

下面文本授权执行仓库迁移并构建，未默认授权系统切换；若用户同时要求应用，按上节执行并补实机验收。

> 为 `/home/mayon/nix-dotfiles` 建立 goal，按 `docs/execution-handoff.md` 及其中链接的最新设计文档完成整个仓库的 Den 重构。先审查并保存已有软件/Neovim 改动基线，再接入真实主机，逐功能迁移，落实 Astra 桌面视觉、分层快捷键、单一文件写入者、后台服务和未来服务器的复用边界，最后清理旧结构并完成相关构建检查。使用原生多子代理，窄任务交给 Luna，跨模块由主代理集成和独立复核；按可审查闭环频繁本地 commit，不 push。允许推翻旧实现，不删除用户数据、不升级无关输入、不伪造服务器。已有软件决定不重复询问。执行到实现、文档和构建完成；系统应用与实机项明确报告，只有我另行或同时授权应用时才执行 switch。

新对话不要照抄本轮曾通过的检查；重新运行当批所需检查并记录结果。若目标含实机项目但环境无法验证，记录阻碍与可继续完成的部分，不能把未测标为完成。
