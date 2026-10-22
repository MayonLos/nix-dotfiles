# 仓库整理

2026-10-23。用户授权自主整理仓库并删除无用文件。锁定输入、包选择和运行系统均不变。

## 已应用改动入库

开始时工作树有 42 个未提交文件（Neovim Astra 重构、Noctalia 拆分、项目 tmuxp 工作台、
Docker 构建缓存清理、Claude Code/dsh 接入与 OpenCode 移除、对应文档）。`nix flake check --no-build`
通过，且该工作树求值出的 toplevel 与 `/run/current-system` 同为
`dp8v8fdxa3hsjzl733442dpgmrdpagsy-nixos-system-nixos-btw-26.05.20261012.7993f34`，
即这些改动已经应用。按主题分为四个提交，未改内容。

## 分支

- `codex/xorg-baseline-20261019` 已完全并入 `main`，删除。
- `feat/matlab`、`mango`、`nvim-markdown-math`、`repo-audit-emacs-refactor` 落后 `main` 194 个提交，
  属于 Den 迁移前的结构。删除分支前分别打为 `archive/feat-matlab`、`archive/mango`、
  `archive/nvim-markdown-math`、`archive/repo-audit-emacs-refactor` 标签，提交仍可检出。

## 文件

- 各轮实施、应用和审核记录移入 `docs/history/`；顶层 `docs/` 只留当前设计与用法，
  新增 [文档索引](../README.md)。全部相对链接已按新位置改写并逐一校验可解析。
- 删除 `docs/repository-audit-2026-10-14.md`：无任何引用，内容已被 2026-10-20 审核取代。
- 删除忽略目录中的 Python 字节码缓存与空的 `.worktrees/`、`.agents/`。
- 源码中未发现无引用的模块、脚本或资源；壁纸目录整体是 Noctalia 随机轮换来源，全部保留。

`.team/briefs/` 为 2026-10-03/17 的 Codex 任务简报，均标记完成并指向已不存在的旧路径。
它被 Git 忽略且没有其他副本，删除不可恢复，因此留给用户决定。
