---
name: nix-modules
description: 修改此仓库的 Nix 模块组织、flake 输入与接线、通道选择或开发 shell；排查模块未加载和求值错误。
---

# Nix 模块与 flake

路径相对仓库根目录。先读实际模块与 `flake.lock`，再判断结构或版本问题。

## 接线

- `flake.nix` 用 flake-parts；`flake/system.nix` 创建 `nixosConfigurations.nixos-btw`。
- `hosts/nixos-btw/default.nix` 导入 `modules/system/`；Home Manager 导入 `modules/home/`。
- `lib/import-dir.nix` 递归加载所有 `.nix`，包含 `.nix` 软链，无排除机制。
  `_assets` 只是没有 `.nix`，不是特殊目录。包表达式放 `pkgs/`，helper 放 `lib/`。
- 模块写成 `_: { ... }` 或 `{ pkgs, lib, ... }: { ... }`。
  NixOS 的 `specialArgs` 与 HM 的 `extraSpecialArgs` 都提供 `inputs`、`pkgs-unstable`。
- `nixvim/` 使用自己的显式 imports，不归 `importDir` 管；由 `dev/nvim.nix` 桥接。

## 包集合与输入

默认 `pkgs` 是 `nixos-26.05`，HM `useGlobalPkgs = true` 与系统共享它。
`pkgs-unstable` 单独 import；两者启用 `allowUnfree`。
不要因一个包改整个通道；先确认 stable 是否满足要求，再取单一属性并说明原因。

修改通道、overlay、输入或 `follows` 前读 [输入与包来源](references/inputs.md)。
已有特例包括 Copilot CLI、Java 26、IM、portal-wlr 与 NVIDIA recipe；
其中 recipe 的导入不同于直接取 unstable 的预编译驱动包。

## 修改方式

新增系统 / HM 模块只需放入对应目录；移除模块会同时移除其配置，先找调用与依赖。
不要把完整目录迁到 `modules/` 而不检查其中所有 `.nix` 的类型。
共享 helper 放在 `lib/` 并通过相对路径导入（版本集合、桌面常量、通用小工具）；
`lib/default.nix` 仍只导出 `importDir`，模块按相对路径取用具体文件。
抽象接口与关键配置的改动索引见 [共享接口与关键配置](references/shared-helpers.md)。

`flake/dev.nix` 管理两个 dev shell 和 treefmt：
默认 shell 提供基础编译与 sops 工具，CUDA shell 单独提供 CUDA 依赖。
项目专属工具链放该项目自己的 flake / `.envrc`；用户编辑工具看 `dev-toolchain`。

HM 随 NixOS switch 应用。`backupFileExtension = "backup"` 不会解决所有文件冲突；
应用会改写的文件应检查 ownership，参考 `desktop-apps`，不要盲目加 `force`。

## 验证

- 结构与 option 改动：按 AGENTS.md 的命令求值；`--no-build` 仅验证求值。
- 包、内核、overlay 改动：构建相关 derivation；系统级影响再构建 toplevel。
- 新文件必须进入 Git flake 的源集合；如用 `path:.` 验证未跟踪文件，先检查源范围。
- `nix fmt` 会改文件；审核使用 treefmt check 输出，避免把自动修复混进只读任务。
- 输入更新后查看 warnings，但没有 warnings 不等于构建或运行时成功。
