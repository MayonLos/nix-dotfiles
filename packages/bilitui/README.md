# bilitui-mayon

独立 Rust workspace，终端浏览 B 站，mpv 播放，FFmpeg 合并下载。公开 Nix 包工厂为
`default.nix`（`{ pkgs }`），由 `nix/pkgs.nix` 发布 `pkgs.bilitui`，Media 安装。
复用 `../mayon-tui/crates/ui` 的组件和公开 One Dark palette，不修改共享 UI。
无后台服务；播放器和串行下载 worker 随程序按需启动，退出时取消自己的任务。

## 页面和操作

`1` 推荐、`2` 热门、`3` 排行、`4` 关注视频动态、`5` 搜索、`6` 收藏夹、
`7` 稍后再看、`8` 历史、`9` 下载队列。游客可看公开页面；需要账号的页面会提示登录。
`Enter` 取视频详情；`u` 打开 UP 投稿；搜索页 `Tab` 在视频与 UP 搜索之间切换。
`s` 输入关键词，输入框 `↑↓` 选本地历史，`Tab` 按需取建议；`/` 过滤当前列表。
`j/k`、方向键、滚轮和点击选择，`n/N` 翻页，`R` 刷新，`Esc` 返回，`?` 帮助，`q` 退出。

详情显示标题、UP、播放/弹幕/点赞数、简介、分 P、合集和相关推荐。
`[/]` 换分 P，`Q` 选择下一次播放/下载的清晰度（默认当前权限下最高可用）。
`p` 使用 mpv 播放 DASH 分离音视频；HTTP Referer、UA 和当前 cookie 一起传递。
播放器使用已有 mpv 配置并单独传 `hwdec=auto-safe`，不改声明式 mpv 配置。
`d` 切换下次播放的弹幕，mpv 内 `j` 切换字幕轨；`h` 切换下次播放的历史回报。
登录且开启回报时，从私有 mpv IPC 读取实际播放位置，每 15 秒 heartbeat；失败不阻止播放。

`l` 点赞、`c` 投 1 枚硬币（单独确认）、`f` 选择收藏夹后收藏、`w` 加稍后再看。
这些操作需要登录，按键不会在未登录时发送 POST。`y` 通过 OSC52 复制公开视频链接。
`v` 下载当前分 P 视频、`a` 下载音频、`A` 下载当前视频全部分 P、`G` 下载视频详情提供的合集。
队列串行运行，最多一次加入 500 集；不覆盖已有文件，不自动重试，失败需手动重新加入。播放或下载进行时暂不允许切换登录账号，避免旧账号任务与新队列交叉。
下载先流式写本地暂存文件，再用 FFmpeg copy 合并为 MKV / M4A；退出取消任务并清理本次暂存文件。
网络中断、地区/会员限制会中文提示。旧式多段 durl 不支持，避免仅播放第一段。

Kitty 在至少 110 列时通过内联图形协议显示当前选择的封面，不支持的终端与窄窗使用文字。
90 列保留全部数字切页；详情在窄窗单独显示，`Esc` 回到列表。

## 登录、配置和数据归属

`L` 获取二维码，以 Unicode 半块显示；每 3 秒轮询一次，`Esc` 取消，过期停止轮询。
二维码密钥只在内存中。cookie 不写日志，不放进进程参数或 Nix store；登录 cookie 保存到
`$XDG_DATA_HOME/bilitui/cookie`，默认 `~/.local/share/bilitui/cookie`，权限 **0600**、目录 **0700**。
播放器的 HTTP cookie 位于 `$XDG_CACHE_HOME/bilitui/player-<pid>-<seq>/http.conf`，权限 0600；
同目录保存 ASS 和 Unix IPC socket（目录0700），播放结束清理。异常断电可能遗留私有目录，
可在确认 bilitui/mpv 没有运行后手动清理这些 `player-*` 目录。

配置由用户拥有，程序只读取，不由 Nix/Home Manager 覆盖：
`$XDG_CONFIG_HOME/bilitui/config.toml`，默认 `~/.config/bilitui/config.toml`：

```toml
report_history = true
# false 会禁止已登录播放的历史回报；访客始终不回报。
danmaku = true
# download_dir 可省略，默认根据 HOME 展开 ~/Videos/Bilibili，不能写字面的 ~。
# download_dir = "/home/your-user/Videos/Bilibili"

[danmaku_options]
font_size = 36
density = 12
opacity = 0.85
blocked = ["屏蔽词示例"]
```

`d/h` 只更改当前进程，下次启动读取配置。搜索历史由程序写到
`$XDG_DATA_HOME/bilitui/search.json`（0600，最近 40 项）；下载队列仅内存，不跨启动恢复。
下载目录默认 `~/Videos/Bilibili/`，属于用户视频数据，移除包/Media 不会清理 cookie、历史、
缓存、配置或下载文件。没有迁移、覆盖其他播放器设置或应用登录状态。

## 实现依据与取舍

- API 和 WBI 参数参照 [bilibili-API-collect 维护镜像](https://github.com/bilibili-plugins/bilibili-api-collect)，
  [WBI 文档镜像](https://sessionhu.github.io/bilibili-API-collect/docs/misc/sign/wbi.html)、
  [播放流文档](https://sessionhu.github.io/bilibili-API-collect/docs/video/videostream_url.html)。
  对 -352/-412、HTTP412/429 共享 60 秒冷却；用户手动重试，不自动规避风控或登录限制。
- [BBDown](https://github.com/nilaoda/BBDown) 提供 DASH 分离下载/本地 FFmpeg 合并的工作流参考；
  [biliup](https://github.com/biliup/biliup) 提供扫码/多 P 客户端交互背景。
  [bilibili-tui](https://github.com/MareDevi/bilibili-tui) 提供终端浏览与外部播放器的交互参考。
  不调用这些程序、不复用它们的登录状态。
- XML→ASS 自行实现，布局参考 [biliass / Danmaku2ASS](https://github.com/yutto-dev/biliass)
  与 [DanmakuFactory](https://github.com/hihkm/DanmakuFactory) 的公开布局与密度规则。
  固定1920×1080，滚动10秒、固定4秒，滚动/顶部/底部分配独立屏幕区域，满车道丢弃。
  宽度按 Unicode cell 估算而非字体实际测量；不支持高级弹幕/脚本弹幕 mode7/8/9、protobuf。
  XML 上限10MiB/20,000条；仅渲染普通 mode1–5，不执行弹幕中的 ASS 指令。

## 验证

```sh
CARGO_BUILD_JOBS=6 cargo test --locked
CARGO_BUILD_JOBS=6 cargo clippy --locked --all-targets -- -D warnings
cargo fmt --all -- --check
```

`checks.bilitui` 构建并运行固定 fixture 单测、clippy 和 rustfmt。不联网、不启动 mpv、不登录账号。
`bilitui-mayon --demo` 是完全离线视觉样例；`--fixture PATH --demo-cover PATH` 可显示匿名公开录制数据。
`--convert-danmaku XML ASS` 可离线转换普通 XML 弹幕；`--probe-playurl DIR` 只重验已有公开录制目录的详情对应的低清取流。
`--probe-public DIR` 专门使用空 cookie、少量间隔请求 buvid、热门、nav/WBI、搜索、详情、低清 playurl，
记录公开 JSON 和不含 URL 的播放摘要，再以 `mpv --no-config --vo=null --ao=null --frames=24` 验证拉流。
它从不读取 cookie/配置、不发二维码请求、不登录、不发 POST；不会录制 cookie、完整 CDN 签名 URL。
部分匿名接口可能被风控；失败必须保留为限制，不能视为通过。

登录、收藏/投币等写入、真实账号历史回报、下载全集及硬件解码必须由主代理获得授权后实机验证；
单测、隔离截图和 null 输出拉流不代表这些功能已实机验收。

本轮录制的 `fixtures/{popular,search,view}-public.json` 来自 2026-10-30 的匿名公开请求，
仅保留 parser 所需的公开数据，不包含登录 cookie 或签名 CDN 流 URL。网络探测实际报告和
隔离视觉证据位于执行 brief 指定的 `.work/r50/bili/`，不进包源码。
