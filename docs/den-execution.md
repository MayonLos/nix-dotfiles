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

## 应用后验收

未执行系统应用。文件归属交接、旧持久用户 unit 停用、重登录环境、GUI/设备、休眠与游戏验证仍按专项设计执行，不能由构建结果替代。
