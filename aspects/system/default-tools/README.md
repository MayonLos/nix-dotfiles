# 默认工具接口

在 Den user 或 host-account binding 的 `defaultTools` 字段中填写角色，再显式选择
`den.aspects.default-tools`。

| 字段 | 含义 |
|---|---|
| `terminal.argv` | 默认终端命令 |
| `editor.argv` | CLI 编辑器命令，供 `EDITOR`/`VISUAL` 使用 |
| `browser.argv`、`browser.desktopId` | 浏览器命令与可选的 HTTP(S)/HTML 默认桌面入口 |
| `fileManager.argv`、`fileManager.desktopId` | 文件管理器命令与可选的目录默认桌面入口 |
| `guiTextEditor` | 文本/Markdown/shellscript 的 GUI 默认桌面 ID，可与 CLI 编辑器不同 |

角色默认 `null`。`argv` 是有序的完整命令值，首项非空；相同值可重复，不同值报冲突，不会
按列表拼接。Desktop ID 包含 `.desktop` 后缀，不按 shell 命令或 Desktop Entry `Exec` 解释。

选择 aspect 后，非空命令会生成 `workspace-terminal`、`workspace-editor`、
`workspace-browser`、`workspace-files` wrapper，并设置本功能拥有的会话变量和 MIME 默认项。
wrapper 对固定参数做 shell escaping，再以 `"$@"` 原样传入调用参数。其他模块的环境变量不会
被转发。

安装软件和设默认是分开的：该功能只安装 wrapper，不按命令名或 Desktop ID 推断安装 Kitty、
Neovim、Firefox 等。绑定显式提供当前默认项；CLI Neovim 与 GUI VS Code 分别承担 CLI 和 GUI
编辑角色。Mango 桌面快捷键、Thunar 动作复用 wrapper，项目 PATH 仍可解析相对命令名。

生产检查 `checks.workspace-composition` 与 `checks.command-line-runtime` 覆盖绑定隔离、argv
边界、工作目录、MIME 和实际 desktop entry。它们不启动 GUI，也不证明配置已应用。每批记录见
[执行记录](../../../docs/history/den-execution.md)。

`contract.nix` 是公开的 user schema；`default.nix` 是唯一功能入口，`consumer.nix` 私有。
本功能拥有上述 wrapper、会话变量和 MIME 声明。移除选择后，下次激活撤销这些声明；它不删除
绑定的应用、桌面文件、用户配置或工作目录。命令行与桌面消费者是否存在由各自功能选择决定。
