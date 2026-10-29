# Obsidian：One Dark、学习首页与手写

2026-10-29 的重构方案在 `vault-stage` 实现，并在独立 HOME、D-Bus 和无头 sway
中的 `vault-shot` 验证。它是待主代理同步的配置，不代表真实笔记库已经迁移。
Obsidian 安装器仍由 Nix 提供（1.13.7）；隔离应用会使用官方应用更新包，
最终实际应用版本及截图、控制台记录以本轮交接报告为准，不能由安装器版本推断。
Home Manager 不部署笔记、插件、主题目录或账户数据。

## 主题与插件

主题为 Minimal，Minimal Theme Settings 使用 Atom / One Dark scheme。
Noctalia 的 `noctalia.css` **只声明调色板变量**；笔记库 Git 管理的
`.obsidian/snippets/vaults-ui.css` 负责组件和布局，两者均启用。
读宽约 680px；首页更宽；蓝色用于短竖条、标签页下划线和选中边线。
callout、代码块、菜单和设置窗口使用低饱和色与实色背景。
配色变量由 appearance 数据提供，组件 snippet 不嵌入固定色值。

新增下载来自 [官方登记清单](https://github.com/obsidianmd/obsidian-releases)
所指仓库的正式 release。八个保留插件的 main.js 按审核意见恢复并保留
笔记库提交 31a366c 的原装字节；可能与同版本公开 release 不同，不再替换。
`_system/plugin-sources.json` 区分下载资产摘要与当前安装文件摘要；
下表保留插件的 release 链接用于版本参考，不能当作原装程序的字节来源证明。

| 名称 / ID | 版本 | 用途 / 来源 |
|---|---|---|
| obsidian-minimal-settings | 9.0.0 | [Atom scheme、字体、读宽和密度。](https://github.com/kepano/obsidian-minimal-settings/releases/tag/9.0.0) |
| dataview | 0.5.68 | [首页实时学科计数、更新时间和继续阅读卡片。](https://github.com/blacksmithgu/obsidian-dataview/releases/tag/0.5.70) |
| obsidian-style-settings | 1.0.9 | [可调读宽、首页宽度与界面字号。](https://github.com/community-archive/obsidian-style-settings/releases/tag/1.0.9) |
| homepage | 4.6.0 | [启动打开 Home，固定 Reading view。](https://github.com/mirnovov/obsidian-homepage/releases/tag/4.6.0) |
| obsidian-quiet-outline | 0.5.21 | [标题导航、当前章节定位，叠加 CSS 阅读进度条。](https://github.com/guopenghui/obsidian-quiet-outline/releases/tag/0.5.21) |
| obsidian-latex-suite | 1.14.1 | [默认公式 snippets，开启其 Vim 集成。](https://github.com/artisticat1/obsidian-latex-suite/releases/tag/1.14.1) |
| notebook-navigator | 3.5.0 | [左侧双栏导航、摘要、日期分组、学科图标。](https://github.com/johansan/notebook-navigator/releases/tag/3.5.0) |
| Minimal | 9.1.4 | [轻量主题基础，使用 Atom / One Dark scheme。](https://github.com/kepano/obsidian-minimal/releases/tag/9.1.4) |
| obsidian-excalidraw-plugin | 2.29.0 | [手写、图示与嵌入画布。](https://github.com/zsviczian/obsidian-excalidraw-plugin/releases/tag/2.29.0) |
| obsidian-git | 2.38.0 | [保留既有备份与远程设置。](https://github.com/vinzent03/obsidian-git/releases/tag/2.38.0) |
| obsidian-outliner | 4.10.0 | [列表结构编辑。](https://github.com/vslinko/obsidian-outliner/releases/tag/4.10.0) |
| obsidian-vimrc-support | 0.10.2 | [保留 .obsidian.vimrc 和 Vim 操作。](https://github.com/esm7/obsidian-vimrc-support/releases/tag/0.10.2) |
| realclaudian | 2.2.5 | [保留现有 CLI agent 面板与全部会话。](https://github.com/yishentu/claudian/releases/tag/2.2.5) |
| omnisearch | 1.31.0 | [全库关键词搜索与页内搜索。](https://github.com/scambier/obsidian-omnisearch/releases/tag/1.31.0) |
| cm-chs-patch | 1.14.0 | [中文分词和 Vim 中文词边界。](https://github.com/aidenlx/cm-chs-patch/releases/tag/1.14.0) |
| pdf-plus | 0.40.31 | [PDF 摘录、位置链接和阅读操作。](https://github.com/ryotaushio/obsidian-pdf-plus/releases/tag/0.40.31) |

共 15 个社区插件。移除 Atom、File Explorer Note Count、Better Word Count 和
Recent Files；计数交给核心 Word Count，目录与最近笔记交给 Notebook Navigator。
核心 Bases、File Explorer（后备）、Bookmarks、Backlinks 保留。
没有新增云端 AI、付费 API、图标插件或修改 Claudian 的 provider 设置。

## 首页与目录

- `Home.md`：问候、可点击搜索入口、五张学科卡片、继续阅读、待整理。
- `学科/{控制理论,数字电路,C++,微机原理,电力电子}/`：重写后的概念页与新增核心章节。
- `资料/摘要/`：原来源摘要；`资料/` 接收待整理资料。
- `综合/synthesis.md`：将原有跨领域观察扩写为有模型边界与算例的结构联系。
- `附件/`：原 assets；`附件/diagrams/` 同时收纳原 wiki/assets 的 SVG。
- `Excalidraw/`：保留目录名以保持原插件的 folder/library/script 设置。
- `_system/bases/`：学科与待整理 `.base`；`_system/views/`：本地首页视图。
- `_system/templates/`：概念模板；`AGENTS.md`：约 40 行页面约定。
- `TODO.md` 与 README 保留；wiki/index、wiki/log 和过时 skills/cache/team/smart 状态移除。

学科卡片由 Dataview 从真实文件元数据计算数量和最近更新时间。
继续阅读取工作区最近打开记录；新工作区没有记录时回退为最近更新。
待整理由[核心 Bases](https://help.obsidian.md/bases/syntax)筛选；无结果时由首页视图
隐藏空表，显示灰字“资料已全部整理”。学科卡片进入章节地图，Bases 按数值 order
排序。学习地图表达先后关系，数量与更新时间始终来自实际文件元数据。

第二轮重写原有 30 篇学科页、综合与摘要并补充核心章节；第三轮合并三组重复总览，
现在共 62 篇学科页。每科只有一个课程入口：自动控制原理、数字电路、C++、微机原理、
电力电子；旧总览名保留为 aliases。frontmatter 统一 updated、subject、order。
一句话定义和直觉按本科教材展开，“本页”列 2–3 个学习要点；完整限定、反例与进阶
术语放在相邻的默认折叠“严格表述”或“进阶”callout，真实技术勘误保留正文。
正文保留推导、折叠解答、误区与 3–5 道折叠自测；来源链接只在 sources 或文末“参考”。
SVG 图由交接目录的独立脚本生成，放入附件并嵌入正文。
TODO 的章节勾选表示资料覆盖，不代表用户已掌握。

Notebook Navigator 替代主文件树，保留原生树作为后备；目录用 Lucide 图标和
小面积学科色，列表显示两行摘要并按日期分组。部分 UI 偏好（双栏、目录展开、
选中目录、包含子目录、最近打开、首次更新提示）保存在每个应用配置的 localStorage，
不能只复制 data.json 后假定全部恢复。Homepage 的启动入口保存在其 data.json。
Quiet Outline 以真实当前章节高亮；进度条由活动阅读视图的 CSS scroll timeline
驱动，不伪造进度百分比；隐藏搜索框和层级滑块，仅保留标题树和进度。
Navigator 标签区仅显示五个学科标签，采用中性色，隐藏元信息噪声标签。
设置使用应用原生 Appearance 页面，关闭独立设置窗口选项，
以 modal 展示；保留 1.14 的原生分组和条目。

## 配置归属与同步

插件保留项的 data.json、hotkeys.json、.obsidian.vimrc、.claudian/、
.obsidian/claude-code-sessions/、.claude/settings*.json 不由本次改写。
`.gitignore` 仍忽略 .env、.claudian 与插件私有数据；只对新增七个插件的设计设置
开放 data.json 跟踪。Home、Bases、SVG 图标、视图与 vaults-ui.css 跟随笔记库 Git。

同步前先退出 Obsidian。主代理审核移动映射、完整状态和保护文件校验后再同步；
不要用带 `--delete` 的宽泛 rsync 将未复制的 .env、.trash 或 .claudian 状态误删。
不要把 vault-shot 的 workspace、Git 测试设置、受限模式或整个私有 HOME 同步回去。
受限模式、分词 WASM 的 IndexedDB 与 Navigator 偏好属于应用配置，而非可移植笔记文件。
真实配置已有分词组件时继续使用；新配置须通过插件自己的下载/校验流程安装后重载 Omnisearch。
Git 的原远端 MayonLos/Notes 已不存在，同步前须决定替代远端或停用自动推送。
截图副本在启动前关闭 Git 自动任务，并通过默认拒绝写入及远程命令的 wrapper 隔离；
这不等于真实笔记库的 Git 配置已修复。

## 手写、搜索与 PDF

保留既有全部快捷键：Ctrl+Alt+D 新建 Excalidraw；Ctrl+Alt+E 创建并嵌入；
Ctrl+Shift+O 全库搜索；Ctrl+Alt+F 页内搜索；Ctrl+Shift+C 复制 PDF 摘录；
Ctrl+Alt+W 适应 PDF 宽度。Vim 仍开启，Latex Suite 使用上游默认 snippets 并开启
vimEnabled，未修改 .obsidian.vimrc 或已有快捷键。
Excalidraw 既有笔模式、三个画笔预设、15 秒自动保存保持原设置。
PDF++ 原件编辑仍关闭；Omnisearch 没有 Text Extractor，不提供 PDF/图片 OCR。
没有改系统输入驱动或全局数位板映射。以下保留 2026-10-22 的测量范围，
不能视作本轮隔离视觉验证重新测试了真实数位板。

2026-10-22 没有安装其他手写插件，没有改变系统输入驱动或数位板全局映射。笔按钮目前产生的
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

## 历史备份与恢复（2026-10-22）

私有备份目录权限为 `0700`：

- `~/.local/state/obsidian-maintenance/20261022-220319/`：首次整理前完整
  `.obsidian` 归档，以及最先移出的七个插件目录。
- `~/.local/state/obsidian-maintenance/20261022-221553/`：替换 Smart 插件前完整
  `.obsidian` 归档，以及移出的 Smart Connections、Smart Context 目录。

每个备份中的完整归档名为 `obsidian-config.tar.gz`，移出目录位于
`removed-plugins/`；代码、配置与规则文件均保留。

恢复单个插件时，从 `removed-plugins/` 取回对应目录到 Vault 的 `.obsidian/plugins/`，
再在 Obsidian 内启用。四个不完整目录仅含旧配置，恢复文件本身不会补齐缺失的插件程序。
2026-10-22 当时没有删除笔记、附件、AI 会话、模型、索引、浏览器登录状态或 `.smart-env` 数据；本轮按用户要求删除过时 `.smart-env`。


## 验证边界

本轮只构建仓库配置，并在隔离 Obsidian 验证笔记库副本；没有系统激活，
没有访问真实笔记库，也没有向 Claudian 发送消息。每轮实际测试与未实现项见交接报告。
恢复旧目录或完整旧配置应从笔记库 Git 历史及上述历史备份取回，勿覆盖当前会话历史。
