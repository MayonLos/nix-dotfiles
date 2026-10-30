# Docker 页

Rust Docker Engine API 终端客户端，沿用 mayon-tui 的 One Dark、细线框、淡底选中行和蓝色侧标。轮询与日志使用 Tokio，不自行启动 daemon。`--host unix:///path/docker.sock` 优先于 `DOCKER_HOST`，否则使用 `$XDG_RUNTIME_DIR/docker.sock`；只接受 Unix socket。

## 页面与键位

- `1` 容器：按 Compose 项目分组，显示端口、CPU、内存；`Enter` 完整详情，`o` 切排序。
- `2` 镜像：大小、标签、悬空标记。
- `3` 卷：大小与引用状态；未知引用受保护。
- `4` Engine 概览：版本、四类磁盘占用和安全可回收量。
- `5` Docker + VM 空间：`Tab` / `v` 切换 Docker 和 VM 分区。Docker 清理：镜像、容器、卷、构建缓存混合明细，按占用降序排列。`Space` 多选/取消，所选合计预计释放量始终显示；`/` 按类型、名称或完整 ID 过滤，跨过滤保留选择。所有资源初始均不选，卷绝不自动选中。
- `j/k`、方向键、滚轮和单击选择；单击页签切页；`?` 帮助，`q` 退出。

容器页保留 `s` 启停、`r` 重启、`p` 项目启停、`R` 确认重启整个项目、`l` 跟随日志、`e` 在新 Kitty 中 exec（探测 bash，回退 sh）。日志内 `j/k` 滚动、`G` 跟随、`/` 过滤、`Esc` 返回。`S` 单独确认停止本地 docker/代理服务，仅标准本地 socket 可用；停止后暂停轮询，`s` 恢复连接。清理不会停止容器。

## 清理安全与确认

清理页 `Enter` / `d` 冻结所选 ID，逐项显示完整 ID/卷名、类型、占用和预计释放空间。`j/k` 看完全部项目后，第一次 `y` 进入二次确认，第二次 `y` 执行。含卷时，每个卷还必须单独输入 `DELETE 完整卷名` 再按 `Enter`；**卷内数据删除后不可恢复**。`Esc` 在任何确认阶段取消。容器/镜像/卷页的 `d` 也走同一预览流程。没有跳过预览的一键全清，也没有 volume prune。

运行中、暂停、重启中及状态未知的容器不可选；只有 `exited`、`created`、`dead` 可选。所有仍被容器引用的镜像、卷都受保护（包括已停止容器的引用）；缺失/未知引用计数也受保护。删除停止容器不会自动选中其镜像或卷，需要刷新后重新预览。执行前逐项重新查询 `/system/df`，状态改变的项目跳过并报告失败；不自动增加清单项目。

容器删除使用 `force=false&v=false`，保留关联卷；镜像使用 `force=false&noprune=true`，防止隐式删除清单之外的悬空父镜像。缓存只允许未使用且不共享的条目，每次提交一个锚定 `^ID$` 筛选，带 `inuse=false,shared=false`。不支持精确筛选的 daemon 直接失败，不回退到全清。

报告持续显示各完整 ID 的成功/失败，`j/k`、滚轮可滚动，`Esc` 关闭。实际释放量取 daemon 占用前后差值，另显示缓存 API 的 `SpaceReclaimed`；有未知大小或查询失败时显示未知。并发 Docker 活动会影响前后差值，不能将它视为文件系统的精确空闲增量。预估只计镜像独占层，Shared 缓存受保护；同时删除共享镜像可能实际释放更多。卷大小为 `-1` 时显示未知，不当作零。

## CLI

```sh
# 只读，打印四类总览和完整明细；不创建终端、不提交 mutation
 mayon-tools docker df

# 仅预览明确 ID（必须完整匹配，不接受前缀或通配符）
 mayon-tools docker clean --image sha256:FULL_ID --container FULL_ID --cache FULL_ID

# 执行必须显式 --yes，打印准确清单后还需输入 DELETE 二次确认
 mayon-tools docker clean --image sha256:FULL_ID --yes

# 卷必须显式给名字；还需单独输入 DELETE 与所有完整卷名
 mayon-tools docker clean --volume NAME --yes
```

选择器可重复使用；普通清理不会包含未指定的卷。无选择器的 `clean`、`df --yes` 等非法组合在连接 daemon 前拒绝。取消不提交删除请求；部分失败返回非零退出码。`--help`、`--version` 无需 socket，直接退出。`df` 即使 Docker 不可用，也会继续输出 VM 数据和各连接的不可用原因。`clean` 仍只接受 Docker 选择器，没有 VM 删除选项。

## 实现依据与验证

`api.rs` 管 Engine 模型和请求，`cleanup.rs` 管安全规则、大小计算、冻结计划与确认状态，`app.rs` 管 TUI，`main.rs` 管 CLI。API 固定 [Engine v1.47](https://docs.docker.com/reference/api/engine/version/v1.47/)，数据来自 `/system/df`（与 `docker system df -v` 同源）。精确缓存筛选依据 [Moby v27.5.1 BuildKit 实现](https://github.com/moby/moby/blob/v27.5.1/builder/builder-next/builder.go)：`id` 实际使用正则匹配，因此必须校验并锚定。视觉与交互复用仓库 mayon-ui，没有新增外部 UI 框架。

从 `packages/mayon-tui` 运行：

```sh
CARGO_BUILD_JOBS=6 cargo test -p dockertui-mayon
CARGO_BUILD_JOBS=6 cargo clippy -p mayon-tools docker --all-targets -- -D warnings
cargo fmt --all -- --check
CARGO_BUILD_JOBS=6 cargo build -p mayon-tools
python crates/docker/tests/cli_mock.py target/debug/mayon-tools
```

`cleanup_tests.rs` 覆盖运行状态、引用保护、默认空选择、共享层/未知大小/饱和计算和确认流程。`tests/mock_engine.py` 是线程化 Unix socket fixture，只允许在本 worktree `.work/` 监听；所有删除仅改变内存数据。`cli_mock.py` 验证真实二进制与该 fixture 的预览、取消、参数、防误删、卷输入和执行报告。视觉验证使用隔离 headless sway + 真实 Kitty + mock socket；不连接用户桌面或真实 Docker。

本 crate 不拥有 daemon units，不写持久配置或用户数据文件；选择和报告只在内存中。使用调用用户已有的 Unix socket 权限，不提升权限。测试 socket/日志只位于测试工作目录；移除程序不会删除镜像、容器、卷、项目或登录状态。真实 daemon 版本兼容、并发创建/挂载资源时的实际拒绝行为、磁盘真实释放量与 Kitty exec 仍需另行实机核对。

## VM 空间（严格只读）

根据仓库 `aspects/dev/virtual-machines/` 的实际配置，virt-manager 默认使用 `qemu:///system`，libvirtd 通过 socket 激活、QEMU 不以 root 运行；主机选择授予 `libvirtd` / `kvm` 组。本面板独立查询 `qemu:///session` 与 `qemu:///system`，不修改 libvirt 配置、不启动/关闭 VM、不刷新或启动存储池、不提权。缺 `virsh`、未启用服务、权限拒绝、查询超时或功能不支持都会显示原因，保留另一个连接的结果。

空间页 `Tab` / `v` 切到 VM：列出 VM 名称和状态、当前与持久配置中的磁盘、已知 backing/dataStore/mirror 依赖、快照及快照磁盘/内存、ISO、存储池里的未引用镜像候选。按已知实际占用降序；`/` 过滤名称、类型、URI 和完整路径，`Enter` 看完整路径/说明，详情中 `j/k` 滚动，`y` 复制路径（`wl-copy`），`r` 刷新 VM 元数据，`Esc` 返回。**Space、d 不会选择或删除任何 VM 资源；VM 没有清理命令。** Docker 暂停后仍可查询、浏览和复制 VM 路径。

文件实际占用取 stat 的 `st_blocks × 512`，共享文件、硬链接和跨 URI 重复引用按设备号/inode 去重。它不是文件的逻辑长度；压缩、CoW/reflink 共享 extent 可能使文件块数之和不同于文件系统实际独占占用。ISO 和明确声明为 raw 的 VM 磁盘可从文件逻辑长度显示虚拟大小。**qcow2/vmdk 等虚拟容量默认显示未知**：为了严格不读取镜像内容，面板不调用 `qemu-img`，也不调用可能由 libvirt 打开镜像头的 `domblkinfo`、`domstats --block`、`vol-info` 或 `vol-dumpxml`。详情解释未知原因，不把 qcow2 的文件长度误当虚拟容量。此取舍依据 [libvirt QEMU driver](https://github.com/libvirt/libvirt/blob/v11.0.0/src/qemu/qemu_driver.c) 和 [storage driver](https://github.com/libvirt/libvirt/blob/v11.0.0/src/storage/storage_driver.c) 的实际读取行为。

查询仅使用 `virsh --readonly --connect URI` 的固定白名单：`list`、`domstate`、`dumpxml`（当前和 `--inactive`）、`snapshot-list`、`snapshot-dumpxml`、`pool-list`、`pool-dumpxml`、`vol-list`、`vol-path`。不请求 `--security-info` 或 secrets，不解析外部 XML 实体。XML 解析器限制 4 MiB / 64 层，拒绝 DTD。

孤立候选仅限已登记的本地 dir/fs/netfs 存储池目录（最多 4 层 / 10000 个目录项）及登记卷；不会遍历整个 HOME 或系统。已知 VM 引用路径即使在池外，也会列出并 stat。任一 URI、VM XML、快照、backing 链或扫描不完整时，未引用文件标成“未引用待核实”。即使显示“孤立镜像候选”，也只表示未见已列 VM/快照/已知链引用，不证明镜像可删除；**孤立镜像、ISO、快照及 VM 磁盘始终保留**。关机域 XML 可能省略 backing 链，面板不会为补全链而读取镜像头。内部快照已包含在磁盘占用内，无法独立分摊时明确显示未知。

`vm.rs` 负责只读盘点与路径复制，`vm_xml.rs` 解析 XML 元数据，`vm_tests.rs` 覆盖稀疏大小、路径空格、引用完整性与去重。`tests/mock_virsh.py` 只响应本地 fixture 的只读白名单；`tests/vm_mock.py` 创建无价值稀疏文件，以私有 PATH 和不可用 Docker socket 验证 `df`、未知链和权限降级。不会连接真实 libvirt 或读取真实镜像内容：

```sh
python -B crates/docker/tests/vm_mock.py target/debug/mayon-tools
```

VM 盘点每 30 秒刷新，单次 virsh 查询超时 3 秒，每个连接总超时 30 秒，超限则显示原因。选择与结果只存在内存，没有新增持久配置；路径复制需要当前调用用户已有的剪贴板能力，失败时完整路径仍可在详情/CLI 查看。

工具箱首次进入 Docker 页才连接 Docker；切走或失焦取消数据、统计和日志任务，保留筛选、子页与日志缓冲。VM 只在空间页的 VM 区域可见时采集。日志保留最多4000行且不超过4MiB。顶层 `[ / ]` 切换工具。
