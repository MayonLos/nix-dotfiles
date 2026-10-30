# mcsrv-mayon

`mcsrv-mayon` 是本机 Minecraft Java 服务端的 Rust CLI/TUI 管理器，目标是让用户在不记启动命令的情况下创建实例、启动服务、查看控制台、管理玩家、备份世界并配置联机。实例互相独立，服务按需启动，不设置开机自启。

## 使用范围与安装来源

当前安装器支持 Mojang Vanilla、Paper、Fabric、Forge、NeoForge、GTNH 官方服务端 ZIP、Modrinth `.mrpack`，以及从 Prism 实例复制 `mods/` 与 `config/`。Paper 下载走 Fill v3，只选 `STABLE` build 并校验官方 SHA-256；Fabric 使用官方 Meta API；Vanilla 校验 Mojang manifest 中的 SHA-1。Forge/NeoForge 需要相应的 server installer。Modrinth `.mrpack` 根据其 manifest 的 Minecraft 与 loader 版本安装 server loader，再下载服务端文件和 overrides。

首次创建时必须明确接受 Minecraft EULA。Mod、整合包和服务端包会运行第三方 Java 代码，只安装信任的来源。已有同名实例不会覆盖；下载和归档解包会校验文件 hash（如来源提供），拒绝越界路径和 ZIP 符号链接，并限制下载和解压大小。

GTNH 版本号是整合包版本，不是 Minecraft 版本。比如 `2.9.0-RC-2` 下载自 GTNH 官方 `ServerPacks/betas/`，普通发布包取 `ServerPacks/`。当前已确认的 2.9.0-RC-2 Java 17–26 服务端包地址为 [`GT_New_Horizons_2.9.0-RC-2_Server_Java_17-26.zip`](https://downloads.gtnewhorizons.com/ServerPacks/betas/GT_New_Horizons_2.9.0-RC-2_Server_Java_17-26.zip)。创建后，管家检查 `java9args.txt` 和 `lwjgl3ify-forgePatches.jar`，按 lwjgl3ify 上游命令启动：

```sh
java -Dfml.readTimeout=180 -Duser.language=en @java9args.txt -jar lwjgl3ify-forgePatches.jar nogui
```

内存由管家在 `java` 后注入，保留 `@java9args.txt`、forgePatches JAR 与 `nogui` 参数。GTNH 默认选 Java 21；若包内启动布局与上述文件不符，创建会报错。本轮隔离验证已下载该官方包并以 Java 21 启动到 `Done`；这不代表现有用户存档的升级迁移已验证。

Prism 导入需要提供实例根目录（含 `mmc-pack.json`）。程序读取 Minecraft 与 loader 组件，复制其 `mods/` 和 `config/`；若发现 `lwjgl3ify` Prism 客户端组件，则拒绝把 1.7.10 客户端当成普通 Forge 服务端，GTNH 请用官方 Server ZIP。JAR 的 `fabric.mod.json` 明确写有 `environment: "client"` 时会自动排除；无 Fabric 元数据的 JAR 会尝试以 SHA-1 查询 Modrinth，只有项目明确标记 `server_side=unsupported` 才排除。404、兼容状态未知或 API/网络错误都会保留并写入报告，不会因查询失败丢弃文件。未知 Forge/其他格式需用户手工核对服务端兼容性。每次导入的依据与保留/排除清单写入实例私有文件 `import-report.txt`；源 Prism 实例只读。

Modrinth 模组搜索和安装筛选当前 Minecraft 版本及 loader。安装会递归处理必需依赖，拒绝项目标记为服务端不支持或兼容性未知的模组；`server_side=optional` 会提示确认。依赖逐项下载校验；若后续依赖或主模组失败，之前成功安装的文件会保留，安装不是整批事务。目标文件已存在时仅在哈希匹配后复用，绝不覆盖内容不匹配的文件。更新只处理可由 SHA-1 在 Modrinth 文件索引中识别的 JAR；新版本按匹配游戏/loader 选择，并先安装其必需依赖；`server_side=unknown` 或 `unsupported` 的项目拒绝更新。旧 JAR 留在 `mods/.mcsrv-backups/`，不自动清理。未被 Modrinth 识别的 JAR 原样保留。Mod 差异按文件名与 SHA-1 显示仅服务端、仅 Prism 或同名不同内容。

## Java 选择

Java 运行时来自 [`lib/java.nix`](../../lib/java.nix) 的 Temurin 集合，支持 8、17、21、25、26；包将公开 store 路径通过非秘密 `MCSRV_JAVA_MAP` 交给命令。创建前会解析 Prism/mrpack 中实际 Minecraft 版本，再选择 JDK；`--java 17` 等可显式指定已提供的版本。

自动选择规则目前是：GTNH 用 21；Minecraft 1.20.5+ 与 1.21+ 用 21；1.17–1.20.4 通常用 17（Paper 的当前实现对 1.20/1.21 选择 21）；1.16 及更早用 8；未识别版本回退到 25。应以对应 loader/整合包官方兼容要求为准。

Forge/NeoForge 可以把 Minecraft 与 loader 版本写成 `MC@loader`，例如 `1.20.1@47.3.0`。没有指定 loader 时，Forge 使用官方 `recommended` promotion（可用 `--source latest` 选择 latest）；NeoForge 从官方 Maven metadata 按目标 Minecraft 版本匹配，默认只选稳定 loader。TUI 的创建向导把 `--source` 显示为通用“服务端包/本地 Prism 实例路径或 URL”提示；Forge/NeoForge 可在这里填 `recommended` 或 `latest`，Prism 和 mrpack 则填本地路径。

## CLI

默认不带子命令时进入 TUI。常用 CLI 示例：

```sh
mcsrv-mayon                         # 打开 TUI
mcsrv-mayon list
mcsrv-mayon create friends --kind paper --version latest --memory 4096 --port 25565 --whitelist --accept-eula
mcsrv-mayon create gtnh --kind gtnh --version 2.9.0-RC-2 --memory 8192 --accept-eula
mcsrv-mayon start friends
mcsrv-mayon status friends
mcsrv-mayon logs friends
mcsrv-mayon command friends "say hello"
mcsrv-mayon backup friends
mcsrv-mayon backups friends
mcsrv-mayon restore friends <快照ID> --confirm <同一快照ID>
mcsrv-mayon config friends --backup-minutes 30 --keep-last 20 --lan
mcsrv-mayon mods friends search "journeymap"
mcsrv-mayon mods friends install <Modrinth项目ID或slug>
mcsrv-mayon mods friends update
mcsrv-mayon mods friends diff /path/to/Prism/instance
mcsrv-mayon network friends
mcsrv-mayon network friends --connect
```

`create --source` 对 Prism/mrpack 接收本地路径；GTNH 通过官方版本号下载，不接受任意 URL。`--offline` 关闭正版验证，默认开启；`--whitelist` 开启白名单，默认关闭；`--rcon` 可选启用 RCON，默认关闭；启用时必须 `--bind 127.0.0.1` 或 `--bind ::1`，不与局域网监听混用；`--bind` 可指定服务端绑定 IP。Aikar JVM flags 可选，仅适用于 Paper，GTNH 拒绝叠加。离线模式会允许未验证用户名加入，建议与白名单一并谨慎使用。

| 页面/操作 | 按键 | 行为 |
| --- | --- | --- |
| 全局 | `1`–`6`、`Tab` / `Shift+Tab` | 切换实例、控制台、玩家、备份、模组、联机页 |
| 全局 | `j` / `k`、`↑` / `↓`、鼠标滚轮/点击 | 移动选择、浏览日志或表格 |
| 全局 | `/`、`?`、`q` | 过滤实例（模组页 `/` 搜索 Modrinth）、帮助、退出 |
| 实例 | `n`、`s`、`x` | 新建向导、启动、停止 |
| 控制台 | `Enter` | 输入并发送单行服务端命令 |
| 玩家 | `Enter`、`a` | 为选中玩家预填 `op` 命令，或输入 `whitelist` / `op` / `kick` / `ban` 等命令 |
| 备份 | `b`、`r`、`v` | 立即备份；选择快照回滚，需再输入 `RESTORE`；设置保留数量 |
| 模组 | `/`、`Enter` / `i`、`u`、`d` | 搜索、安装所选项目、检查并更新、与 Prism 对比 |
| 联机 | `l` / `L`、`t`、`c` | 停止时切换局域网放行、显示 Tailscale 接入说明、输入备份分钟数（0 关闭） |

TUI 页面状态每隔数秒刷新。TPS/MSPT 在 Paper 上通过 `tps`、`mspt` 命令读取，GTNH/Forge 通过 `forge tps` 的 Overall 行读取；原版、Fabric 和未适配的 NeoForge 指标显示不可用。在线玩家来自服务端 `list` 命令，内存是 Java 进程的 RSS 近似值。控制台页显示日志尾部（最多 120 行、约 24 KB）；TUI 日志缓冲最多 500 行。

## 生命周期、存档与状态文件

系统默认实例根目录为 `~/.local/share/mcsrv/`，每个实例位于 `~/.local/share/mcsrv/<名字>/`。根目录和实例工作目录使用 `0700`；由程序创建的配置、日志、凭据和 lock 文件按 `0600`/umask `0077` 写入。主要路径包括：

| 路径 | 内容与归属 |
| --- | --- |
| `instance.json` | 实例类型、Minecraft 版本、Java 路径、启动参数、端口、备份和网络选项 |
| `import-report.txt` | Prism 模组导入时的检测依据、排除和待人工复核清单；仅 Prism 导入生成 |
| `installed.json` | 安装时解析出的 Minecraft、loader、loader 版本及可选整合包版本；创建完成后作为安装记录 |
| `server.properties`、`eula.txt` | 管家拥有端口、绑定、认证、白名单和 RCON 等所选键；保留整合包其余属性；明确接受 EULA |
| `rcon.secret` | 随机 RCON 密码；默认不启用 RCON，文件留在实例私有目录 |
| `mods/`、`config/`、loader 文件、插件与资源 | 服务端运行文件；不等同于存档备份 |
| `console.log`、`logs-manager/` | 当前控制台日志和按启动时间轮换的旧日志 |
| `backups/password`、`backups/repo/` | restic 本地仓库口令与增量备份数据 |
| `rollback-preserved/` | 每次成功回滚前移出的原有世界目录；不会自动删除 |
| `mods/.mcsrv-backups/` | 模组更新前保留的旧 JAR |

创建后，实例目录由程序及 Minecraft server 运行时共同拥有。启动会调用 `systemd-run --user` 创建 `mcsrv@<名字>.service` transient unit；不会 enable 或设置开机自启。停止通过控制台发送 `stop` 并等待进程退出；失败时有超时保护。该 transient unit 退出后由 systemd 收集。

启动前会尝试创建一次备份；若尚无世界则报告“首次启动无需备份”。运行期间默认每 30 分钟再做一次，`--backup-minutes 0` 关闭定时备份。备份只包含 `server.properties` 中 `level-name` 对应的世界目录及常规 Nether/End 目录，不包含 mods、config、loader、插件、白名单/OP 文件、日志或凭据。用户应另行保管这些文件。运行中备份发送 `save-off`、`save-all flush`（1.7.10 使用 `save-all`），完成后尝试恢复 `save-on`；若服务端未确认保存，操作报错并提示检查控制台。

restic 对仓库作内容去重；`keep_last` 默认 20，用于忘记较旧快照。程序不自动运行 restic `prune`，所以忘记快照后仓库磁盘块不会自动回收。不会自动删除世界。回滚要求服务器停止及明确确认快照 ID；回滚前再备份当前世界，并把原世界目录保留到 `rollback-preserved/`。回滚功能仅替换允许的主世界/维度目录，快照中出现特殊文件或与当前 `level-name` 不一致时会拒绝恢复。

## 局域网、防火墙与外网联机

默认局域网共享关闭。使用 `config <名字> --lan` 后，启动时申请临时放行 TCP 25565–25575 中实例所用端口，关服时撤销；应用每 30 秒续租，NixOS host unit 和 nftables set 都以 90 秒为上限。系统侧 `mcsrv-firewall@<端口>.service` 只放行游戏端口 TCP；RCON 端口不对外开放。Polkit 仅允许 `mcsrv-firewall` 组成员对允许范围内模板单元执行 `start`、`stop`、`restart`。不支持的 NixOS 防火墙后端会 fail closed。规则开放时该端口对所有可路由来源地址可达，可能包括 WAN 和 VPN；不要无意配置路由器端口转发。停止规则后，已建立连接可能仍由 conntrack 保留到连接跟踪状态超时。

外网联机推荐 Tailscale 私有 tailnet：双方设备加入受控 tailnet 后使用 100.x 地址和游戏端口，无需路由器转发。NixOS 的 Tailscale daemon 必须由系统配置启用，并完成设备登录/组织策略授权；`t` 只显示接入说明；执行 `network <名字> --connect` 才显式调用 `tailscale up`，可能改变现有 daemon 的连接状态或要求 operator 批准。管家运行时不启动或关闭 `tailscaled`；宿主可显式启用下述可选集成，不读取或保存 Tailscale 凭据；凭据留给 daemon。首次使用前先确认本机 operator 授权和 tailnet 访问策略。

其他选项：

- **playit.gg**：按其官方 Linux agent 流程安装并登录 agent，在 agent 控制台为 Minecraft Java TCP 服务创建 tunnel，目标填本机地址与端口。确认外部提供的域名/端口及账号访问策略；管家不安装 agent 或存储账号令牌。
- **自建 frp**：在具备公网地址的 VPS 部署 `frps`，本机部署 `frpc` 将 Minecraft TCP 端口映射至 VPS。`frps`/`frpc` 配置与 token 由用户在 Nix/sops 运行时管理，不得写入 Nix 字符串、实例日志或本仓库明文。
- **ZeroTier**：双方安装并启动各自系统服务，手动加入同一个受控网络并完成网络管理员授权，再用虚拟地址连接。需要自行评估第三方控制面和网段路由策略。

Clash/Mihomo TUN 的本地或 overlay 流量需确保走 `DIRECT`；建议至少对 `127.0.0.0/8`、RFC1918 私网、Tailscale `100.64.0.0/10` 和 ULA `fd7a:115c:a1e0::/48` 配置直连规则。`network` 页面显示系统接口报告的全局地址；若 Tailscale 地址已由系统呈现，也会出现在其中。Mihomo 规则结构示意如下，合并前按现有规则顺序核对：

```yaml
rules:
  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - IP-CIDR,100.64.0.0/10,DIRECT,no-resolve
  - IP-CIDR6,fd7a:115c:a1e0::/48,DIRECT,no-resolve
```

本功能不改写 Clash/Verge 配置。若要按进程直连，进程规则可能同时覆盖 Prism、游戏和其他 Java 程序；不要把它当成只匹配某个服务器的精确开关。TUN 入站、同机本地回连及实际路由需结合本机配置验证，直连规则本身不证明玩家已可连入。

## 设计依据和当前限制

实现参考了 [PaperMC Downloads Service](https://docs.papermc.io/misc/downloads-service/) 的稳定 build 与 checksum 接口、[Fabric Server](https://wiki.fabricmc.net/install) 的可执行服务端 JAR 和 loader API、[Modrinth API](https://docs.modrinth.com/api/) 的项目环境与版本依赖字段，以及 [GTNewHorizons/lwjgl3ify](https://github.com/GTNewHorizons/lwjgl3ify) 的官方 1.7.10 server 命令。GTNH 包下载位置以其[官方下载页](https://www.gtnewhorizons.com/downloads/)和[版本历史](https://www.gtnewhorizons.com/version-history/)为准。`itzg/docker-minecraft-server` 的 [GTNH Compose 示例](https://github.com/itzg/docker-minecraft-server/blob/master/examples/gtnh/docker-compose.yaml)作为另一种容器化 server-pack 运行方案参考；此功能不依赖 Docker，也不将存档迁入容器卷。没有把其他名称相近但未核实适用性的 `mc-server-wrapper` 项目当作实现依据。

运行状态会通过有大小/时间上限的 status 协议核实；GTNH 在 Done 后仍可能由 Hodgepodge 拒绝连接，此时保持“启动中”。Paper 与 GTNH/Forge 的 TPS/MSPT 通过控制台命令读取，其余 loader 未适配对应命令时显示不可用。自动备份依赖本机 `restic`，安装包会将其加入用户 profile。创建需要网络下载和匹配的 Temurin JDK。GTNH 初次包下载、首次启动/接受迁移提示及到 `Done` 的完整验证状态由执行报告另行记录；模块构建或 API HTTP 200 均不等同于服务器已经成功开服。

## 开发

```sh
cd packages/mcsrv-mayon
cargo test --locked
cargo clippy --all-targets --locked -- -D warnings
cargo fmt --all --check
cargo build --release --locked
```

Cargo workspace 独立并提交 `Cargo.lock`。本仓库的 Nix package factory 与 gaming aspect 负责构建和安装；桌面快捷键、窗口规则由桌面 feature 拥有，不在本 README 管理范围内。

可选 Tailscale 宿主接线（由主代理在适当宿主模块中明确选择；默认关闭）：

```nix
services.mcsrv-mayon.tailscale = {
  enable = true;
  operator = "mayon";
};
```

该设置复用锁定 NixOS `services.tailscale` 和 `extraSetFlags`，允许指定 operator 显式管理 daemon。设备认证状态留在 tailscaled 的运行时 state；没有在 Nix 中声明密钥。若另用 `services.tailscale.authKeyFile` 自动加入，必须指向 sops/权限受限的运行时文件，不向本包提供 token。

整合包的 `server.properties` 中未由管家管理的设置（例如 `allow-flight`、`level-type`）会保留。mrpack 按标准下载服务端文件，再依次应用 `overrides/`、`server-overrides/`，不应用 `client-overrides/`。两个覆盖层允许服务端覆盖通用配置，均拒绝路径越界和符号链接。

模组搜索、安装/更新与 Prism 差异的完整结果显示在可滚动弹窗，使用 `j/k` 或滚轮移动、`Esc` / `q` / `?` 关闭。实例选择与页内玩家/快照选择独立；后台操作期间不可切换实例，避免向错误实例发出管理命令。
