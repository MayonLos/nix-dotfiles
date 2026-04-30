# Nix Dotfiles Dendritic-Lite 重构设计

## 背景

当前配置有 14 个 `default.nix` 胶水文件，唯一职责是列举 import 列表。每增加一个模块需要同时修改胶水文件，维护成本高且容易遗漏。同时存在模块分类错位（openssh 在 security 而非 services）、文件粒度不一致（nix-ld.nix 3 行 vs obsidian.nix 395 行）、lib/ 空置等问题。

## 目标

- **消灭手写 import 列表**：用 `importDir` 递归自动导入替代全部 `default.nix` 胶水文件
- **修正分类错位**：openssh → services, polkit 独立, users 拆分
- **启用 lib/**：抽取 obsidian 和 keybinds 中的纯函数
- **保留 system/home 分离**：不引入 deferred module，保持现有架构认知模型
- **加新模块零摩擦**：`touch modules/<类别>/新功能.nix` 即生效

## 目录结构

```
modules/
├── system/                           # importDir 递归导入 → NixOS modules
│   ├── core/
│   │   ├── boot.nix
│   │   ├── network.nix
│   │   ├── nix.nix
│   │   └── locale.nix
│   ├── desktop/
│   │   ├── niri.nix
│   │   ├── gamemode.nix
│   │   └── xdg.nix
│   ├── hardware/
│   │   ├── nvidia.nix                # 合并 gpu.nix + cuda.nix
│   │   ├── bluetooth.nix
│   │   ├── pipewire.nix
│   │   └── firmware.nix
│   ├── programs/
│   │   ├── libreoffice.nix
│   │   ├── nix-ld.nix
│   │   ├── thunar.nix
│   │   ├── gamescope.nix
│   │   ├── zsh.nix
│   │   └── clash.nix
│   ├── security/
│   │   └── polkit.nix                # openssh 移出
│   ├── services/
│   │   ├── openssh.nix               # 从 security 移入
│   │   └── systemd.nix              # thermald + upower + power-profiles
│   └── user/
│       ├── mayon.nix
│       ├── fonts.nix
│       └── environment.nix
│
├── home/                             # importDir 递归导入 → HM modules
│   ├── base/
│   │   ├── user.nix
│   │   ├── session-vars.nix
│   │   ├── fcitx5.nix
│   │   ├── gtk.nix                   # 原 ui.nix
│   │   └── xdg.nix
│   ├── wm/niri/
│   │   ├── autostart.nix
│   │   ├── keybinds.nix
│   │   ├── rules.nix
│   │   └── settings.nix
│   ├── programs/
│   │   ├── firefox.nix
│   │   ├── mpv.nix
│   │   ├── obsidian.nix
│   │   ├── noctalia.nix
│   │   ├── yazi.nix
│   │   ├── zathura.nix
│   │   ├── thunar-terminal.nix
│   │   ├── vscode.nix
│   │   ├── git.nix
│   │   ├── latex.nix
│   │   ├── foot.nix
│   │   └── tmux.nix
│   ├── shell/
│   │   └── zsh.nix
│   ├── services/
│   │   ├── clipboard.nix
│   │   └── cliphist.nix
│   └── packages.nix
│
└── _assets/wallpaper/
```

## 关键机制

### importDir 函数

```nix
importDir = dir:
  builtins.concatLists (
    builtins.attrValues (
      builtins.mapAttrs (name: type:
        if type == "regular" && builtins.match ".*\\.nix" name != null then
          [ (dir + "/${name}") ]
        else if type == "directory" then
          importDir (dir + "/${name}")
        else [ ]
      ) (builtins.readDir dir)
    )
  );
```

- 递归扫描目录下所有 `.nix` 文件
- `_assets/` 下只有 `.jpg`/`.png`，自动被 `builtins.match` 过滤
- `builtins.readDir` 返回字母序，导入顺序确定

### hosts/nixos-btw/default.nix

```nix
{ inputs, ... }:
let
  importDir = /* 同上 */;
in {
  imports = [ ./hardware.nix ] ++ importDir ../../modules/system;
}
```

### flake/system.nix（HM 侧）

```nix
users.mayon = {
  imports = importDir ../modules/home;
  backupFileExtension = "backup";
};
```

## 变更清单

| 操作 | 文件 |
|------|------|
| 删除 (14) | 所有 `modules/**/default.nix` 胶水文件 |
| 删除 (1) | `modules/system/hardware/cuda.nix`（合并到 nvidia.nix） |
| 拆分 | `modules/system/users/default.nix` → `user/mayon.nix` + `user/fonts.nix` + `user/environment.nix` |
| 拆分 | `modules/system/security/default.nix` → `security/polkit.nix` + `services/openssh.nix` |
| 移动 | openssh 部分 → `modules/system/services/openssh.nix` |
| 重命名 | `modules/home/base/ui.nix` → `gtk.nix` |
| 新建 | `lib/default.nix`, `lib/obsidian-helpers.nix`, `lib/keybind-helpers.nix` |
| 修改 | `hosts/nixos-btw/default.nix`（使用 importDir） |
| 修改 | `flake/system.nix`（HM 侧使用 importDir） |
| 修改 | `modules/home/programs/apps/obsidian.nix`（引用 lib helpers） |
| 修改 | `modules/home/wm/niri/keybinds.nix`（引用 lib helpers） |

## 不变

- `flake.nix` 顶层结构不变
- `flake/dev.nix` 不变
- `flake/home.nix` 不变
- `hosts/nixos-btw/hardware.nix` 不变
- 所有非胶水模块的内容不变（除 obsidian/keybinds 抽取 helpers 外）
- `_assets/wallpaper/` 不变
