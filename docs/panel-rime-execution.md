# 面板、场景与 Rime 收尾记录

日期：2026-10-18。从干净提交 `1efaab2` 开始，承接用户对面板收纳、统一场景及专业词库、
候选排序、纠错的选择。用户随后要求整理文档并 push；这次明确推送授权覆盖此前积累的本地
重构与优化提交，不改写历史、不强推。系统应用沿用此前自主 nr 授权。

实际 Astra 负责 Noctalia/greeter 与视觉文档，Luna 负责输入法的局部实现；主代理负责集成、
隔离验证、构建、应用与提交。保护另一项 mod 工作，不注销、不重启机器、不停止业务进程。
不升级输入，不清理历史、个人词库、模型、容器卷或 VM。

## 本轮交付

- 面板：`dev` 和 `panels` 低频组悬停展开、离开收起。布局/Quill 作为常显锚点，展开后
  保留 Portctl/Docker；resize/keymode 独立显示。键盘仍可通过启动器 `/pan` 搜索面板。
- 场景：启动器/控制中心统一为居中浮层、720 宽，协调圆角、阴影、输入框和内部卡片。
  锁屏跟随当前壁纸，greeter 沿用公开 009 资源；不添加额外 shell 或壁纸 daemon。
- Rime：补充 21 个锁定上游缺失的编程/Nix、嵌入式、核工程和 Minecraft 术语，权重 100。
  保留用户学习、组句、五候选、英文/混输、现有短词冲突排序和正确读音提示。
  未广泛开启模糊音；上游已有错拼派生，本轮用真实引擎验证 `zhognzi` →“中子”。
  具体维护和数据边界见[词库说明](../aspects/interactive-session/rime/README.md)。

输入方式仍是雾凇全拼，无需更换 schema。例如 `shengmingshipeizhi` →“声明式配置”、
`kefuxiangoujian` →“可复现构建”、`zhongzishuyun` →“中子输运”、
`hongshizhongjiqi` →“红石中继器”。这些是候选可达示例，不承诺固定第一名。

## 检查与复核

新增根 `rime-technical-runtime` 检查在临时 HOME/XDG/user-data 目录运行锁定 librime 1.16.1。
实际编译生产配置，验证普通中文、新专业词、错拼和英文共 8 个输入样例可在前四页找到预期
候选；同时核对学习选项、纠错注释配置和实际打开的数据库名，未读取个人学习词条。
这不证明学习持久化、旧词连续性或个人候选排名，日常输入仍待用户验收。

独立复核发现原方案错误假设词表递归导入。先用隔离检查复现 `nihao` →“你好”失败，再将
锁定上游五张中文表显式按原顺序列入复合词表，保留主表正文与专业补充；修复后 8 个样例
全部通过。以后升级上游应比对 import 列表，不能只添加一层词典引用。
Noctalia/Mango parser、writer guard 和 treefmt 专项检查通过，包含新 Rime 检查的全部 17 项根
checks 已通过，完整主机 toplevel 已构建并成功 nr。输入锁相对基线未变化。技术依据以锁定源码为准，并参考
[Rime 官方定制指南](https://github.com/rime/home/wiki/CustomizationGuide) 与
[librime 1.16.1 API](https://github.com/rime/librime/blob/1.16.1/src/rime_api.h)。

## 实际应用

使用带 `--no-write-lock-file --max-jobs 1 --cores 2` 的 `nixos-rebuild switch` 成功应用。
应用前显示管理器/greetd、NetworkManager 与 nix-daemon 的 unit 内容均未变化；没有注销、
重启 Mango 或机器。Noctalia、Fcitx5、剪贴板桥及 Mango target active，HM Result=success。
应用前记录的 8 个业务/会话进程 PID/start-time 均保留，未读取命令参数或完整环境。

通过 `noctalia msg wallpaper-set` 显式选择声明中的 009 store 资源，`wallpaper-get eDP-1`
确认生效；没有删除壁纸 state。捕获当前内屏、启动器和控制中心作初步构图核对，截图只保留
在 `/tmp/codex-panel-rime-{desktop,launcher,control-center}.png`，不提交包含工作窗口的截图。
实际 Astra 再看截图发现 glass 下终端文字穿透过重，改用官方 `soft`（浮层 0.80、卡片 0.88），
保留圆角、阴影和动效；该修正提交为 `cbaf9ed`。最终构建与应用结果以下方收尾核验为准。

Rime 一般 reload 与 full deploy 返回后，旧生成 schema 仍未更新；观察到缓存中的依赖时间戳
均为 0，store 输入时间戳固定，不能据命令成功判断配置已更新。仅把 `build/rime_ice.schema.yaml` 移入
`~/.local/state/nix-dotfiles/rime-deploy/20261018-161035/`（目录 0700、备份 0600），再通过
Fcitx5 官方配置接口触发其内部部署：

```sh
busctl --user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 \
  SetConfig sv fcitx://config/addon/rime/deploy a{sv} 0
```

部署后重新生成的公开 schema 确认 `dictionary = rime_ice_technical`、`user_dict = rime_ice`，
学习/组句开启；实际 Fcitx5 文件句柄同时指向新 compiled table 和原 `rime_ice.userdb/LOCK`。
没有产生 `rime_ice_technical.userdb`，没有外部 deployer 并发打开真实库，也未读取学习词条。
后续修改 Rime 配置应重新核对已部署 schema，不能仅凭 nr/DBus 返回成功；遇相同缓存问题，
先保留该公开生成文件的可回退副本，再让 Fcitx5 自行部署，不删除整个 build/用户目录。

构建/检查/应用日志保留为 `/tmp/codex-panel-rime-{checks,flake,toplevel,switch}.log`；
错误导入的负例日志为 `/tmp/codex-rime-negative.log`。最终 GUI 与输入习惯验收仍由用户完成。

## 收尾核验

`soft` 修正后重新通过全部根 checks 和完整主机构建，再次 nr 成功。当前运行系统与最终构建
一致：`/nix/store/yfp33chaag8955n5rlfwk2jq5850anf1-nixos-system-nixos-btw-26.05.20261012.7993f34`。
日志为 `/tmp/codex-panel-rime-final-{checks,toplevel,switch}.log`。
再次核对服务、HM Result、009 壁纸、新 Rime schema 与原数据库名称，以及 8/8 个进程身份。
内屏启动器再次截屏核对为 `soft`，保留 `/tmp/codex-panel-rime-launcher-soft.png`，随后关闭
检查时打开的浮层；没有启动应用或测试性改变防空闲/勿扰状态。

本文、README、交接、写入归属、视觉说明、测试说明与词表维护说明的本地链接已经检查。
推送使用普通 `origin main`，保留全部本地提交历史。默认 SSH 22 端口不可用，GitHub SSH
443 已成功 fetch；仅对该 Git 命令使用 `HostName=ssh.github.com` / port 443，不改仓库 remote。

## 验收边界

用户验收包括实际悬停展开、键盘面板搜索、多屏场景、锁屏文字对比度及日常候选质量。
保留 Rime 现有学习数据与个人短语；公开词表不等于导出个人输入历史。候选排序受上下文和
个人学习影响，隔离环境的候选结果只证明记录的输入样例。
