# 默认工具接口

在 Den 的用户或主机账号绑定上填写 `defaultTools`，再显式选择 `den.aspects.default-tools`。

| 字段 | 含义 |
|---|---|
| `terminal.argv` | 默认终端命令 |
| `editor.argv` | CLI 编辑器命令，供 EDITOR/VISUAL 使用 |
| `browser.argv`、`browser.desktopId` | 浏览器命令与可选的 HTTP(S)/HTML 默认桌面入口 |
| `fileManager.argv`、`fileManager.desktopId` | 文件管理命令与可选的目录默认桌面入口 |
| `guiTextEditor` | 文本/Markdown/shellscript 的 GUI 默认桌面 ID，可与 CLI 编辑器不同 |

所有角色默认 `null`。`argv` 是有序的完整命令值，首项非空；相同定义可重复，不同定义报冲突，不按列表拼接。Desktop ID 包括 `.desktop` 后缀，不被当作 shell 命令或 Desktop Entry 的 `Exec` 字段解释。

数据本身不产生配置。选择 aspect 后，仅为非空命令生成 `workspace-terminal`、`workspace-editor`、`workspace-browser`、`workspace-files` 脚本，并设置对应的会话变量和明确选择的 MIME。脚本用 `escapeShellArgs` 固定配置参数，再以 `"$@"` 原样传递调用参数；不会重新解析用户参数。home 和 systemd 只接收本功能拥有的变量，不把其他模块的变量顺带转发。

安装软件和设默认分开：本功能只安装这些小脚本，不根据命令名或 Desktop ID 自动安装 Kitty、Neovim、Firefox 等。调用方须显式选择应用，或提供可用的外部命令。相对命令名按调用时 PATH 解析，允许项目环境覆盖；固定 store 可执行路径则按该路径执行。组合样本明确选择 GUI 应用，并检查所用的 Desktop ID 确实存在。

当前真实配置的 `EDITOR/VISUAL = nvim` 和 MIME 默认项尚未迁移；接入时需转移这些声明及 Mango 快捷键的消费者，不能把两套默认项同时叠上去。样本保留 CLI Neovim 与 GUI VS Code 的区别。

`checks.nix` 用隔离的记录程序执行真实脚本，检查空格、引号、`$`、命令替换文本和空参数，再检查生成的 mimeapps.list 和实际桌面入口文件。不启动 GUI，不应用到当前会话。
