# 第八轮：架构 v2.1 重构执行记录

本轮只修改源码、求值和构建，未激活系统、未执行 sudo 或 nixos-rebuild，未 stage、commit、push、stash、reset 或更新 flake.lock。冻结提交为 `cdbe549ba857377d045f8fa17843582dd829b3a9`，开始时工作树干净。所有移动使用普通 mv/rename，由主代理后续审阅、暂存；未删除用户数据或修改 sops 加密内容。

## 基线与结果

完整结构化数据见 [B0](architecture-v2-baseline.json) 和 [结果](architecture-v2-result.json)，逐文件迁移/新增/分拆见 [文件清单](architecture-v2-files.tsv)。

| 输出 | 对比 |
|---|---|
| toplevel outPath | 严格相等：`/nix/store/g3bzi4prsy0las13mycrc5zqlxkz1h2z-nixos-system-nixos-btw-26.05.20261021.da6dc0e` |
| packages.x86_64-linux.neovim / neovim-dev drvPath | 两项均严格相等 |
| devShells.x86_64-linux.default / cuda drvPath | 两项均严格相等 |
| formatter.x86_64-linux drvPath | 从 `gnzdpjchra7y0fg97il09wlwi3i9crvn-treefmt.drv` 改为 `lfcw0cfad42dlgyhbnn4xpd9l5gffwzs-treefmt.drv`：statix 由自动 fix 改为只检查，保留 deadnix 的 `--no-lambda-pattern-names` |
| checks 名单 | 原 18 项保留，新增 architecture、statix、deadnix，共 21 项 |
| flake.lock、stateVersion、包依赖组合 | 保持不变；系统等价以严格相等的 toplevel 为准 |

最初未经 Git 过滤的路径诊断含本地忽略内容，不能作为 B0，已弃用。正式 B0 通过指定 Git 提交求值取得，并以只含跟踪文件及本轮经过检查的新源码的临时快照交叉确认相等。后续临时快照位于仓库 `.work/refactor-v2/source`，排除 `.git`、所有 `.work`、`.team`、`.worktrees`、`result*` 和 Git 忽略的本地文件，不使用整个工作树的 `path:.`。新文件没有暂存，因此最终构建使用该过滤快照的 `path:` flake；尚未在主代理暂存后的 Git flake 上复核。

每批记录保存在忽略的 `.work/refactor-v2/`。包通道、host 管线、inventory、各领域目录、契约、lib、override、子 aspect 后缀、公开检查钩子及格式化均分别比对。目录批次曾发现 shell `cd ../..` 被路径重写误改，已修正后恢复相等；中间失败诊断不作为接受结果。之后所有接受的实现均恢复 B0。

98 个非 Nix/Markdown 的 aspect 资源文件逐一比对：内容和 basename 全部保持一致。Neovim `.work` 未迁入新目录；原位置仅保留本地临时目录，不属于登记源码。

## 目录与身份

源码登记表现有九个导航领域、30 个功能目录，全部有 README：

```text
aspects/
  system/       default-tools, maintenance
  hardware/     legion-laptop
  appearance/   appearance, avatar
  desktop/      session-support, mango-session, xorg-session, greeter
  cli/          shell, terminal
  dev/          ai-agents, containers, editor-runtime, embedded, jetbrains,
                languages, neovim, virtual-machines, vscode
  apps/         communication, documents, file-manager, firefox, gaming, media
  network/      laptop-network, remote-access
  workspace/    project-workbench, workspace-task
```

既有功能 aspect ID 保持不变，目录名不承担身份含义。仅以下具名 host 子 aspect 统一后缀，并在单独批次验证严格相等：

| 原 ID | 新 ID |
|---|---|
| editing-runtime | editing-runtime-host |
| gaming-host-support | gaming-host |
| embedded-host-support | embedded-workbench-host |
| local-containers-host-support | local-containers-host |
| local-virtual-machines-host-support | local-virtual-machines-host |

新增 avatar、avatar-host、legion-laptop-user、tree-account-tool、network-manager-user 与 host-pipeline，只承接迁出的既有实现。没有通过改目录名重命名 interactive-session、login-screen、command-line 等既有功能 ID。

## 规范落实

| 规范 | 结果与证据入口 |
|---|---|
| §2–3 目录/功能 | 九领域显式登记；桌面按规定四组拆分；功能 README 记录用途、输入、输出、拥有文件和移除残留；资源只移动、basename 与内容保持一致 |
| §3.3 class | 保留 Den 上下文参数形状；需要上下文的拆分文件使用显式偏应用，不依赖路径 imports 注入 host/user |
| §4 通道 | 使用 includes、schema、已校验 quirks、公开选项/包工厂；Firefox 模板和头像选中标记经 quirk 贡献；host 支持具名路由，授权留 user class/绑定 |
| §5 契约 | appearance/default-tools/languages/desktop-integrations 契约各归其功能；Neovim 显式接收默认数据；ANSI/壁纸是 README 声明的公开数据 |
| §6 inventory | 身份、facts、绑定、扫描工件与秘密声明分离；生成脚本、头像、锁屏 widget、GPU/mpv、lenovo-legion、NH 和 shell 消费者均迁入功能 |
| §6 host 管线 | nix/hosts.nix 经 schema 提供 mkDefault instantiate 与 HM defaults，按当前 host/system/facts 获取 pkgs。锁定 HM 的 extraSpecialArgs 是浅 attrs，故先在 schema 的 homeManagerArgs 上 mkDefault，再普通传给 HM，避免上游 nixosConfig 丢弃默认参数 |
| §7 bundles | 只保留 includes 组合，无实现或实体声明 |
| §8 包/输入/lib | 两个 nixpkgs 实例集中 nix/pkgs.nix；portal overlay 位置/顺序不变；白名单 qq/wechat/jdk26；第三方包只做原始 drv 别名。无满足多功能共享无参条件的配方，不预建 packages 目录；lib 仅留 java/seed-file/service 三个多功能消费者 helper；输入有 follows 策略注释 |
| §9 状态/服务 | 不清理任何用户数据；秘密通过实际 sops path 消费；既有脚本名称、文本和服务行为保留。更新写入归属及服务路径文档 |
| §10 检查 | 功能钩子统一公开 checks.nix 签名，nix/checks.nix 显式登记并复用真实主机 config；架构扫描在求值时 deepSeq，违规 throw；负例同时验证诊断与入口确实失败；statix 不自动修复 |
| §11 等价 | 正式 B0 冻结 Git 提交，接受批次/最终 toplevel 严格相等；packages/devShells 相等；formatter/checks 的限定变化如上表 |
| §12 文档 | 保留原文件名，新增 operations；更新现行文档、索引、AGENTS 和功能 README。历史链接受只追加规则约束，见下文 |

`mkForce` 从 19 处减到 18 处；`mkOverride` 仍为 0。移除 CLI Bat 主题 force，将会话支持的 base16 改为 mkDefault 后由 CLI 普通赋值。余下 18 处分别覆盖上游 unit/socket、Picom、Rime、Markdown MIME 或 Bat cache 行为，逐处有 `# force:` 原因。未自动删除 aspect/class 函数参数。

独立 reviewer 核实锁定 Den 与 HM 的参数、路由、浅合并行为，复核修正了头像无 Mango/移除选择、多秘密自定义路径与目录插值扫描绕过。头像新增组合测试覆盖独立、Xorg 及保留身份数据移除功能；现有双主机双账号、共享去重、冲突负例、无桌面和客户端不启 daemon 语义检查保留。

## 实际验证与边界

- `git diff --check` 通过；新文件另由 formatter/直接空白检查覆盖。
- `nix fmt` 已实际成功执行。Nix 2.34.9 的 fmt 从 cwd 发现 flake：本轮从过滤源码的 store 快照调用该 formatter，以 `--working-dir` 指回仓库并传显式源码文件列表，避免未暂存文件导致 Git flake 缺文件，也避免格式化本地临时目录。
- `nix flake check --no-build --no-write-lock-file path:<过滤快照>` 通过，含求值期架构检查与负例。
- 实际 `nix build --no-link --no-write-lock-file` 构建全部 21 个 checks 与 toplevel，成功；部分输出复用已有 store/cache。treefmt 构建检查 255 个源码文件、0 变化。Xorg 隔离检查出现非致命 C.UTF-8 编码提示，命令最终成功。
- 未激活、未实机验证；没有声称冷登录、设备、QQ 真实通话/捕获、GUI 外观或服务运行态通过。

最终扫描器补强通过内置正负例和 statix 检查；交付前针对最终过滤源码再次运行完整求值与全部输出构建。未另做三次性能剖析，也不据此宣称性能改善。

## 历史链接待决项

现行文档、功能 README、根 README、AGENTS 与 tests README 的相对链接可解析。四份历史 Markdown 中 18 个源码链接随迁移失效；另检测到旧 optimization 记录一处既有章节 anchor 不匹配；规范 §12 要求 history 只追加，因此尚未改写这些旧记录。已在 `.work/refactor-v2/history-links.patch` 准备只改链接目标的具体补丁（18 个源码目标与 1 个既有 anchor），并向用户请求该例外；未把未应用补丁写成链接检查通过。

主代理还需审阅和暂存新文件，再用 Git flake 复核。此为用户明确禁止本执行代理 stage 的交接步骤，不是系统构建失败。所有其他功能迁移和构建已完成；无需执行 switch/test 来证明本轮源码构建。
