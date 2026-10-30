# Mayon 工具箱

`mayon-tools` 安装公开 `pkgs.mayonTui.tools`。同一程序包含 docker、ports、serial、keys、voice 页，`[` / `]` 切换；原各页内部数字页签保留。默认 ports，首次访问才初始化；切走或失焦暂停刷新与流，保留视图状态。打开工具箱不会初始化 Docker。

入口：`mayon-tools [docker|ports|serial|keys|voice]`；原只读 CLI 子命令位于对应页名后。keys 读取 Mango 拥有的 `~/.config/keys-mayon/bindings.json`，serial 保留 `~/.config/serial-mayon/` 与日志位置，voice 只通过现有私有 socket 访问独立 daemon。此 feature 不创建容器/卷、串口日志、语音模型或其他运行时数据；移除仅撤回安装，不删除上述用户数据。

Clash 与 Bilibili 为独立程序。桌面快捷键和窗口规则归 Mango feature，协议/交互实现位于 `packages/mayon-tui/`。原功能 feature 通过 `includes` 选择工具箱。
