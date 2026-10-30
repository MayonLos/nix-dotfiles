# mayon-tools

一个终端窗口内的 Docker、Ports、Serial、Keys 和 Voice 页。默认打开 Ports；`[ / ]` 或点击顶部页签切换，输入时方括号进入输入框，内部数字键保持原用途。

```sh
mayon-tools
mayon-tools docker
mayon-tools ports --docker-map
mayon-tools serial list
mayon-tools keys list --json
mayon-tools voice
```

每页首次访问才创建，切换时保留筛选、选择、子页和有上限的数据缓冲，取消刷新与流；终端失焦时暂停。Docker 未访问时不创建连接；后台页不刷新。绘制由键盘、数据变化和消息过期触发，连续变化最多每70ms绘制一次。语音通过现有 daemon socket 通信，不复制其配置与录音实现。

配置和数据路径沿用各页原有约定，见各 crate README；迁移不改写或删除原数据。旧的独立 TUI 可执行入口合并到本命令。

离线验证：`cargo test -p mayon-tools -p dockertui-mayon -p portstui-mayon -p keys-mayon -p serial-mayon`。
Docker 的 `tests/mock_engine.py` / `cli_mock.py` / `vm_mock.py` 与 Serial 的 PTY 测试只使用临时环境；Keys 可用 `--data` 指定 fixture，Voice 无 daemon 显示按需待命。
