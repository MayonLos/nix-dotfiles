# nix-dotfiles

NixOS + Home Manager 配置，单主机 `nixos-btw`（Intel + NVIDIA 笔记本，2560×1600 @ 165 Hz，mango 合成器）。

- **框架**：flake-parts
- **通道**：`nixpkgs` = nixos-26.05（稳定），`nixpkgs-unstable` = nixos-unstable
- **Home Manager**：作为 NixOS 模块运行，不是 standalone

仓库工作流以 **Codex** 为入口：[AGENTS.md](AGENTS.md) 放公共约定，
十个领域技能在 [.agents/skills/](.agents/skills/)，详细排障资料按需从技能的 `references/` 读取。
技能不是配置真相的替代品：版本以 `flake.lock` 为准，行为以当前模块和实际验证为准。

## Codex 工作流

在仓库目录启动 `codex`。Codex 自动发现 `.agents/skills/`；
可用 `/skills` 查看，或在请求中显式写 `$nix-modules` 等技能名。
共享的项目配置在 [.codex/config.toml](.codex/config.toml)，
只设置子代理启用与并发；主模型、账号与权限仍使用个人配置。
项目配置受 Codex 的仓库信任机制控制，未信任时可能不加载。

三个原生代理角色在 [.codex/agents/](.codex/agents/)：

| 角色 | 用途 | 模型 |
|---|---|---|
| `luna-review` | 小范围只读审核、资料核对 | `gpt-6-luna` |
| `luna-worker` | 已明确范围的小改动 | `gpt-6-luna` |
| `reviewer` | 跨模块独立复核 | 继承主代理 |

例如：“审核最近的改动，让 luna-review 检查文档与模块是否一致，主代理复核结论。”
实现任务先划分互不重叠的文件，主代理合并检查；没有必要时不拆任务。
角色和技能未刷新时重开会话。只读角色也明确禁止编辑，不把 sandbox 默认值当成绝对保证：
当前会话的权限覆盖可能优先于角色配置。

旧的 Claude 技能、CLI 包装代理和 `CLAUDE.md` 已移出共享工作流；
个人的 Claude 设置、登录状态和已安装软件不由此次迁移改动。
目录与角色格式依据 [官方技能说明](https://learn.chatgpt.com/docs/build-skills)
及 [子代理说明](https://learn.chatgpt.com/docs/agent-configuration/subagents)。

## 日常命令

```sh
nr                  # 重建系统（nh os switch，含 home-manager）
nc                  # 清理旧世代（每周自动跑一次，保留最近 5 个和 14 天内的）
nix fmt             # 格式化全部 .nix（nixfmt + deadnix + statix，走 treefmt）
nix develop         # 开发 shell：git、gnumake、clang-tools、sops、age、ssh-to-age
nix develop .#cuda  # CUDA 工具链单独一个 shell
```

底层命令（`nr` 出问题时用）：

```sh
sudo nixos-rebuild switch --flake .#nixos-btw
```

声明式配置修改需重建才生效；应用维护的可写运行时配置可以即时修改，见下节。

## 目录结构

```
flake.nix              inputs 与 flake-parts 编排
AGENTS.md              Codex 常驻约定与领域技能索引
.agents/skills/        Codex 领域技能与按需 references
.codex/               共享项目配置与原生子代理角色
flake/
  system.nix           NixOS + Home Manager 接线，自动导入 modules/
  dev.nix              开发 shell、treefmt 配置
hosts/nixos-btw/
  default.nix          主机入口，自动导入 modules/system/
  hardware.nix         nixos-generate-config 产物
lib/
  default.nix          导出 importDir
  import-dir.nix       递归导入一个目录下所有 .nix
modules/
  home/                → Home Manager（用户 mayon）
    base/              身份、GTK、Qt、输入法、XDG、会话变量、Xresources
    wm/mango/          mango 配置（key=value，由 Nix 生成）、noctalia
    programs/
      apps/            浏览器、mpv、截图、yazi、IM 等
      dev/             编辑器、语言工具链、direnv、git
      games/           prismlauncher
      terminal/        kitty、tmux
    shell/             zsh（无框架）、starship、zoxide
    services/          剪贴板桥接、cliphist
    packages.nix       用户级 CLI 工具
  system/              → NixOS
    core/              boot、locale、网络、nix 设置
    desktop/           mango、xdg portal、greetd、gamemode
    hardware/          nvidia（PRIME offload）、音频、蓝牙、固件
    programs/          clash、nix-ld、thunar 等
    security/          polkit、sops
    services/          earlyoom、openssh、docker、systemd
    user/              用户、字体、环境变量
    virtualisation/    libvirt/KVM
nixvim/                Neovim 配置（显式 imports 的 nixvim 模块树）
secrets/secrets.yaml   sops 加密的 API key（可安全提交）
```

### 自动导入：加文件就够了

`lib/import-dir.nix` 里的 `importDir` **递归导入目录下每一个 `.nix`**，`modules/home/` 进 Home Manager，`modules/system/` 进 NixOS。新增模块不需要在任何地方登记，丢个文件进去即可。

**它没有排除机制** —— 连下划线前缀都不跳过。资源目录只有在不含 `.nix` 文件时才不会被当成模块导入。

这就是 **`nixvim/` 放在仓库根目录而不是 `modules/` 下**的原因：这里是 nixvim 模块，不是 Home Manager 模块。由 `modules/home/programs/dev/nvim.nix` 统一引用。

## 软链接：哪些能改，哪些不能

Home Manager 把配置文件从 `/nix/store` 链接到家目录。**store 里的东西是只读的**，所以直接编辑 `~/.config/...` 要么失败，要么在下次重建时被覆盖。

但链接的**粒度**有两种，区别很大：

### 整个目录被链接 → 应用无法在里面写任何东西

```
~/.config/fcitx5      → /nix/store/…（只读目录）
~/.Xresources         → /nix/store/…
~/.zshrc              → /nix/store/…
~/.config/mimeapps.list → /nix/store/…
```

这类由 `xdg.configFile."fcitx5".source = <整个目录>` 产生。后果是**连临时试验都做不了** —— 想改一行 fcitx5 配置试试效果，只能改 Nix 然后重建。

### 真目录里只链接了个别文件 → 应用可以在旁边写

```
~/.config/mango/       真目录（config.conf 是链接，noctalia.conf 由主题模板写入）
~/.config/kitty/       真目录（mayon.conf 是链接；kitty.conf 和主题文件可写）
~/.config/noctalia/    真目录（具体文件的归属见 noctalia.nix）
~/.config/yazi/        真目录（声明式配置和运行时状态共存）
```

这类由 `xdg.configFile."kitty/mayon.conf".source = ...` 产生 —— 路径里带了文件名，HM 就只建这一个链接，父目录保持可写。

**这个区别决定了应用能不能保存自己的运行时状态**：noctalia 要写 `settings.json`，主题模板要往 `~/.config/mango/noctalia.conf` 里渲染配色。要是把它们的整个目录都链成 store，这些全都会失败。

> 需要「配置进版本库、同时又能即时编辑」时，用 `config.lib.file.mkOutOfStoreSymlink` 链到仓库里的真实路径。本仓库目前没有用到这种模式。

### 判断某个路径属于哪种

```sh
ls -la ~/.config/foo          # 是链接还是目录
readlink ~/.config/foo        # 指向 store 就是只读
find ~/.config/foo -maxdepth 1 -type l -lname '/nix/store/*'
```

## 密钥

API key 用 sops-nix 加密存在 `secrets/secrets.yaml`（**可以安全提交**），重建时解密到 `/run/secrets/<name>`，属主 `mayon`。

- 解密用主机 SSH ed25519 密钥；编辑用你的个人 age 密钥（`~/.config/sops/age/keys.txt`）
- 配置在 `modules/system/security/sops.nix`，收件人在 `.sops.yaml`
- shell 通过 `modules/home/shell/zsh.nix` 导出成环境变量

加一个新 key：

```sh
sops secrets/secrets.yaml            # 编辑
# 然后在 sops.nix 加 secrets.<name>.owner，在 zsh.nix 的循环里加 <name>:ENV_VAR
```

**注意**：systemd 用户服务和桌面启动的应用不会 source 交互式 zsh 初始化，不能依赖这些变量；
可直接读 `/run/secrets/<name>`。

## 修改流程

1. 改对应配置并检查 `git diff`；新文件需进入 Git flake 的源集合
2. `nix fmt`
3. `nix flake check --no-build --no-write-lock-file` 求值，再按影响构建相关输出或 `nix build --no-link .#nixosConfigurations.nixos-btw.config.system.build.toplevel`；求值通过不等于构建或运行时通过
4. 需要应用配置时用 `nr` 切换；仅工作流文档和技能变更不需要重建系统
5. 有些东西需要额外一步才生效：

| 改了什么 | 还要做 |
|---|---|
| fcitx5 配置 | `systemctl --user restart app-org.fcitx.Fcitx5@autostart.service`（**不是** `fcitx5-daemon`，那个是登录时竞争失败的那份） |
| nvim 配置 | 无，重建即生效 |
| mango 配置 | `Super+Alt+R`（reload_config）或重登；键位、窗口规则、动画都能热重载 |
| QQ 的 wrapper | 从托盘完全退出再开 |

## 排查

```sh
# 构建报错但看不出哪里
nix build --show-trace .#nixosConfigurations.nixos-btw.config.system.build.toplevel

# 某个选项最终的值是什么
nix eval .#nixosConfigurations.nixos-btw.config.<option.path>

# 某个包的闭包多大、被什么撑着
nix path-info -Sh <store-path>
nix path-info -rS <store-path> | sort -k2 -rn | head

# 回退到上一个世代
sudo nixos-rebuild switch --rollback
```

`flake.lock` 更新后检查 `evaluation warning:` 和构建结果，再验证受影响的运行时行为；
没有弃用提示不代表没有兼容性问题。
