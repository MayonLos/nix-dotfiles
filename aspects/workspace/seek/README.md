# Seek

`seek` 是独立的 workspace 功能：学生资料包括笔记、课件、作业与代码，既不属于
AI coding agent，也不依赖某个桌面会话。公开入口为 `default.nix`；公开测试钩子为
`checks.nix`。Den 选择 `seek` 后安装公开 `pkgs.seek`、桌面入口和用户 timer。
真实 host/user 选择由主代理集成，本分支不修改 inventory 或 desktop。

输入：用户自己审核的 `~/.config/seek/config.toml`（include/exclude/confirmed、OCR、
嵌入和问答后端）；DeepSeek 的 `qa.key_file` 指向 sops 运行时文件。feature 不声明
或读取秘密、不生成可变配置、不安装或启动 Ollama。默认不外发，只有显式 `ask`
或 TUI 发送确认使用后端。首次 `seek init` 只调查家目录两级目录名，写未确认建议。

输出：`seek` CLI/TUI 和 `seek-index.service` / `seek-index.timer`。timer 由
`timers.target` 启动，15 分钟后首次、随后每 2 小时（10 分钟随机延迟）；oneshot
以 Nice=19、idle IO、CPUQuota=50%、MemoryMax=2G、UMask=0077 运行，电池供电时推迟。
确认前不读资料；没有 config 时 condition 跳过。无 inotify daemon、无开机模型进程。
OCR 默认关；需要时另安装含 `chi_sim` 和 `eng` 的 Tesseract。

拥有文件：本目录的 Nix 与 README，以及上述包/desktop entry/unit 声明。
用户配置和 `~/.local/share/seek/` 索引、模型由程序/用户独占写入（详情见
[程序 README](../../../packages/seek/README.md)）。移除 feature 会移除安装声明及 timer，
保留配置、模型、索引、所有源资料。构建不激活 timer，不等于已经安装或应用。
