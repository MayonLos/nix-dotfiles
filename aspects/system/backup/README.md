# 本地 Restic 备份

用锁定 nixpkgs 的 `restic` 对用户文档、图片和 dotfiles 工作树做每日版本化备份。它补充
Git/Nix 世代回滚：这两者都不包含 `~/Documents`、`~/Pictures` 里的用户数据。

## 输入

- 主机侧 sops 秘密 `restic-password`，默认 owner/mode 为 root/0400，运行时路径为
  `/run/secrets/restic-password`。
- 由 `inventory/hosts/nixos-btw/default.nix` 选择；没有用户级配置或可选参数。

## 输出

`services.restic.backups.home` 生成 `restic-backups-home.service` 和同名 timer：

- 仓库：`/home/mayon/Backups/restic`（本机 ext4 根盘）
- 路径：`~/Documents`、`~/Pictures`、`~/nix-dotfiles`
- 排除：`Documents/embedded`、`Documents/gtnh*`、`.cache`、`node_modules`、`.venv`、`target`
- 每日 `OnCalendar=daily`，带 15 分钟随机延迟；保留 7 日、4 周、6 月
- 首次运行 `--initialize` 创建仓库；密码只从运行时 sops 文件读取

## 边界

**这是同盘备份**：能防误删和错误修改，不能防磁盘损坏、文件系统损坏、整机丢失或勒索软件同时
加密备份。要覆盖这些场景，需要另一个物理磁盘或远端仓库；当前没有可用外接盘/远端凭据，所以
没有自动选择。仓库路径、密码文件和保留策略都可以在 `default.nix` 中改。

没有配置 `restic check` 的独立 timer；备份成功后可手动运行检查。没有把 restic 纳入应用数据
一致性快照（数据库/浏览器配置不在备份路径内），需要时按应用单独处理。

## 恢复演练

```sh
sudo restic -r /home/mayon/Backups/restic \
  --password-file /run/secrets/restic-password snapshots
sudo restic -r /home/mayon/Backups/restic \
  --password-file /run/secrets/restic-password \
  restore latest --target /tmp/restic-restore --include /home/mayon/Documents/notes
```

## 拥有文件与状态

本 feature 拥有 `default.nix`、本 README 和 systemd/tmpfiles 声明。备份仓库、restic cache 和
`~/Backups` 属于运行态数据，不由 activation 清理或迁移。

## 移除后状态

从 host 绑定和 `aspects/default.nix` 移除后，下一次激活删除 timer/service 和 tmpfiles 规则；
已存在的 `/home/mayon/Backups/restic`、快照和 sops 秘密不会被自动删除，需要用户自行决定是否
保留或清理。
