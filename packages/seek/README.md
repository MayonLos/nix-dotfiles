# seek · 本地资料检索

独立 Rust 工作区，公开包工厂 `default.nix { pkgs }`，公开输出 `pkgs.seek`。
只读复用 mayon-ui 的 One Dark 色板、终端生命周期与 chrome；不修改共享 UI。
实现参考 [Tantivy](https://github.com/quickwit-oss/tantivy) 的 BM25、
[jieba-rs](https://github.com/messense/jieba-rs) 搜索分词、
[fastembed-rs](https://github.com/Anush008/fastembed-rs) 的本地 ONNX 推理，
和 [BGE 模型说明](https://huggingface.co/BAAI/bge-small-zh-v1.5) 的中文查询前缀。
不复用完整知识库服务器，按需进程退出后没有常驻内存。

```sh
seek init                      # 仅列家目录两级目录名，写未确认建议
$EDITOR ~/.config/seek/config.toml  # 审核 include/exclude
seek init --confirm             # 明示范围，输入 yes 确认
seek model download            # 仅下载公开模型，不发送资料
seek index                     # 增量抽取与嵌入
seek query '热方程的边界条件' --json --limit 8
seek tui --viewer zathura
seek ask '热方程的边界条件是什么？' --dry-run  # 仅预览问题/片段
seek ask '热方程的边界条件是什么？'           # 显式外发
```

首次建议只选存在的 `Vaults`、`notes`、`Documents/notes`、`Dev`、`latex`。
Downloads/整个 Documents 不默认选，避免混入聊天附件、游戏和应用状态。
每个路径都须是绝对目录。默认不跟随 symlink；排除隐藏路径（包括 .cache、.git、
.local/share/Steam）、node_modules、target、Steam、PrismLauncher、VM 目录/镜像、
聊天数据、secrets 和常见凭据文件。**排除表不是秘密检测器**；应只选择适合检索的资料目录。
用户手动改范围后应再次 `seek init --confirm`，索引时按当前配置删除已排除内容的活跃记录。

`--config` / `--data-dir` 可隔离运行。配置默认 `~/.config/seek/config.toml`；
数据默认 `~/.local/share/seek/`（均尊重对应 XDG 环境变量）。目录 0700，配置、
CURRENT/status/model 的原子写文件 0600；SQLite/Tantivy 在私有生成目录内。
索引包含**明文片段**，不适合共享数据目录或云端同步。

模型固定为 Xenova/bge-small-zh-v1.5 的 INT8 ONNX，revision
`75c43b069aac4d136ba6bc1122f995fedcfd2781`；首次显式下载到
`model/<revision>/`（约 25 MB）。下载器只访问该公开模型文件，常规索引/查询不会下载。
CPU 运行时由 Nix 包提供 ONNX Runtime；普通 Cargo 开发需设置
`ORT_DYLIB_PATH=/path/to/libonnxruntime.so`。不需要 GPU、API key 或 daemon。
模型未准备好时会报错；可设置 `embeddings=false` 并 `seek index --force` 先用 BM25，
查询也支持 `--lexical`。向量按 chunk 存储，余弦扫描后与 BM25 做 RRF（k=60）。
当前不提供 cross-encoder 重排和 inotify daemon。

抽取支持 UTF-8 md/txt/常见代码、PDF（Poppler 分页）、docx/pptx/xlsx（有界 ZIP/XML）。
分块最多 700 字符，保留路径、标题、页/slide/sheet 和抽取文本行号；docx 无可靠物理页码，
使用行号；XLSX 的 page 是 sheet 顺序，PPTX 的 page 是 slide 顺序。代码只有白名单扩展名。
不解析旧二进制 doc/ppt/xls、图片或 Obsidian/Quill 的私有二进制数据库；Quill 若为
Markdown/文本导出可直接检索。OCR 默认关，`ocr=true` 时逐扫描页调用 Poppler +
Tesseract `chi_sim+eng`，需要额外安装语言包。索引失败项显示原因。

增量以 mtime/大小先跳过，再比较 BLAKE3；仅修改文件重新抽取/嵌入。每次索引重建
Tantivy 检索段，新生成完整后原子发布 `CURRENT`，已有查询继续使用原生成。并发索引用
文件锁拒绝。改变/失败文件会从新一代移除旧片段，删除文件也会移除。当前保留历代生成以
保护并发读取；**旧生成仍含历史片段**，需要回收时停止 seek 进程后仅清理数据目录中的
`gen-*`（不要删源资料；保留 CURRENT 指向的一代），后续可增加自动保留策略。
文件 mtime 和大小都被人为恢复时需 `seek index --force`。

问答仅显式 `ask` / TUI 的 `a` → Enter → `y` 触发，发送问题与最多 20 个片段
（TUI top-5），每片段最多 1200 字符及路径/页码元数据，不上传整文件。回答追加原始来源列表，
模型生成的事实与引用仍需人工核对；片段作为不可信资料指示模型处理。
默认后端是 DeepSeek 官方 HTTPS，使用 `deepseek-flash` 并关闭 thinking；模型名依据
[当前官方 API 文档](https://api-docs.deepseek.com/api/create-chat-completion/)，不使用已停用的
`deepseek-chat`。key 只在请求时读取 `qa.key_file`，默认
`/run/secrets/deepseek-api-key`。sops 应设 owner 为用户、mode `0400` 或 `0600`；
不把 key 字面值写入 Nix、config、环境变量、store 或日志。
程序不创建 sops 声明，由主代理按现有 secrets 管理接线。支持 `qa.backend="ollama"`、
`qa.model="<已安装模型名>"`，仅访问 `127.0.0.1:11434`，不会启动或安装 Ollama。

TUI：`1/2/3` 切搜索/问答/索引，`/` 编辑，Esc 结束，↑↓/j/k/滚轮选择，Enter 打开，
`Tab` 窄窗切预览，PgUp/PgDn 滚动，`a` 问答，`?` 帮助，`q` 退出。
90 列下单栏显示，宽窗右侧预览；片段只从索引读取。PDF 默认 xdg-open file URL
带 `#page=N`（依 viewer 支持）；`--viewer zathura/okular` 明确传页码 argv。
其他文档用 xdg-open；docx/代码默认程序不能保证定位到行。
搜索后台线程合并待查问题并忽略过期返回；问答独立线程，不阻塞绘制。
运行时索引更新后重开 TUI 载入新代（当前会话保持快照）。

`seek query --json --limit 8 '问题'` 输出稳定数组，字段
`path,page,title,line_start,line_end,text,score`（page 为 null 表示无页码）。
`seek open '问题' --rank 1 --viewer zathura` 打开结果。`seek batch` 从 stdin 逐行读问题，
逐行输出 `{query,elapsed_ms,hits}`，模型加载一次后处理，stdin 关闭就退出，供基准或 provider
批处理使用，不创建 socket/server。查询目标 <200 ms 指**已加载模型后的检索**；
冷进程包括 Jieba/ONNX 初始化，不能承诺 200 ms。

开发：`CARGO_BUILD_JOBS=6 cargo test --locked`、`cargo clippy --all-targets -- -D warnings`、
`cargo fmt --check`。`tests/fixtures.py <私有目录>` 仅生成合成语料，
`tests/benchmark.py --binary <seek> --root <合成语料目录> --output <报告> [--lexical]`
在独立 HOME 内建索引并测试 20 题 hit@5 和热查询延迟。默认混合模式需公开模型下载，
`SEEK_TEST_ORT` 可显式传入测试用 runtime 路径。Nix check 跑单元测试、fmt、clippy 和
纯 BM25 合成基准，不在 sandbox 下载模型。完整混合质量与 1 万文件规模性能须另测。
