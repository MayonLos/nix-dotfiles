# Grok Bot

本仓库通过锁定的 `llm-agents` 输入安装官方 Linux 桌面客户端；当前包为 0.66.0，
来源是官方 Cursor CDN 的 `.deb`，由 Nix 处理运行库，不安装 Flatpak 或 AppImage。
`modules/home/programs/dev/grok-bot.nix` 管理包和 `grokbot://`、旧版 `sand://` 登录回跳。

```sh
grok-bot
```

桌面菜单入口为 **Grok Bot**。常规部署随 `nr` 应用；不要用 `--version` 探测这个 GUI 程序，
该参数也会启动应用。CLI `grok` 是另一款 Grok Build 编码工具。

## 首次使用

1. 按应用界面用 Cursor 账号登录；SuperGrok 用户按官方流程关联已有套餐。
2. 创建一个 Bot，写清职责、预期产物和它需要访问的资料。
3. 先交一个具体任务，读结果并修正它的工作方式。
4. 将稳定的做法存成 skill；需要定时或事件触发时再创建 routine。

Grok Bot 需要符合条件的 Cursor / SuperGrok 套餐，并有用量限制；不是本地模型的免费运行器。
各 Bot 使用账号的云端电脑，电脑中的文件和登录态可共享。访问本机文件需要另外启用相应功能。
本地仓库编码可继续使用 Codex、Pi、Grok Build；跨应用、浏览器和持续后台任务适合 Grok Bot。

## 模板与样板文本

| 形式 | 用途 | 使用方式 |
|---|---|---|
| `x.ai/bot/...` 分享链接 | 安装别人设计的 Bot 副本 | 预览配置 → Add to Grok Bot → 连接自己的插件/账号 |
| 社区 `PROFILE.md` | 定义 Bot 的职责、工作方法和产物 | 创建 Bot → Edit Profile → 粘贴文本并按自己需求修改 |
| Skill | 复用已经验证的工作方法 | 让 Bot 保存具体步骤，后续任务调用 |
| Routine | 定时或事件触发同一流程 | 单次任务验证后配置触发条件 |

模板可以包含说明、相关技能、部分记忆、定时流程和插件配置；它不带原作者的登录态、
完整电脑、对话历史或自定义 MCP/脚本。导入后的集成可能仍需要安装或授权。

对本仓库可先试两类职责：

- **PR 审查**：“审查这个 nixvim diff，检查懒加载、键位和工具依赖，列出有证据的问题及验证缺口；只给报告。”
- **资料调研**：“核查 llama.cpp 的当前官方部署文档和社区反馈，区分已验证事实、体验反馈和未确认结论，给原始链接。”

“幕僚长”适合负责总览：收集进展、整理待办、提醒卡点，再把明确任务交给专门的 Bot。
刚开始只给它一个范围小、产物明确的任务，例如：

> 查看 MayonLos/nix-dotfiles 最近一周的提交和未关闭 Issue，给我中文报告：
> 改了什么、有哪些遗留问题、建议先处理哪三件事。只生成报告。

这需要先完成 GitHub 账号连接。界面中“插件已安装”不等于已经取得仓库访问权限。
单次报告满意后，再将它设成每天或每周运行的 routine。

社区目录：[可安装分享模板](https://github.com/divo12/awesome-grok-bot-templates)、
[PROFILE 文本与团队工作规范](https://github.com/cobusgreyling/grok-bot-templates)。
后者的 CLI 用于打印或生成模板文本；其评分是项目自身规则，不代表实际任务效果。

## 当前验证范围

已验证包安装、桌面文件和进程启动；账号登录、云端电脑和插件连接需在自己的账号内完成。
当前 Nix 打包器为规避上游 Electron webview 崩溃强制 `--no-sandbox`，
这是锁定包的兼容处理。应用内自动更新对只读 Nix store 的行为尚未验证；包版本由 Nix 管理。

资料核查日期：2026-10-08。
官方资料：[安装与登录](https://docs.x.ai/grok-bot/get-started)、
[FAQ 与套餐用量](https://docs.x.ai/grok-bot/faq)、
[模板指南](https://x.ai/bot/guides/templates-for-grok-bot)、
[Skills 与 routines](https://docs.x.ai/grok-bot/skills-routines-and-automations)、
[锁定包定义](https://github.com/numtide/llm-agents.nix/tree/83984ebbbe5322b261d9fdc24eb15cf44f23abec/packages/grok-bot)。
