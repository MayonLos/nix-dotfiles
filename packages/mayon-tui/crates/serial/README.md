# Serial 页

面向 STM32 开发的 Linux 串口工作台，延续 mayon-ui 的 One Dark、中文提示与 Kitty 操作方式。无参数先选端口，启动时不自动打开真实设备。

```sh
mayon-tools serial
mayon-tools serial list
mayon-tools serial /dev/ttyACM0 -b 115200
mayon-tools serial /dev/serial/by-id/usb-… --baud 921600
```

## 设计依据

2026-10-30 查询上游文档后确定范围：

- [tio](https://github.com/tio/tio) 已有自动重连、设备列表、HEX、时间戳、日志、控制线切换/脉冲与基本行输入。因此不把这些当作超越 tio 的理由，继续安装 tio 用于轻量终端、脚本和传输协议。
- [Serial Studio Quick Plot](https://github.com/Serial-Studio/Serial-Studio/blob/master/doc/help/Getting-Started.md) 展示了 CSV 即时绘图的价值。本工具取其快速看遥测的工作流，提供无需项目定义的 key=value / 数值 CSV braille 波形，最多16通道，每通道1024点。
- [picocom](https://github.com/npat-efault/picocom) 定位为精简终端；本工具增加可搜索/过滤回滚、暂停跟随、命令收藏、GBK 与可见的烧录交接状态。
- [probe-rs cargo-embed](https://probe.rs/docs/tools/cargo-embed/) 提供 RTT 与 GDB；RTT 是调试探针内存通道，不等同 UART。本工具只管理 UART 和外部烧录命令，不实现 RTT，也不猜测芯片型号。

适合“串口日志 + 数值变化 + 常用命令 + 烧录后继续看输出”同时出现的调试过程。没有复制 tio 的 Lua、X/Y-Modem 或 RS-485 功能。

## 功能与边界

端口页只读 sysfs，显示 ttyACM/ttyUSB 的 VID:PID、产品、序列号，识别 ST-Link VCP、STM32 VCP、CH340/CH341、CP210x 与 FTDI。列表750ms刷新；设备断开后界面保留，400ms间隔寻找同一 VID:PID、序列号和 USB 接口，tty 编号改变不影响身份。没有序列号时限定相同物理 USB 位置与接口；相同序列号出现多个候选时拒绝自动选第一个。明确的手动路径按路径重开；应优先选择列表中的 USB 设备或 `/dev/serial/by-id/`。

参数包含常用/任意正整数波特率（界面上限12M，实际受驱动支持）、5–8数据位、none/even/odd校验、1/2停止位、none/hardware/software流控。设置按设备身份保存。DTR/RTS可切换或反转100ms后恢复；驱动不支持时报告错误。硬件流控下 RTS 可能由驱动接管，电平、复位极性、真实波特率/帧格式均需接板验证。

TEXT 按 CR/LF/CRLF 成行并完整解码跨读取边界的 UTF-8/GBK；未结束行实时预览。ANSI SGR 的颜色/强调转成 ratatui spans，OSC、光标控制等不会下传终端。监视页 `g` 可重新解码已有文本缓冲。HEX/MIX 使用独立16字节行的原始接收缓冲，保留换行、NUL和非文本字节，长包可逐行回滚。MIX 右侧为可打印 ASCII；其他字节显示 `.`。时间戳支持本地绝对时刻、进程启动后相对秒数、关闭；接收时间以主机收到数据为准。

文本与原始接收缓冲各默认10万行，各有32MiB内容上限（不含容器元数据），满后淘汰最旧行并计数。暂停只冻结视口，不停止接收/日志；暂停位置被淘汰会提示。TEXT单行最多16KiB，达到上限会在完成行及文本日志中标记，超出部分仍进入HEX缓冲与开启后的原始日志。搜索/过滤使用共享 Matcher：Unicode 不区分大小写、中文原文/全拼/首字母、多词 AND；仅短文本允许子序列。HEX页可搜索十六进制；`n` / `N` 向后/向前循环定位并显示“第 x/共 y 个”。匹配预处理使用有16MiB索引预算的共享缓存，空查询不建立索引；重新解码按新文本查询。自定义高亮词用逗号分隔，默认 ERROR/WARN/FAULT。吞吐量每秒更新。

发送支持输入历史、CR/LF/CRLF/无尾、HEX（不追加行尾）、命令收藏、原字节文件（单次≤1MiB）、定时重复最近输入的成功排队负载（≥20ms，断线/烧录停止，不在重连后自动恢复）。发送按小块交错读写，不调用不可取消的 tcdrain；忙时拒绝新负载并报告。TX统计代表成功写入驱动的字节数，不代表 MCU 已确认接收。发送记录标记排队意图；设备端协议确认仍由固件负责。

日志 `l` 开始/结束：同名 `.bin` 为开启期间的精确 RX 字节流，`.log` 为带 RFC3339 时间戳的解码行与连接/发送事件，正常退出也落盘未换行尾部。`c` 为下次日志启用长表 CSV：`timestamp,seconds,channel,value`，不固定通道集合，字段使用 CSV 引号转义。开启前的数据不追补，原始 `.bin` 不混入 TX。暂停不影响日志；长时间采集注意磁盘容量。

烧录页检测 PATH 中 probe-rs/openocd/st-flash，只提示可用工具，初始命令留空。`o` 填写完整 shell 命令（含明确芯片/工程参数），`O` 设置工作目录；空目录表示启动目录。F5 快照命令和目录、停止定时发送、发带请求编号的 Release；仅收到对应 ACK（fd已关闭、自动重连已禁用）后启动私有进程组，捕获 stdout/stderr，结束后按原设备身份重连。烧录中参数修改保存到重连时应用，不能提早打开串口。Esc 可取消等待/运行中的烧录，q退出会终止子进程组。输出保留最近2000行且总计不超过1MiB，单行16KiB；输出队列过载时最终状态报告丢弃行数。只运行用户明确配置的命令；重连不代表烧录成功，退出状态可在输出中检查。

## 键位

| 键 | 操作 |
|---|---|
| 1–5 | 监视 / 端口 / 参数 / 命令 / 烧录 |
| ? / q / Ctrl+C | 帮助 / 退出 / 退出 |
| ↑↓、j/k、PgUp/PgDn、g/G、Home/End、鼠标 | 选择端口、参数或收藏；端口页 Enter 连接 |
| i / Enter | 输入发送（↑↓历史，支持左右/Home/End、Ctrl+A/E/U/K/W、Alt+Backspace；Esc取消） |
| x / e / F / t | 发送TEXT/HEX、行尾、原字节文件、重复毫秒数（0停止） |
| / / f | 增量过滤接收记录；Enter 保留，输入中 Esc 恢复打开前过滤，列表 Esc 清除 |
| Ctrl+f / n / N / h | 搜索、下一个、上一个、高亮词（空搜索清除） |
| Space / p / PgUp / PgDn / End | 暂停、回滚、恢复跟随；滚轮可用 |
| v / T / g / w | 接收TEXT/HEX/MIX、时间戳、UTF-8/GBK、波形 |
| l / c | 日志开关、下次日志的CSV开关 |
| b / B / s | 常用波特率、自定义波特率、完整参数 |
| d / r / D / R | DTR、RTS切换，DTR、RTS 100ms反转脉冲 |
| a | 添加收藏：`名称=命令`；命令页Enter只载入，不立即发送 |
| o / O / F5 / Esc | 烧录命令、目录、执行、取消 |
| u | 主动断开（禁自动重连；端口页Enter重新连接） |

## 配置与状态归属

本程序是唯一 writer；Home Manager 只安装包，不管理/覆盖配置。

- `$XDG_CONFIG_HOME/serial-mayon/config.json`，默认 `~/.config/serial-mayon/config.json`：设备参数/编码/行尾/烧录命令和目录，收藏、高亮词、回滚行数。
- `$XDG_DATA_HOME/serial-mayon/history.json`，默认 `~/.local/share/serial-mayon/history.json`：最近1000条输入历史。
- `$XDG_DATA_HOME/serial-mayon/logs/YYYYMMDD-HHMMSS-纳秒.{log,bin,csv}`：显式开启的日志。

应用目录0700，新建配置、历史、日志0600；配置/历史使用同目录原子替换。配置损坏时报错，不覆盖坏文件。配置示例可先启动退出一次生成，再在程序退出后编辑；`highlights`是字符串列表，`scrollback`默认100000（限制100–1000000）。烧录命令按 shell 语法执行，不提供需要猜测的模板，也不需要 sudo。移除 embedded feature 或包只移除命令，保留配置、日志、固件和所有工程数据。

输入框使用单行 TextInput 与终端真实光标；bracketed paste 只插入当前输入框，多行转空格并过滤控制字符，无输入框时忽略。过滤持续显示匹配数/总数，无结果提示 Esc 清除。

由 `packages/mayon-tui/default.nix` 的 `tools` 输出提供，与工具箱共用 workspace/Cargo.lock，无独立可执行程序。
切换工具页或失去终端焦点时关闭串口、停止定时发送与烧录任务；保留接收缓冲、过滤、选择和内部子页。返回后按已有连接意图重连。顶层工具页使用 `[ / ]` 切换。

## 验证

```sh
CARGO_BUILD_JOBS=6 cargo test --manifest-path packages/mayon-tui/Cargo.toml -p serial-mayon
CARGO_BUILD_JOBS=6 cargo clippy --manifest-path packages/mayon-tui/Cargo.toml -p serial-mayon --all-targets -- -D warnings
cargo fmt --manifest-path packages/mayon-tui/Cargo.toml -p serial-mayon --check
```

工具箱构建包含本库的单元与PTY测试。`tests/pty.rs` 使用 openpty 与临时 symlink，验证二进制收发、跨片编码、替换PTY断线重连、Release ACK及发送背压时及时关闭；从不打开真实串口。`flash_flow.rs` 在替代worker队列上注入过期/匹配ACK并运行安全的printf命令，验证延迟执行、命令快照、取消、期间不能重新打开及完成重连。`app_flow.rs` 覆盖搜索、日志、暂停、CSV、发送边界等。

`python3 scripts/visual-smoke.py <截图目录> [binary]`（仓库根目录调用时使用完整脚本路径）使用 `env -i`、临时HOME/XDG/runtime、私有D-Bus与headless sway（2560×1600、scale1.5）、真实Kitty与PTY模拟器。依赖 sway/kitty/grim/ImageMagick 在PATH。会生成monitor/搜索/参数/收藏/HEX/断开重连/模拟烧录/90列/帮助截图、gallery.html与overview.png。此脚本不连接用户Wayland会话，结束时清理自己启动的进程。截图和PTY不能证明真实USB枚举、驱动帧格式、电平复位、真实烧录或板端持续吞吐量。
