# Neovim 重构设计与验收边界

本文件记录当前重构方案。用户要求整体推翻有问题的原生配置，以旧 Nixvim 的界面和操作效果作为参考；旧 Nixvim 的配色不作为目标，One Dark Darker（主背景 `#1f2329`）仍是明确约束。主代理保留 Den 功能入口、native Lua 配置、固定 Nix wrapper 和语言参数贡献；桌面视觉由 Astra 设计。当前实现和验证进度以[本轮执行记录](../neovim-rebuild-execution.md)及工作树为准。

## 当前结构

- [Neovim aspect](../../aspects/dev/neovim)通过 Den 接入真实主机。Home Manager 使用同一固定 Neovim 包；没有单独的 Home Manager switch。
- [Lua 配置](../../aspects/dev/neovim/config)负责界面和编辑行为；[package.nix](../../aspects/dev/neovim/package.nix)固定 wrapper、配置树和工具路径，[plugins.nix](../../aspects/dev/neovim/plugins.nix)固定插件闭包，[nix/neovim.nix](../../nix/outputs.nix)提供普通包、开发包和检查输出。
- 语言服务、formatter 与 linter 仍通过 Den 语言贡献生成配置，不在本次界面重构中改写其主机选择和参数。
- One Dark Darker 由固定的 `onedark.nvim` 提供完整语法和插件高亮，再由仓库配置叠加 palette 对齐与浮窗关系。主背景来自 palette 的 `#1f2329`。

## 本轮重做内容

本轮恢复完整界面插件组合：Snacks、Heirline、Navic、One Dark Darker、render-markdown 和 Trouble。Snacks 负责 picker、explorer、通知、输入/选择、buffer 操作、窗口工具和图片组件；Heirline 与 Navic 提供状态栏、标签栏及 LSP 符号路径；Trouble 提供诊断、符号、LSP 位置和 quickfix 面板；render-markdown 提供 Markdown 呈现。配置仍由 Nix 固定依赖、Lua 配置插件行为。

新增 `lazydev.nvim` 只管理 Lua 按需库和模块补全；不加载运行时插件管理器，不覆盖原生 LuaLS 根探测。项目及祖先目录已有 `.luarc.json` / `.luarc.jsonc` 时不注入库。

先前手写的 `ui.lua`、`editor.lua`、`files.lua`、`image.lua` 及对应旧 UI widget 检查已删除。小而明确的个人行为放在 feature 模块中：

- `features/scratch.lua` 使用 `stdpath("data")/mayon-scratch` 存新草稿；原 Snacks `scratch` 目录及旧草稿保持原样，不迁移、不覆盖、不清理。
- `features/math_preview.lua` 将数学预览触发、浮窗和 LaTeX 错误反馈接回 Snacks 图片和转换组件。保持一个渲染入口，避免自动图像布局与公式预览同时认领内容。
- `features/fileops.lua` 为 Snacks rename/trash 操作提供文件安全保护，涵盖目标冲突、已打开 buffer、未保存内容和缺少回收站命令等场景。隔离检查覆盖真实插件调用链；用户完整项目操作仍由最终验收确认。

Screenshots 曾显示长 Markdown 行被截断，并指出空 `[No Name]` 标签影响界面。本轮将围绕旧 Nixvim 的实际视觉与操作结果重新检查这些路径，不以“模块存在”或 headless 启动成功代替 GUI 验收。

## 被最新要求覆盖的历史选择

先前迁移计划曾决定完整移除 Snacks、用自写 Lua 替代 UI，并删除或不恢复 Heirline、Navic、render-markdown、Trouble、math preview 等行为；还曾暂用 `habamax`，以及把界面重构限制为仅替换状态栏和面包屑。用户最新明确要求整体推翻这些结果，并按旧 Nixvim 的效果重新配置。因此这些内容只说明决策历史，不再约束当前实现。当前主题仍固定为 One Dark Darker，截图参考仅用于判断布局、密度、信息层级和操作流。

历史迁移记录保存在[Den 执行记录](den-execution.md)；其中基于旧实现的结论不能当作当前实现或验收证据。

## 数据和验证边界

重构只调整配置与程序接线。不得删除或改写 undo、会话、草稿、插件历史、项目文件、模型、凭据或用户状态。尤其不要把旧 `scratch` 目录当作可清理的缓存。

`nix flake check --no-build` 是求值检查；构建普通包或 `checks.neovim` 只证明相应 derivation 成功。真实启动、快捷键/弹窗、字体和配色观感、终端图片、桌面菜单入口及当前会话中的用户操作需要分别验证。没有运行的项目须保持待验收，构建不能代替图形界面验收。

本轮相关输出：`nix build --no-link --no-write-lock-file .#checks.x86_64-linux.neovim`、普通/开发 Neovim 包和主机 toplevel；实际执行状态由主代理在[执行记录](../neovim-rebuild-execution.md)填写。系统应用沿用会话中既有自主 nr 授权，构建与应用分别记录，不强制重启已有编辑器。

## 入口

```sh
nix run .#neovim
NVIM_CONFIG_DIR="$PWD/aspects/editing/neovim/config" nix run .#neovim-dev
```

普通包固定使用 store 配置；开发包默认同一配置，并允许 `NVIM_CONFIG_DIR` 覆盖以检查工作树。两者使用相同的锁定插件和 parser 依赖。
