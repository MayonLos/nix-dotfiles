---
summary: 自写工具清单、入口、数据位置、统一交互约定和资源测量
read_when: 修改或新增自写 TUI、查工具的快捷键和数据目录、判断某个工具是否还存在
code: [packages/mayon-tui, packages/bilitui, packages/mayon-voice, packages/noctalia-clash-status, aspects/cli/mayon-tools, aspects/cli/keys-mayon]
checks: [mayon-tui, bilitui, serial-mayon, keys-mayon, keys-mayon-bindings, mayon-voice, mayon-voice-fcitx]
---

# 自写工具

源码只放在 `packages/`；功能目录负责安装、快捷键和配置。Mango 绑定在
`aspects/desktop/mango-session/mango/keybinds.nix`。

## 清单

| 工具 | 入口 | 按键 | 包输出 | 用户数据 |
|---|---|---|---|---|
| Clash | `clashtui-mayon` | `Super+Shift+C` | `pkgs.mayonTui.clash` | `~/.local/share/mayon-clash/` |
| 工具箱 | `mayon-tools [docker\|ports\|serial\|keys\|voice]` | `Super+Shift+D` | `pkgs.mayonTui.tools` | 见下 |
| Bilibili | `bilitui-mayon` | `Super+Shift+B` | `pkgs.bilitui` | `~/.local/share/bilitui/`、`~/.config/bilitui/`、`~/Videos/Bilibili/` |
| 语音输入 | `mayon-voice {toggle,start,stop,status,models fetch}` | 专用键，松开触发 | `pkgs.mayonVoice` | `~/.local/share/mayon-voice/models/` |

工具箱页签：

| 页 | 内容 | 状态 |
|---|---|---|
| docker | 容器、镜像、卷、概览、空间 | 不写持久配置；切到此页才连接，不会因打开工具箱唤醒 daemon |
| ports | 监听端口与进程 | 无持久状态 |
| serial | 串口监视、参数、命令、烧录 | `~/.config/serial-mayon/`、`~/.local/share/serial-mayon/` |
| keys | Mango 快捷键速查，只读 | 读 `~/.config/keys-mayon/bindings.json`（生成） |
| voice | 语音状态页，经 socket 访问 daemon | 无 |

非交互子命令挂在对应页下，如 `mayon-tools keys list --json`、`mayon-tools serial list`。
详情见 [packages/mayon-tui/README.md](../packages/mayon-tui/README.md) 与各 crate README。

## 已移除（不要找也不要恢复接线）

`seek`、`power-mayon`、`mcsrv-mayon`、`study-mayon`、`shots-mayon` 于 2026-10-31 删除，
相关数据目录已由用户清理。截图功能不受影响，仍由 mark-shot、wayscrollshot 提供。
`musicfox` 决定继续使用上游，不自写。代码可从 Git 历史 `47fcebe` 找回。

## 统一约定（新增工具必须遵守）

共享实现在 `packages/mayon-tui/crates/ui`（包名 `mayon-ui`）：

| 模块 | 职责 |
|---|---|
| `search` | `Matcher`：多词 AND、大小写不敏感、中文、全拼、首字母；短文本才启用子序列；返回分数与命中范围 |
| `input` | `TextInput`：CJK 宽度、光标移动、Ctrl+A/E/U/K/W、安全粘贴、真实光标位置 |
| `style` | `Tone`、`Notice`、`modal`、`list_state`、数值右对齐、按键提示 |
| `lib` | `chrome`、`table`、终端生命周期（bracketed paste、焦点事件） |

交互：

- 本地过滤用 `/`，边打边滤；上下键直接移动选中项；Enter 保留结果；输入中 Esc 恢复打开前的过滤；列表态 Esc 清除过滤。远程搜索（如 bilitui 的 `s`）才用 Enter 提交。
- 显示 `匹配数/总数` 和命中高亮；无匹配时提示 Esc 清除。
- 刷新和过滤按稳定 ID 保持选中项，任何情况都不越界。
- 文本量大的搜索（如 keys）优先显示真实命中，子序列只作无命中时的回退。

外观：One Dark，不引入新色；绿成功、黄警告、红错误、蓝可操作，并配文字或符号；标题、正文、次要信息三级文字色。

资源（硬性要求，见下方测量）：

- 事件驱动，只在有变化时重绘，不用固定帧率循环。
- 失焦（FocusLost）暂停刷新与流；工具箱只刷新当前页，页签首次打开才初始化。
- 日志、串口、搜索缓存都有容量上限。
- 宁可多占磁盘，不多占 CPU、内存和显存。

布局规定了鼠标命中的行号（如 tabs 在第 1 行），改 `chrome` 行数时要同步 clash、docker、serial 的鼠标计算。

## 资源测量

2026-10-31，部署版本，15 秒采样，clash 和 docker 未连接真实服务，采样时机器有其他构建负载。显存未测，这些工具不使用 GPU。

| 工具 | CPU 聚焦 旧→新 | CPU 失焦 旧→新 | 唤醒/秒（聚焦）旧→新 | 内存 旧→新 |
|---|---|---|---|---|
| ports | 1.60% → 0.53% | 1.53% → 0% | 16.2 → 2.1 | 5 → 6 MB |
| keys | 0.33% → 0% | 0.33% → 0% | 4.0 → 0 | 3 → 6 MB |
| clash | 0.20% → 0% | 0.13% → 0% | 22.5 → 3.7 | 7 → 8 MB |
| docker | 0.67% → 0.13% | 0.67% → 0% | 15.1 → 1.2 | 7 → 8 MB |

一个 Kitty 窗口约 150 MB，这才是开销大头；工具箱让这几个工具共用一个窗口。

## 验证

```sh
cd packages/mayon-tui && cargo test --workspace --locked
nix build --no-link --no-write-lock-file .#checks.x86_64-linux.mayon-tui
```

终端界面要用真实 Kitty 截图验证，方法见 [agent-workflow.md](agent-workflow.md) 第 8 节。
