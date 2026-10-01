# 输入和包来源

编辑 `flake.nix`、`flake/system.nix` 或切换包来源时读取。本表描述迁移时的结构，
具体版本由当前 `flake.lock` 与模块决定；更新后同步变更的结论。

| 来源 | 当前用途与约束 |
|---|---|
| `nixpkgs` | stable 系统与多数用户包 |
| `nixpkgs-unstable` | 快速更新或 stable 缺少的单包 |
| `home-manager` | release-26.05，NixOS 模块方式 |
| `nixvim`、`mcp-hub` | 编辑器模块及 MCP 二进制，nvim 有独立包集合 |
| `noctalia` | 跟随 `nixpkgs-unstable` |
| `noctalia-plugins-official`、`noctalia-plugins-community` | `flake = false` 源树，经 `kind = "path"` 使用 |
| `sops-nix`、`nix-index-database` | 运行时秘密、预构建命令索引 |
| `flake-parts`、`treefmt-nix` | 输出结构、格式检查 |

以下五个输入保持各自 nixpkgs pin，不添加 `follows`：

- `mango`：mango/scenefx/wlroots 组合必须匹配。
- `noctalia-greeter`、`mark-shot`、`wayscrollshot`：源码按自己的依赖组合构建。
- `llm-agents`：自身 pin 对应 `cache.numtide.com` 预构建产物。

不要把所有没有 `follows` 的输入归为同一类；无 nixpkgs 输入的源码树不需要去重。

当前单属性例外的调用点：

- `modules/home/packages.nix`：Copilot CLI、Typora。
- `modules/home/programs/dev/java.nix`、`modules/home/base/session-vars.nix`、
  `modules/home/programs/games/prismlauncher.nix`：Java 26，三处同步。
- `modules/home/programs/apps/im.nix`：QQ / WeChat。
- `modules/home/programs/dev/antigravity.nix`：`antigravity-ide-fhs`——stable
  26.05 没有该属性，FHS 变体供 IDE 扩展与语言服务器加载；同文件的 CLI 走
  `llm-agents`，不占 unstable。
- `flake.nix`：overlay 替换 `xdg-desktop-portal-wlr`。NixOS 模块硬编码该属性到
  extraPortals 和 ExecStart，不能另加第二个不同版本的 backend。
- `modules/system/hardware/nvidia.nix`：用当前系统的 kernelPackages.callPackage
  调用 unstable 的 NVIDIA recipe，内核与其余依赖仍来自系统集合。

输入数量不能直接代表闭包大小。修改 overlay 后检查实际受影响的 derivation，
不要仅为减少一次求值牺牲兼容性或缓存命中。
