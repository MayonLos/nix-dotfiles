---
summary: 文档入口，按任务路由到文档、代码和检查
read_when: 每次开始任务时先看这里
code: [AGENTS.md, README.md]
checks: [docs]
---

# 文档索引

先按任务查下表，再读对应文档。**当前源码和 `flake.lock` 优先于任何文档**，发现矛盾时修正文档。

## 按任务查

| 要做什么 | 先读 | 代码入口 | 检查 |
|---|---|---|---|
| 新增、移动功能，跨功能传数据 | [architecture](architecture.md) | `aspects/default.nix`、`bundles/default.nix` | `architecture` |
| 验证、应用、回滚、清理 | [operations](operations.md) | `nix/checks.nix` | `treefmt` |
| 改生成文件，查谁写入、移除后留下什么 | [config-ownership](config-ownership.md) | 表内路径 | — |
| 新增或修改后台服务 | [service-policy](service-policy.md) | 各功能 `default.nix` | — |
| 查、改快捷键 | [keymap](keymap.md) | `aspects/desktop/mango-session/mango/keybinds.nix` | `keys-mayon-bindings` |
| 改自写工具（Clash、工具箱、Bilibili、语音） | [tools](tools.md) | `packages/mayon-tui`、`packages/bilitui`、`packages/mayon-voice` | `mayon-tui`、`bilitui`、`mayon-voice` |
| 改颜色、字体、尺寸、透明度 | [visual](visual.md) | `aspects/appearance/appearance/onedark.nix` | `palette-contrast` |
| 改顶栏、Dock、面板、通知、窗口规则 | [desktop](desktop.md) | `aspects/desktop/mango-session` | `desktop-composition` |
| 改 Xorg / dwm 会话 | [xorg](xorg.md)、[xorg-visual](xorg-visual.md) | `aspects/desktop/xorg-session` | `xorg-session-runtime` |
| 改 Neovim | [neovim](neovim.md)、[keymap](keymap.md) | `aspects/dev/neovim` | `neovim` |
| 增删软件 | [apps](apps.md) | `aspects/apps` | — |
| Obsidian 主题与笔记库 | [obsidian](obsidian.md) | `aspects/apps/documents` | `documents-visual-config` |
| 用 dsh、Grok Bot | [dsh](dsh.md)、[grok-bot](grok-bot.md) | `aspects/dev/ai-agents` | — |
| 委托外部代理、交接进行中的轮次 | [agent-workflow](agent-workflow.md) | `.work/HANDOFF.md`（本地） | — |
| 规划服务器 | [server-plan](server-plan.md) | `tests/composition/remote.nix` | `remote-workspace-composition` |
| 查某次改动的经过 | [history](history/README.md) | `git log` | — |

## 关键事实

- 单主机 `nixos-btw`，用户 `mayon`，Intel + NVIDIA 笔记本，Mango + Noctalia。Home Manager 随系统重建。
- 仓库总规则在 [AGENTS.md](../AGENTS.md)。功能细节在各功能目录的 `README.md`。
- 秘密只经 sops 运行时文件传递，不进 Nix 字符串、日志或 store。
- 回复用户用中文；技术标签保持英文。

## 写文档的规则

`checks.docs` 会强制前三条：

1. 顶层文档开头都有 front matter：`summary`（一句话）、`read_when`（何时该读）、`code`（真实存在的路径）、`checks`（相关检查）。
2. 每篇顶层文档都登记在上面的路由表。
3. 本地链接必须有效（`docs/history/` 除外）。
4. 只写现行事实，不写“本轮”“尚未应用”这类随时间失效的状态；过程和结论写进 `docs/history/`，那里只追加。
5. 能从源码查到的数值，写明源码位置，并以源码为准。
6. 一个事实只写一处，其他地方放链接。
