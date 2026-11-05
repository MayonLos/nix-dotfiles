# Neovim 重写（2026-11-05）

用户要求“完全重构、优化美化，可推翻现有实现”，保留 AI、嵌入式调试、文档写作、会话与项目四个领域的全部功能。

## 流程

1. 五个 dsh（DeepSeek Harness）只读审计 ui、面板与 AI、编辑与 LSP、嵌入式、核心与项目；主代理抽查后否定了其中三条（ui2 不可用、README 仍写 blink.cmp、补全自定义触发与原生 autotrigger 重复）。
2. 用户决定：One Dark 只保留界面层覆盖、全局圆角、会话改用 mini.sessions，动画、AI 逐词接受、C++ 片段、MP157 配置全部保留。
3. 共用 `mayon/util.lua`（文档判断、winhighlight 合并、边框常量）先写好；五个领域各在独立 worktree 由 dsh 重写。DeepSeek 官方额度中途耗尽，剩余四个改用 opencode Go（`deepseek-v4.1-flash`，key 由 sops 注入）续作。
4. 每个领域由 Claude 子代理只读审查并做运行时复现，共发现约 15 个缺陷（附加进程 pid 传成函数、`:q` 无法退出、签名浮窗抢焦点、resolve 后文档窗无样式、手动加载会话清掉终端与 AI 缓冲、willRename 编辑落到旧路径等），再由子代理修复、补回归测试，主代理复核后合并。
5. 视觉设计稿先用单元格网格 HTML 加 headless chromium 渲染给用户确认；用户否决 surface/deep 色块分层，定稿为“一块画布”。实现后在私有无头 sway 中用真实 Kitty 和 grim 截图核对，修正了浮窗内边距与 AI 面板行号。

## 结果

- 默认安静：符号大纲只手动打开；新增常驻轮询全部去掉，Claude 连接状态只在 AI 面板可见时每 500ms 查询一次。
- 去掉对 which-key、Snacks picker 内部函数的补丁和两个 `_G` statuscolumn 函数；Oil 适配器与 tiny-inline-diagnostic 的补丁保留并集中注释。
- 会话恢复保留旧的分支 → 无分支 → 旧编码名回退顺序，并恢复了多实例互不覆盖的 mtime 保护。
- 视觉规格见 `docs/neovim.md` 的“2026-11-05 重写”一节。
