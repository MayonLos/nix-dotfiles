# 系统与编辑器优化、应用记录

日期：2026-10-18。新 goal 从干净提交 `0ad542a` 开始。用户已自行切换上一轮配置，
本轮明确授权主代理继续实现、构建并自行 nr，最终由用户验收。此前实施记录的“不应用”
只描述此前任务边界，不覆盖本次新授权。

实际 Astra 根据两张 Neovim 截图负责视觉设计；Luna 处理通知、项目入口与源码核验，
主代理负责桌面/终端集成、长任务操作、运行交接及提交，跨模块另做独立复核。
允许按效果选择插件或原生实现；不为更换技术丢失原有功能或文件安全保障。

保护另一个 mod 任务，不重启机器、不注销 Mango、不杀业务或编辑器进程，不升级无关输入，
不清理数据、历史、模型、凭据、容器卷或 VM。系统切换不等于所有 GUI 已验收。

## 起始运行状态

实际系统指向上一轮已构建的 `1f6ilz…` toplevel；Mango target、输入法和剪贴板桥正常。
新 Noctalia unit 因活跃旧 shell writer 被 guard 拒绝，达到 start-limit；并非系统构建失败。
已核实 executable/UID/start-time，并绑定 Linux pidfd 仅向唯一旧 shell 发 SIGTERM，等其退出
和 writer scan 为空后 reset-failed/start 新 unit。Noctalia 与 Mango 均 active，没有会话或
进程组信号。writer guard 只修正误导的“必须注销”提示，保护逻辑没有放宽。

## 实施状态

### 已实现

- Neovim：目录树单行、图标/侧栏层次、短根标题与完整路径查看；标签点击选择正文而非覆盖
  树/终端；默认正文不软折行，手动 wrap 有续行标记；状态栏补文件格式和 LSP 进度。
  常规 WorkDoneProgress 按 client/token 聚合到状态栏和单条静默历史，不再堆叠 toast；
  普通 INFO、WARN/ERROR 和诊断路径保留。共享 reducedMotion 也控制原生滚动。
- 桌面：铃铛/DND 与 caffeine 状态可见，`Super+Alt+D/I` 提供原生入口；未新增轮询 daemon。
- 终端：Kitty 标签消费相同 palette，安静视觉铃声随减少动画偏好关闭，有前台任务时关闭
  窗口会确认。保留字体、正文不透明度、图像与 tmux 能力，不强制重载现有终端。
- 项目：真实 binding 只注册 dotfiles 和 NewNuclear；入口可选择终端、CLI editor 或文件。
  目录与 argv 按数据处理，无目录不创建/不回退，无额外参数的 editor 打开 `.`。
  `.envrc` 必须通过 direnv 信任，不自动 allow，不启动构建或回放历史。
- 长任务：`workspace-task -- 命令 参数` 和“长任务终端”持有命令生命周期的 sleep inhibitor；
  自动锁屏仍保留。Noctalia caffeine 是另一个 idle inhibitor，两者不混为一谈，也不自动
  套在正在运行的任务上，不声称抵抗强制休眠或断电。

### 参考与取舍

实际 Astra 查阅 [LazyVim UI](https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/plugins/ui.lua)、
[mini.files](https://github.com/nvim-mini/mini.files/blob/main/doc/mini-files.txt)、
[Neovim options](https://neovim.io/doc/user/options/)；主代理核对
[Snacks](https://github.com/folke/snacks.nvim)、[end-4](https://github.com/end-4/dots-hyprland)、
[Kitty 配置](https://sw.kovidgoyal.net/kitty/conf/) 与
[systemd inhibitor](https://www.freedesktop.org/software/systemd/man/latest/systemd-inhibit.html)。
本次判断原生组件已具备所需能力，直接完善更合适，没有为外观新增运行插件或升级输入。
Noctalia IPC、通知历史、caffeine、优雅退出和应用 cgroup 语义均再对当前锁定源码核验。

### 检查与复核

全部 16 项根 checks 已通过（包括新 project-workbench）；Mango/Noctalia 默认及减少动画
分支实际 parser、Kitty parser/tmux、完整 Neovim、协议/功能/无头组合均通过。新增树/标签
安全和减少动画回归、进度聚合/静默历史测试，项目检查仅在临时目录运行。
跨账号/host 项目选择和撤销、数据不生成应用、相对目录拒绝由生产组合覆盖。

真实 direnv 另在隔离 HOME/XDG 临时项目验证：未信任时拒绝，显式 allow 后 exec 成功；
未修改用户实际项目或 trust 数据。输入锁相对基线不变，无无关输入升级。

独立 reviewer 找到并修复项目检查的 Nix store 源码相邻布局问题；实际构建还修正了
unittest 绝对路径入口与 sandbox spy 的解释器路径，未弱化断言。生产启动检查中的
TreesitterContext 背景预期随 Astra 深色层次设计更新；Kitty 的 close 选项按锁定 tuple 类型验证。
追加复核未发现剩余阻塞缺陷。尚未取得的 GUI/设备/性能证据不写成完成。

实现提交 `1c46de6`（编辑器）与 `cb9fa57`（项目/终端/桌面操作）；最后 unused 参数格式
修正与本文一起提交。构建命令均使用 `--no-write-lock-file --max-jobs 1 --cores 2` 串行执行。
完整主机构建与授权应用均已完成，结果见下节。

## 应用与验收

使用 `sudo nixos-rebuild switch --flake /home/mayon/nix-dotfiles#nixos-btw --no-write-lock-file
--max-jobs 1 --cores 2` 成功应用。`/run/current-system` 与构建的
`/nix/store/k3k3m81j2cc4f67a5yylpwd7sip8j3d1-nixos-system-nixos-btw-26.05.20261012.7993f34`
一致。应用前比对显示管理器/greetd、NetworkManager 和 Nix daemon unit 内容未变化。
实际 switch 重启 Home Manager、正常 reactivation；没有注销 Mango 或重启机器。

应用后核对：Noctalia/Fcitx5/clipboard bridge active/running，Mango target active，
Home Manager unit Result=success；`workspace-project list` 给出两个预期项目；三个 desktop
入口和已安装 Mango 配置/帮助均存在；`workspace-task -- true` 返回成功并释放抑制，
勿扰 status 查询返回 off。没有为测试切换用户 caffeine/DND 状态或启动真实项目。

初次使用旧 `mmsg -d` 语法被当前 CLI 拒绝；查锁定源码/实际 help 后使用
`mmsg dispatch reload_config` 返回 `success:true`，已热加载新键位，无需重启 compositor。
应用前记录的两个 Codex 与五个 Java 进程 PID/start-time 均保持，未向它们发信号；
进程检查未收集命令参数或环境。Noctalia 公开设置备份目录仍为 `0700`。

当前打开的 Neovim/Kitty 不强制重启，新开实例读取新配置；
用户随后验收字体、状态栏密度、真实 jdtls、多屏、树点击、弹窗、动画与终端关闭确认。
外屏/设备/游戏/休眠和性能比较未执行，不声称更快或更省电。运行日志仅记录对应结果，
不输出凭据、剪贴板、完整进程命令或环境。

本轮检查与应用日志为 `/tmp/codex-system-polish-{eval,checks,final-checks,toplevel,switch}.log`。
16 项根检查、真实主机 toplevel 和应用 smoke checks 属于各自证据层级，不等于视觉验收。
