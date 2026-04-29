# Nix Dotfiles 目录结构重构设计

## 背景

当前配置存在边界模糊（`host/` vs `home/` vs `system/`）、文件查找困难（命名不直观、导入链混乱）、flakes 部分游离（`dev/` 未接 perSystem）等问题。采用 flake-parts 标准化重构，单主机为主预留多机扩展。

## 语义边界

| 术语 | 含义 | 位置 |
|---|---|---|
| `flake/` | flake-parts 子模块，拆分 `flake.nix` 用 | 顶层 |
| `hosts/` | 主机组装层，不是可复用模块 | 顶层 |
| `modules/` | 内部可复用 NixOS / HM 配置模块 | 顶层 |
| `lib/` | 纯 Nix 辅助函数 | 顶层 |
| `flakeModules/` | 对外导出的 flake-parts 公开模块 | 顶层，当前为空 |
| `_assets/` | 静态资源，`_` 前缀防 glob 导入 | `modules/home/` 下 |
| `perSystem` | flake-parts 多架构 packages/devShells/checks | `flake/dev.nix` |
| `withSystem` | 从 perSystem 桥接 pkgs 到 nixosSystem | `flake/system.nix` |

## 目录树

```
nix-dotfiles/
│
├── flake.nix                         # 极瘦入口：inputs + mkFlake + imports
├── flake.lock                        # 锁定文件（自动生成）
├── .gitignore
│
├── flake/                            # flake-parts 子模块（拆分 flake.nix 用）
│   ├── system.nix                    # nixosConfigurations 定义（withSystem 桥接）
│   ├── home.nix                      # homeConfigurations 定义（独立 HM 用，预留）
│   └── dev.nix                       # perSystem.devShells（cuda 等）
│
├── hosts/                            # 主机组装层（顶层，不嵌套）
│   └── nixos-btw/
│       ├── default.nix               # 主机组装点：导入 modules/system/ 下所需模块
│       └── hardware.nix              # nixos-generate-config 生成，文件系统/内核模块
│
├── modules/                          # 内部可复用模块（按抽象层划分为 system / home）
│   ├── system/                       # --- NixOS 系统层模块 ---
│   │   ├── core/
│   │   │   ├── default.nix           # 聚合导入 boot/network/nix/locale
│   │   │   ├── boot.nix              # systemd-boot, kernel, 文件系统
│   │   │   ├── network.nix           # NetworkManager, firewall, IPv6
│   │   │   ├── nix.nix               # nix.settings, gc, substituters
│   │   │   └── locale.nix            # timezone, i18n
│   │   │
│   │   ├── desktop/
│   │   │   ├── default.nix           # 聚合导入 niri/gamemode/xdg
│   │   │   ├── niri.nix              # programs.niri + niri-session patch
│   │   │   ├── gamemode.nix          # programs.gamemode
│   │   │   └── xdg.nix               # xdg.portal 等系统级 XDG 配置
│   │   │
│   │   ├── hardware/
│   │   │   ├── default.nix           # 聚合导入 GPU/音频/固件
│   │   │   ├── cuda.nix              # NVIDIA CUDA 支持
│   │   │   ├── audio.nix             # PipeWire 音频
│   │   │   └── firmware.nix          # CPU microcode, 设备固件
│   │   │
│   │   ├── programs/                 # 系统级程序（非用户级 home-manager 管）
│   │   │   ├── default.nix           # 聚合导入
│   │   │   ├── libreoffice.nix       # libreoffice
│   │   │   ├── thunar.nix            # thunar 文件管理器
│   │   │   ├── gamescope.nix         # gamescope
│   │   │   ├── zsh.nix               # 系统级 zsh（programs.zsh.enable）
│   │   │   └── clash.nix             # Mihomo/clash 代理
│   │   │
│   │   ├── security/
│   │   │   └── default.nix           # sudo, polkit, gnupg-agent
│   │   │
│   │   ├── services/
│   │   │   └── default.nix           # openssh, docker, thermald, upower
│   │   │
│   │   └── users/
│   │       └── default.nix           # users.users.mayon 定义（groups, shell）
│   │
│   └── home/                         # --- Home Manager 用户层模块 ---
│       ├── users/
│       │   └── mayon/
│       │       └── default.nix       # mayon 用户的 HM 入口：导入下方各功能模块
│       │
│       ├── base/
│       │   ├── default.nix           # 聚合导入
│       │   ├── user.nix              # username, homeDirectory, stateVersion
│       │   ├── session-vars.nix      # sessionVariables (NIXOS_OZONE_WL 等)
│       │   ├── xdg.nix               # 用户级 XDG 目录/默认应用
│       │   ├── input-method.nix      # 输入法配置
│       │   └── ui.nix                # GTK/Qt 主题, 光标, 字体
│       │
│       ├── packages.nix              # 用户包集合（home.packages 清单）
│       │
│       ├── wm/
│       │   └── niri/
│       │       ├── default.nix       # 聚合导入
│       │       ├── autostart.nix     # niri 自启动程序
│       │       ├── keybinds.nix      # 快捷键绑定
│       │       ├── rules.nix         # 窗口规则
│       │       └── settings.nix      # niri 常规设置
│       │
│       ├── programs/
│       │   ├── apps/
│       │   │   ├── firefox.nix       # Firefox 浏览器
│       │   │   ├── mpv.nix           # mpv 播放器
│       │   │   ├── noctalia.nix      # Noctalia 桌面 shell
│       │   │   ├── obsidian.nix      # Obsidian 笔记
│       │   │   ├── thunar-terminal.nix # Thunar 终端集成
│       │   │   ├── yazi.nix          # yazi 文件管理器
│       │   │   └── zathura.nix       # zathura PDF 阅读器
│       │   ├── dev/
│       │   │   ├── git.nix           # Git 配置
│       │   │   ├── latex.nix         # LaTeX 环境
│       │   │   └── vscode.nix        # VS Code
│       │   └── terminal/
│       │       ├── foot.nix          # foot 终端模拟器
│       │       └── tmux.nix          # tmux 复用器
│       │
│       ├── shell/
│       │   ├── default.nix           # 聚合导入
│       │   └── zsh.nix               # zsh 配置（programs.zsh, oh-my-zsh 等）
│       │
│       ├── services/
│       │   ├── default.nix           # 聚合导入
│       │   ├── clipboard.nix         # wl-clipboard
│       │   └── cliphist.nix          # cliphist 剪贴板历史
│       │
│       └── _assets/                  # 静态资源（_ 前缀 = 非模块，不参与导入）
│           └── wallpaper/            # 壁纸文件（.jpg/.png）
│
├── lib/                              # 纯 Nix 辅助函数库
│   └── default.nix                   # mkUser, mkHost 等辅助函数（当前可空）
│
└── flakeModules/                     # 对外导出的 flake-parts 模块（公开 API）
    └── .keep                         # 预留，当前为空
```

## 各节点职责

| 路径 | 职责 |
|---|---|
| `flake.nix` | 声明 inputs，调用 `mkFlake`，导入 `flake/` 下的子模块 |
| `flake/system.nix` | 用 `withSystem` 拿到 pkgs，定义 `nixosConfigurations`，组装 NixOS + HM 模块 |
| `flake/home.nix` | 定义 `homeConfigurations`（独立 HM 模式，当前预留） |
| `flake/dev.nix` | 在 `perSystem.devShells` 中定义 cuda 等 dev shell |
| `hosts/nixos-btw/default.nix` | 单主机的组装入口，按需导入 `modules/system/` 下的模块 |
| `hosts/nixos-btw/hardware.nix` | `nixos-generate-config` 产物，文件系统挂载与内核模块 |
| `modules/system/core/` | 系统核心：boot、网络、nix 设置、时区语言 |
| `modules/system/desktop/` | 桌面会话：niri WM、gamemode、XDG portal |
| `modules/system/hardware/` | 硬件支持：CUDA、音频、CPU 微码 |
| `modules/system/programs/` | `environment.systemPackages` 管的全系统程序 |
| `modules/system/security/` | 安全策略：sudo rules、polkit |
| `modules/system/services/` | 系统后台服务：sshd、docker、thermald、upower |
| `modules/system/users/` | `users.users.<name>` 顶层声明 |
| `modules/home/users/mayon/` | mayon 用户的 HM 入口，导入下方所有功能模块 |
| `modules/home/base/` | HM 基础：用户名、家目录、环境变量、XDG、主题 |
| `modules/home/packages.nix` | `home.packages` 用户包清单 |
| `modules/home/wm/niri/` | niri 窗口管理器的 HM 配置 |
| `modules/home/programs/` | 用户程序 HM 配置，按类别分 apps/dev/terminal |
| `modules/home/shell/` | Shell 配置（zsh） |
| `modules/home/services/` | 用户 systemd 服务（clipboard, cliphist） |
| `modules/home/_assets/` | 壁纸等静态资源，`_` 前缀确保不被 glob 导入 |
| `lib/` | 纯函数库，`mkUser`、`mkHost` 等复用的 Nix 表达式 |
| `flakeModules/` | 真正公开的 flake-parts 模块，供其他 flake 消费 |

## 代码骨架

### `flake.nix`

```nix
{
  description = "NixOS from Scratch";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    MyNixvim = {
      url = "github:MayonLos/nixvim";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    niri.url = "github:sodiboo/niri-flake";

    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
      inputs.noctalia-qs.follows = "noctalia-qs";
    };

    noctalia-qs = {
      url = "github:noctalia-dev/noctalia-qs";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    claude-code.url = "github:sadjow/claude-code-nix/v2";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];
      imports = [
        ./flake/system.nix
        ./flake/home.nix
        ./flake/dev.nix
      ];
    };
}
```

### `flake/system.nix`

```nix
{ withSystem, inputs, ... }:
let
  pkgs-unstable-for = system:
    import inputs.nixpkgs-unstable {
      inherit system;
      config.allowUnfree = true;
      overlays = [ inputs.claude-code.overlays.default ];
    };
in
{
  flake.nixosConfigurations.nixos-btw = withSystem "x86_64-linux" (
    { pkgs, ... }:
    inputs.nixpkgs.lib.nixosSystem {
      inherit pkgs;
      specialArgs = {
        inherit inputs;
        pkgs-unstable = pkgs-unstable-for "x86_64-linux";
      };
      modules = [
        inputs.niri.nixosModules.niri
        ./hosts/nixos-btw
        inputs.home-manager.nixosModules.home-manager
        {
          nixpkgs.config.allowUnfree = true;
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = {
              inherit inputs;
              pkgs-unstable = pkgs-unstable-for "x86_64-linux";
            };
            users.mayon = import ./modules/home/users/mayon;
            backupFileExtension = "backup";
          };
        }
      ];
    }
  );
}
```

### `flake/dev.nix`

```nix
{ ... }:
{
  perSystem = { pkgs, ... }: {
    devShells = {
      cuda = pkgs.mkShell {
        name = "cuda-dev";
        packages = with pkgs; [
          cudaPackages.cudatoolkit
          cudaPackages.cudnn
          linuxKernel.packages.linux_zen.nvidia_x11
        ];
        shellHook = ''
          export CUDA_PATH=${pkgs.cudaPackages.cudatoolkit}
        '';
      };
      default = pkgs.mkShell {
        name = "default-dev";
        packages = with pkgs; [
          git
          gnumake
          clang-tools
        ];
      };
    };
  };
}
```

### `flake/home.nix`

```nix
{ ... }:
{
  flake.homeConfigurations = { };
}
```

## flake-parts 可选模块评估

以下梳理 flake-parts 生态中所有可选模块，标注当前采纳状态及理由。

### 必选（本次重构即纳入）

#### `home-manager.flakeModules.home-manager`

- **来源**：`github:nix-community/home-manager`（25.05+ 内置）
- **作用**：提供 `flake.homeConfigurations` 和 `flake.homeModules` 选项，类型安全的 HM 集成
- **采纳理由**：替代当前 `flake/system.nix` 中手动调用 `inputs.home-manager.nixosModules.home-manager` + 内联配置块的旧式写法。HM 配置通过 flake-parts 类型系统分发，NixOS 模块和 HM 模块不会互相误导入
- **用法**：`flake.nix` 的 `imports` 中加入 `inputs.home-manager.flakeModules.home-manager`

#### `treefmt-nix.flakeModule`

- **来源**：`github:numtide/treefmt-nix`
- **作用**：统一多 formatter 管理（alejandra、nixfmt、deadnix、statix、prettier 等），自动挂载到 `nix fmt` 和 `nix flake check`
- **采纳理由**：dotfiles 仓库的核心资产是 .nix 文件，统一格式化保证风格一致，`nix flake check` 自动校验
- **用法**：添加 `treefmt-nix` input → `imports` 中加 `inputs.treefmt-nix.flakeModule` → 配置 `perSystem.treefmt.programs`

---

### 可选（按需触发，暂不启用）

#### `easyOverlay`

- **来源**：`flake-parts.flakeModules.easyOverlay`（内置）
- **作用**：声明式定义 overlay，取代手动 `import nixpkgs { overlays = [...]; }`
- **暂不启用理由**：当前仅有一个 claude-code overlay，手动 `import` 写法已足够简单。当 overlay 数量 ≥3 且需要跨主机差异化时再启用

#### `modules`

- **来源**：`flake-parts.flakeModules.modules`（内置）
- **作用**：为 flake 提供 `flake.modules` 选项，按 module class（`nixos`、`homeManager`、`darwin`、`generic`）归类发布可复用模块
- **暂不启用理由**：当前配置是自用的单机 dotfiles，没有对外发布模块的需求。当需要将 `modules/system/` 或 `modules/home/` 下的模块打包供其他 flake 消费时启用

#### `flakeModules`

- **来源**：`flake-parts.flakeModules.flakeModules`（内置）
- **作用**：提供 `flake.flakeModules` 选项，发布 flake-parts 模块供其他 flake 的 `imports` 使用
- **暂不启用理由**：同 `modules`，没有对外发布需求。当需要将 `flake/` 下的某个 flake-parts 子模块（如 `flake/dev.nix`）抽象为可复用发布时启用

---

### 预留（未来可能引入）

#### `git-hooks-nix`

- **来源**：`github:cachix/git-hooks.nix`
- **作用**：管理 pre-commit hooks（nixfmt-check、deadnix、statix、shellcheck 等），`nix flake check` 时跑
- **预留理由**：当团队协作或 CI 接入时启用，单机自用收益不大

#### `agenix-rekey` / `agenix-shell`

- **来源**：`github:oddmario/agenix-rekey` / agenix 生态
- **作用**：secret 管理和 rekey 工作流
- **预留理由**：当前配置中无可感知的 secret（SSH 密钥手工管理），当需要托管 API token 或部署密钥时考虑

#### `disko`

- **来源**：`github:nix-community/disko`
- **作用**：声明式磁盘分区和格式化
- **预留理由**：当前系统已安装运行，不需要重新分区。换硬件/重装时启用

#### `nix-unit`

- **来源**：`github:nix-community/nix-unit`
- **作用**：Nix 模块的单元测试框架
- **预留理由**：当 `lib/` 中出现复杂函数或 `modules/` 中出现条件分支密集的模块时启用

#### `process-compose-flake`

- **来源**：`github:Platonic-Systems/process-compose-flake`
- **作用**：为 devShell 定义多进程服务编排（类似 docker-compose）
- **预留理由**：当前 devShell 不需要多进程启动，当 CUDA 开发需要同时跑数据库/缓存时启用

#### `pkgs-by-name-for-flake-parts`

- **来源**：`github:QuotS/pkgs-by-name-for-flake-parts`
- **作用**：自动从 `pkgs/by-name/` 目录结构扫描并注册 packages
- **预留理由**：当前没有自定义 package 需要管理，当有自维护的衍生品时启用

#### `nix-topology`

- **来源**：`github:oddmario/nix-topology`
- **作用**：自动生成 NixOS 系统拓扑图（硬件、服务、网络关系）
- **预留理由**：文档可视化需求，当前规模不需要

---

### 不纳入

#### `devenv`、`devshell`

- **不纳理由**：flake-parts 自带的 `perSystem.devShells` 已满足需求，devenv/devshell 引入额外抽象层和依赖，且与 treefmt-nix、git-hooks-nix 的集成路径与内置方案不兼容

#### `std`、`ez-configs`、`easy-hosts`、`mission-control`

- **不纳理由**：这些是替代性的全栈框架，与已选的 flake-parts 原生方案竞争而非互补。引入会造成两套体系共存

#### `dream2nix`、`haskell-flake`、`rust-flake`、`pydev`、`ocaml-flake`

- **不纳理由**：语言专属框架，当前配置不涉及对应语言的项目管理

#### `github-actions-nix`、`gitlab-ci`、`hercules-ci-effects`

- **不纳理由**：CI/CD 专属，当前配置没有 CI 管线

---

### `flake.nix` 调整（纳入必选项后）

```nix
outputs = inputs:
  inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    systems = [ "x86_64-linux" ];
    imports = [
      ./flake/system.nix
      ./flake/home.nix
      ./flake/dev.nix
      inputs.home-manager.flakeModules.home-manager
      inputs.treefmt-nix.flakeModule
    ];
  };
```

### `flake/system.nix` 调整（启用 HM flakeModule 后）

启用 `home-manager.flakeModule` 后，HM 配置块从内联移至 `flake.homeConfigurations` 选项，`system.nix` 只保留 NixOS 层的组装：

```nix
{ withSystem, inputs, ... }:
let
  pkgs-unstable-for = system:
    import inputs.nixpkgs-unstable {
      inherit system;
      config.allowUnfree = true;
      overlays = [ inputs.claude-code.overlays.default ];
    };
in
{
  flake.nixosConfigurations.nixos-btw = withSystem "x86_64-linux" (
    { pkgs, ... }:
    inputs.nixpkgs.lib.nixosSystem {
      inherit pkgs;
      specialArgs = {
        inherit inputs;
        pkgs-unstable = pkgs-unstable-for "x86_64-linux";
      };
      modules = [
        inputs.niri.nixosModules.niri
        ./hosts/nixos-btw
        inputs.home-manager.nixosModules.home-manager
        {
          nixpkgs.config.allowUnfree = true;
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = {
              inherit inputs;
              pkgs-unstable = pkgs-unstable-for "x86_64-linux";
            };
            users.mayon = import ./modules/home/users/mayon;
            backupFileExtension = "backup";
          };
        }
      ];
    }
  );

  flake.homeConfigurations.mayon = withSystem "x86_64-linux" (
    { pkgs, ... }:
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [ ./modules/home/users/mayon ];
      extraSpecialArgs = {
        inherit inputs;
        pkgs-unstable = pkgs-unstable-for "x86_64-linux";
      };
    }
  );
}
```

### `flake/dev.nix` 调整（新增 formatter 和 treefmt）

```nix
{ ... }:
{
  perSystem = { pkgs, ... }: {
    devShells = {
      cuda = pkgs.mkShell {
        name = "cuda-dev";
        packages = with pkgs; [
          cudaPackages.cudatoolkit
          cudaPackages.cudnn
          linuxKernel.packages.linux_zen.nvidia_x11
        ];
        shellHook = ''
          export CUDA_PATH=${pkgs.cudaPackages.cudatoolkit}
        '';
      };
      default = pkgs.mkShell {
        name = "default-dev";
        packages = with pkgs; [
          git
          gnumake
          clang-tools
        ];
      };
    };

    treefmt = {
      projectRootFile = "flake.nix";
      programs = {
        nixfmt.enable = true;
        deadnix.enable = true;
        statix.enable = true;
      };
    };
  };
}
```

## 设计决策与取舍

### 为什么 `packages.nix` 单独一个文件而不归入 `base/`

`base/` 下的模块都是声明式属性设置（`home.username`、`home.stateVersion`、`sessionVariables`、`xdg` 等），这些属性的合并语义是"同名属性后者覆盖"，因此拆分或合并对最终结果影响不大。

`packages.nix` 则是一个列表（`home.packages`），列表的合并语义是"追加拼接"。如果把它塞进 `base/` 的某个文件里，未来想按主机/按用户差异化包清单时，就只能覆盖整个列表而不能追加。独立为单个文件后，多用户/多主机场景可以通过导入不同的 `packages.nix` 变体实现差异化，而不破坏 `base/` 的通用性。

### 为什么 `flakeModules/` 当前为空

`flakeModules/` 的定位是**对外 API**——类似库的公开接口。它存放的是被其他 flake `import` 消费的 flake-parts 模块。

当前配置是自用的单机 dotfiles，没有需要暴露给外部消费的模块。只有在出现以下场景时才会填充：
- 抽象出一套通用的 NixOS/HM 模块希望分享给其他人 `import`
- 将某个功能封装为可发布的 flake-parts 模块（如 `flakeModules/desktop-niri.nix`）
- 配置拆分为多个子 flake 形成依赖关系

在此之前保留空目录作占位，语义上比不创建这个目录更清晰——它明确告诉读者"对外 API 层存在，但你目前看到的都是内部模块"。

### 为什么 `lib/default.nix` 初始为空

`lib/` 的触发条件是：同一段 Nix 表达式在三处或以上出现，并且抽成函数后能显著降低认知负担。当前配置里还没有满足这个条件的情况。

典型触发场景：
- `mkUser "mayon" { extraGroups = [...]; }` 这样的用户工厂函数
- `mkHost { hostname = "..."; cpu = "intel"; gpu = "nvidia"; }` 这样的主机定义模板
- 多主机共享的 `mkNixpkgsConfig` 等通用配置片段

不提前预埋函数——在首次出现真实重复时创建，避免过早抽象。

### 为什么 `programs/desktop/` 子目录被取消

原设计将 `noctalia.nix`（桌面 shell 启动器）和 `thunar-terminal.nix`（文件管理器终端集成）归入 `programs/desktop/`，但"desktop"作为分类依据过于模糊——它既不是按功能类型（两者都是 GUI 应用），也不是按抽象层级，且只有两个文件就建子目录没有信息增益。

修正方案：两者都归入 `programs/apps/`——noctalia 是用户可启动的应用程序，thunar-terminal 是对 thunar 的行为配置，属于应用级配置。这样 `programs/` 的子分类全部按程序类型维度划分（apps/dev/terminal），标准统一。

## 与旧版结构的映射

| 旧路径 | 新路径 |
|---|---|
| `configuration.nix` | `hosts/nixos-btw/default.nix` |
| `hardware-configuration.nix` | `hosts/nixos-btw/hardware.nix` |
| `host/home.nix` | `flake/system.nix`（内联 HM 配置） |
| `host/packages.nix` | `modules/home/packages.nix` |
| `host/home/base.nix` | `modules/home/base/user.nix` |
| `host/home/*.nix` | `modules/home/base/*.nix` |
| `system/*.nix` | `modules/system/core/*.nix` 等 |
| `system/program/*.nix` | `modules/system/programs/*.nix` |
| `home/niri/*.nix` | `modules/home/wm/niri/*.nix` |
| `home/program/*.nix` | `modules/home/programs/*.nix` |
| `home/service/*.nix` | `modules/home/services/*.nix` |
| `home/shell/*.nix` | `modules/home/shell/*.nix` |
| `home/wallpaper/` | `modules/home/_assets/wallpaper/` |
| `dev/cuda/` | `flake/dev.nix`（perSystem.devShells） |
