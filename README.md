# nix-dotfiles

NixOS + Home Manager 配置，单主机 `nixos-btw`（Intel + NVIDIA 笔记本，2560×1600 @ 165 Hz，niri 合成器）。

- **框架**：flake-parts
- **通道**：`nixpkgs` = nixos-26.05（稳定），`nixpkgs-unstable` = nixos-unstable
- **Home Manager**：作为 NixOS 模块运行，不是 standalone

配置约定和踩坑记录见 [CLAUDE.md](CLAUDE.md)（未纳入版本库，仅本地）。

## 日常命令

```sh
nr                  # 重建系统（nh os switch，含 home-manager）
nc                  # 清理旧世代（每周自动跑一次，保留最近 5 个和 14 天内的）
nix fmt             # 格式化全部 .nix（nixfmt + deadnix + statix，走 treefmt）
nix develop         # 开发 shell：git、gnumake、clang-tools、sops
nix develop .#cuda  # CUDA 工具链单独一个 shell
```

底层命令（`nr` 出问题时用）：

```sh
sudo nixos-rebuild switch --flake .#nixos-btw
```

**改完配置必须重建才生效** —— 编辑 `~/.config/` 下的文件没有意义，见下节。

## 目录结构

```
flake.nix              inputs 与 flake-parts 编排
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
    wm/niri/           niri 配置（单个 KDL 字符串）、noctalia
    programs/
      apps/            浏览器、mpv、截图、yazi、IM 等
      dev/             编辑器、语言工具链、direnv、git
      games/           prismlauncher
      terminal/        foot、tmux
    shell/             zsh（无框架）、starship、zoxide
    services/          剪贴板桥接、cliphist
    packages.nix       用户级 CLI 工具
  system/              → NixOS
    core/              boot、locale、网络、nix 设置
    desktop/           niri、xdg portal、greetd
    hardware/          nvidia（PRIME offload）、音频、蓝牙、固件
    programs/          clash、nix-ld、thunar 等
    security/          polkit、sops
    services/          earlyoom、openssh、docker
    user/              用户、字体、环境变量
    virtualisation/    libvirt/KVM
nixvim/                Neovim 配置（nixvim 模块树，45 个插件模块）
secrets/secrets.yaml   sops 加密的 API key（可安全提交）
```

### 自动导入：加文件就够了

`lib/import-dir.nix` 里的 `importDir` **递归导入目录下每一个 `.nix`**，`modules/home/` 进 Home Manager，`modules/system/` 进 NixOS。新增模块不需要在任何地方登记，丢个文件进去即可。

**它没有排除机制** —— 连下划线前缀都不跳过。`modules/home/_assets/` 和 `wm/niri/_plugins/` 之所以没被当成模块导入，纯粹因为里面没有 `.nix` 文件。

这就是 **`nixvim/` 放在仓库根目录而不是 `modules/` 下**的原因：那 45 个文件是 nixvim 模块，不是 Home Manager 模块，放进去会被逐个加载然后全部报错。只有 `modules/home/programs/dev/nvim.nix` 一个文件伸手去引用它。

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
~/.config/emacs/       真目录（12 项里只有 init.el、early-init.el 是 store 链接）
~/.config/niri/        真目录（config.kdl 是链接）
~/.config/foot/        真目录（foot.ini 是链接）
~/.config/noctalia/    真目录（1/4 是链接）
~/.config/yazi/        真目录（3/6 是链接）
```

这类由 `xdg.configFile."emacs/init.el".source = ...` 产生 —— 路径里带了文件名，HM 就只建这一个链接，父目录保持可写。

**这个区别决定了应用能不能保存自己的运行时状态**：noctalia 要写 `settings.toml`、Emacs 要写 `custom.el` 和 `personal.el`、niri 要写会话数据。要是把它们的整个目录都链成 store，这些全都会失败。

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

**注意**：systemd 用户服务不会 source zsh profile，所以守护进程拿不到这些环境变量，得直接读 `/run/secrets/<name>`（Emacs 的 gptel 就是这么做的）。

## 修改流程

1. 改 `modules/` 下对应的 `.nix`
2. `nix fmt`
3. `nix build --no-link .#nixosConfigurations.nixos-btw.config.system.build.toplevel` —— 先构建再切换，能提前看到 `evaluation warning:`（nixpkgs 的弃用提示都在这里）
4. `nr` 切换
5. 有些东西需要额外一步才生效：

| 改了什么 | 还要做 |
|---|---|
| fcitx5 配置 | `systemctl --user restart app-org.fcitx.Fcitx5@autostart.service`（**不是** `fcitx5-daemon`，那个是登录时竞争失败的那份） |
| Emacs 配置 | `systemctl --user restart emacs` |
| nvim 配置 | 无，重建即生效 |
| niri 配置 | `niri msg action load-config` 或重登 |
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

`flake.lock` 更新后想知道有没有东西要改：构建输出里的 `evaluation warning:` 就是答案，它会点名被弃用的属性和位置。
