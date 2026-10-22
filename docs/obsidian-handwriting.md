# Obsidian 手写与插件管理

2026-10-22 按本机 Vaults 的实际插件与运行状态整理。当前 Obsidian 应用为 1.14.4，
安装器为 Nix 提供的 1.13.7；应用后台更新不等于重建或改变 Nix 包声明。
Obsidian 由 `aspects/documents/default.nix` 安装；Vault 内插件和设置由应用管理，
不把笔记、插件状态或账户数据放进 Nix store。

## 保留的插件

| 插件 | 用途 |
|---|---|
| Excalidraw 2.29.0 | 手写笔记、公式、图示和笔记内嵌画布 |
| Git | 现有 Vault 版本管理；本次不改变备份或远程设置 |
| Outliner | 列表缩进和结构编辑 |
| Vimrc Support | 加载已有 `.obsidian.vimrc`；保留 Vim 模式 |
| Better Word Count | 编辑与选区计数 |
| File Explorer Note Count | 文件夹笔记数 |
| Recent Files | 最近笔记列表 |
| Claudian | 在 Vault 内使用现有 CLI agent |
| Omnisearch 1.31.0 | 文字笔记的全文搜索、结果排序和页内搜索 |
| Simplified Chinese Word Splitting 1.14.0 | 结巴中文分词与编辑器/Vim 中文词边界 |
| PDF++ 0.40.31 | PDF 摘录、来源位置链接和阅读操作 |

当前共保留 11 个插件。先前移出的完整插件为 Smart Chat、Smart Templates 和
Smart Lookup，分别放弃浏览器会话嵌入、提示词模板拼装和独立语义查询界面。
随后按用户要求移出 Smart Connections 和 Smart Context，不再保留 Smart 系列插件。
没有查到笔记中的 Smart Chat 专用代码块或对 Smart Templates、Smart Lookup 的引用。
Omnisearch 使用文本关键词检索，不提供 Smart Connections 的语义关联，也不是 OCR。

Calendar、Commander、Copilot、Easy Typing 的旧目录缺少 `manifest.json` 和
`main.js`，仅余配置或规则文件，也已移出插件目录。

## 手写入口

- `Ctrl+Alt+D`：新建 Excalidraw 画布并在新标签页打开。
- `Ctrl+Alt+E`：在当前 Markdown 笔记内创建并嵌入画布，在旁边打开。
- 默认开启笔模式，显示黑笔、红笔、荧光笔三个预设；桌面自动保存间隔为 15 秒。
- 新建的 `Excalidraw/手写试写.excalidraw.md` 用作空白试写页。

快捷键绑定的是插件的 `excalidraw-autocreate-newtab` 与
`excalidraw-autocreate-and-embed` 命令。设置通过本机 Obsidian CLI 写入运行中的应用，
不通过覆盖整个设置目录应用。

## 搜索与 PDF 阅读

| 快捷键 | 功能 |
|---|---|
| `Ctrl+Shift+O` | Omnisearch 全库搜索 |
| `Ctrl+Alt+F` | Omnisearch 当前文件内搜索 |
| `Ctrl+Shift+C` | PDF 中复制选区/批注的摘录及来源链接 |
| `Ctrl+Alt+W` | PDF 适应宽度 |

上述快捷键已检查与当前命令表无冲突。Omnisearch 保留原生 `Ctrl+O` 快速切换入口，
遵守已排除文件，启用驼峰词拆分；没有安装 Text Extractor，PDF/图片/Office 文件内容
索引保持关闭，当前主要检索 Markdown 笔记。

中文插件 1.14.0 要求 Obsidian 1.14.4；安装时已核实实际应用满足要求。配套
`jieba-wasm@2.4.0` 使用插件自身下载地址及内置 SHA-256 校验，通过插件
`installJieba` 立即初始化并持久化到 IndexedDB，设置 `useJieba=true`。它是本地分词
组件，不是付费模型。启用后重载 Omnisearch，重新生成索引。

PDF++ 的默认复制格式为 Markdown 引用加中文“来源”链接，显示文档标题与页码。
保留手动选择和复制的操作方式，原件编辑选项 `enablePDFEdit` 保持关闭。
本轮没有引入付费 API 或配置云端 AI 服务。

本轮没有安装其他手写插件，没有改变系统输入驱动或数位板全局映射。笔按钮目前产生的
`B`、`E` 与部分侧键是固件键盘输出；普通 Markdown 编辑区仍启用 Vim，不能把这些键
一概当成画笔命令。数位板实测记录如下，编号仅代表测试时的按下顺序，不代表物理位置：

| 测试顺序 | 当前键盘输出 |
|---|---|
| 1、2 | `A`、`C` |
| 3、4 | `Ctrl+KP+`、`Ctrl+KP-` |
| 5、6 | `[`、`]` |
| 7、8 | 空格、Tab |
| 9、10 | `Ctrl+S`、`Ctrl+E` |
| 11、12 | `I`、`Ctrl+Alt+Z` |

笔按钮测试期间还出现了 `BTN_STYLUS` 和接触事件；没有独立证据把所有接触事件都归于
笔身按钮。上方软键区本次只读到笔接触，没有独立快捷键。以上不证明所有键位已完成
重映射，也不证明实际手写压感已经验证。

## 备份与恢复

私有备份目录权限为 `0700`：

- `~/.local/state/obsidian-maintenance/20261022-220319/`：首次整理前完整
  `.obsidian` 归档，以及最先移出的七个插件目录。
- `~/.local/state/obsidian-maintenance/20261022-221553/`：替换 Smart 插件前完整
  `.obsidian` 归档，以及移出的 Smart Connections、Smart Context 目录。

每个备份中的完整归档名为 `obsidian-config.tar.gz`，移出目录位于
`removed-plugins/`；代码、配置与规则文件均保留。

恢复单个插件时，从 `removed-plugins/` 取回对应目录到 Vault 的 `.obsidian/plugins/`，
再在 Obsidian 内启用。四个不完整目录仅含旧配置，恢复文件本身不会补齐缺失的插件程序。
没有删除笔记、附件、AI 会话、模型、索引、浏览器登录状态或 `.smart-env` 数据。

## 验证范围

已检查实际加载清单、插件入口文件、设置落盘、命令注册及移出插件不再加载。
Excalidraw 画布的笔模式和工具状态通过运行时 API 核对，最终截图已看到手写笔迹及
三支笔的入口。中文分词实测“现代控制理论与传递函数”得到“现代”“控制”“理论”
“与”“传递”“函数”“传递函数”；Omnisearch 搜索“传递函数”“传递”和“Laplace”
均返回结果，并包含对应标题。本机当时没有 Vault 内 PDF，因此没有宣称实际 PDF
摘录操作已通过。没有进行系统重建或配置激活；没有测量压感曲线，也没有核验全部侧键。

参考：[Obsidian CLI](https://help.obsidian.md/cli)、
[Excalidraw 插件](https://github.com/zsviczian/obsidian-excalidraw-plugin)、
[Omnisearch](https://github.com/scambier/obsidian-omnisearch)、
[中文分词](https://github.com/aidenlx/cm-chs-patch)、
[PDF++](https://github.com/RyotaUshio/obsidian-pdf-plus)。
