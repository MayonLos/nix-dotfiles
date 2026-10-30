# voice-input

可选择的个人离线中文语音输入 feature，ID `voice-input`。放在 apps：它消费已有桌面
输入法/音频能力，不拥有 compositor、快捷键、Noctalia、PipeWire 或 Fcitx daemon 生命周期。
默认不加入真实 host/bundle，主代理在用户 binding 的 `includes` 中选择。

输入：已有 Fcitx5 和 PipeWire session support、公开 `pkgs.mayonVoice`、
`config.nixDotfiles.graphicalSessionTargets`。不额外 `includes` 整个桌面。
输出：安装 CLI/TUI、给现有 HM Fcitx5 `addons` 公开选项追加提交桥、systemd 用户 socket/service。
`checks.nix` 是公开验证钩子，构建包、运行单元/进程测试和编译 addon。

socket 随所选图形 target 启停，`0600`；service 无登录 wants，仅 socket 激活，
空闲默认 10 分钟退出释放模型；退出图形会话由 `PartOf` 停止整组子进程。
不修改桌面目录；快捷键由桌面 owner 并入，推荐 `SUPER,V` toggle。
若锁定 Mango 的 release 行为通过现场验证，可用 press start / release stop。

拥有文件：仅包内 immutable 程序、addon、用户 unit 声明。配置
`~/.config/mayon-voice/config.toml`、模型 `~/.local/share/mayon-voice/models/`
归用户，运行时音频/socket 放 `%t/mayon-voice/`。不读取/写入应用历史、词库或认证。
润色默认关闭；启用后只读既有 sops runtime key，明文不进入 store。
完整配置、权限、clipboard 回退取舍、秘密边界和开发命令见
[公开程序说明](../../../packages/mayon-voice/README.md)。

移除 feature 撤回包、addon 和 unit，不删除用户配置、模型或下载；需应用后确认服务
与 Fcitx addon 已退出。真实桌面环境、麦克风、QQ/微信输入仍须实机核验。
