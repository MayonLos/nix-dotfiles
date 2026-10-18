# Den 实施记录

执行日期：2026-10-18。目标为实现、文档与构建；不执行 switch/test、服务启停或用户数据清理。运行中的配置仍可能来自旧 generation。

## 批次 0：可回退基线

- 起始 HEAD `c894381`；已有工作树和索引补丁、跟踪文件快照保存在用户状态目录 `nix-dotfiles/baselines/den-start-20261018T033548Z`，不进入 Git/store。
- `5805d3b` 保存既有软件精简、工具链与完整原生 Lua Neovim。删除软件和编辑器旧输入之间有引用依赖，合成一个可构建闭环。
- `46cfbe2` 单独保存已存在的仓库指令、角色及旧领域说明删除；没有混入新 Den 实现。
- 重新执行 flake check 求值、treefmt、Neovim 检查和完整主机构建，全部通过；Luna 定点审查和独立 reviewer 均未发现阻塞。
- 当前运行中仍有 llama-cpp 与两个 cliphist watcher；仓库不再声明它们，本次没有停止这些服务或删除历史/模型。

## 批次 1：真实主机接线

Den v0.19.0 使用测试子 flake 已验证的同一 revision。只新增 Den 锁节点，没有升级其他输入。根 flake 通过薄 `nix/` 接线，真实 inventory 仅有 `nixos-btw`；Den 生成部署输出，原手写 `flake/system.nix` 已退出导入。系统和 HM 的旧模块入口暂为兼容接线，后续按功能迁出。

Den 的 `host.instantiate` 显式复用 stable/unstable package instances，并向 NixOS `specialArgs` 提供 inputs 和 unstable；HM 同样保留原 extraSpecialArgs、全局包与备份设置。不能仅依赖 Den 的 module args 提供 imports 所需 inputs。

重新求值通过。迁移前后 JSON 比较：磁盘/交换、启动参数及 loader、系统/HM stateVersion、账号 UID/home/shell/groups、secret owner/mode/path 均完全相同。treefmt 与完整主机 toplevel 构建通过；独立 reviewer 未发现阻塞，新旧 HM profile 内容对比一致。构建不会执行 activation。

## 批次 2：系统边界

系统侧递归导入已退出，登记入口为 `aspects/system/default.nix`。通用维护不携带代理、个人 Nix trusted-user、秘密或笔记本电源/GPU；这些由真实 host 选择。扫描工件、PCI/显示事实、账号绑定和凭据授权分别位于 inventory。系统与 HM stateVersion 保持 25.11，账号 UID 沿用原声明的自动分配，未重分配实机 UID 1000。

flake 求值、完整主机构建与系统隔离检查通过。磁盘、账号、启动、stateVersion、secret owner/mode/path 不变量相同；独立 modprobe 配置行发生排序变化，去除空行后逐行集合一致。独立 reviewer 未发现回归，建议补充的 greeter/Intel graphics 断言已纳入。

`checks.system-boundaries` 对 x86_64/aarch64 的内部无头维护 fixture 强制检查无桌面/greeter/GPU/笔记本电源/代理/TUN信任/个人账号及授权/秘密/入站SSH，并以误选 laptop-network 的负例证明守卫可拒绝泄漏。仅为 ARM 求值检查和 x86 检查产物构建，没有 ARM 系统构建或部署；账号绑定隔离仍由后续生产功能组合检查补齐。

## 批次 3：命令行工作台

`command-line` 一次选择配置 Zsh、Git/gh/delta/lazygit、direnv、查包、tmux、Yazi、监视及 CLI 工具，并只向目标宿主提供 shell 注册。Git 身份留在个人 identity；DeepSeek 的运行时文件读取留在真实账号绑定；Java selectors 随 Java 功能，而非任意 shell。

`terminal` 消费类型化 appearance，为 Kitty 生成唯一完整配置，Noctalia Kitty 模板已停用。默认工具使用共享 argv wrapper；CLI 编辑器仍为 Neovim，GUI 文本默认仍为 VS Code，Mango/Thunar/MIME 入口接入相同默认值。tmux 导航使用 Ctrl+a 前缀，并在显式重载时释放旧 root Alt 绑定，保留插件、恢复、图像透传、复制与 cwd。

重新求值、treefmt、完整主机构建、`checks.workspace-composition` 和 `checks.command-line-runtime` 通过。组合检查使用实际生产 aspect，覆盖两主机两账号、共享宿主、移除最后 consumer、无桌面/Java/秘密读取/设备授权；隔离程序检查覆盖 Kitty parser/ANSI/字号/不透明度、Zsh 语法、真实 tmux 键表、中文空格 cwd 与含引号/空参数/美元符号的 argv、Thunar helper、实际 home/system profile desktop IDs 和 MIME。

独立 reviewer 发现迁移脚本误改 `...` 别名，已恢复并重新构建检查；无剩余阻塞。只读确认现有 Kitty 主配置仅旧两条 include，没有额外手工设置；没有修改真实 Home。Kitty 文件备份/接管、Noctalia 实际 apply、GUI/Alt 键盘效果仍需应用后验收。

## 批次 4：完整编辑器与语言

完整 Neovim 配置、包配方、插件/parser、Diffview 与专项测试已收拢到 `aspects/editing/neovim/`，没有使用隔离样本覆盖丰富 Lua。共享 palette 与语言贡献生成 `mayon.generated`；Lua 继续拥有高亮、handlers、Python 环境选择、MATLAB 通知/设置和编辑行为。语言工具包与有序 server/formatter/linter 数据随显式 support 选择，编辑器只消费，不反向启用语言。VS Code 和三个 JetBrains 继续保留，所需 nix-ld 共享支持由功能投递；Java 环境/Gradle/selectors 随 Java。

重新求值、treefmt、完整 host、普通/dev 包、Neovim 全部原专项检查及 editor composition 构建通过。生产 Neovim 的空语言/C++ 独立组合通过；有序 cmd/root/formatter 冲突负例被拒绝，filetypes 按集合合并。真实 CSS LS 对临时项目未保存内容发布诊断，Conform 调用真实 StyLua 完成格式化；普通入口忽略配置覆盖、dev 使用源码覆盖并找到生成数据的检查通过。独立 reviewer 未发现漏迁或回归。

没有测试 MATLAB 本体/授权、AI 网络请求、IDE GUI、Kitty 图像或所有用户项目；用户安装树、授权、历史、会话、草稿与缓存均未迁移或删除。

## 应用后验收

未执行系统应用。文件归属交接、旧持久用户 unit 停用、重登录环境、GUI/设备、休眠与游戏验证仍按专项设计执行，不能由构建结果替代。
