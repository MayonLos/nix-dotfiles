# keys-mayon

只读的 Mango 快捷键速查，沿用 mayon-tui 的 One Dark palette、细框、淡底选中行和左侧蓝条。
采用 Ratatui 分组列和共享中文/拼音搜索；不拉取社区快捷键表，不执行动作。

```sh
keys-mayon
keys-mayon list
keys-mayon list --json
keys-mayon --data /path/to/generated-bindings.json list --json
```

数据默认取 `$XDG_CONFIG_HOME/keys-mayon/bindings.json`（默认 `~/.config`），
可用 `KEYS_MAYON_DATA` 或 `--data` 覆盖。Mango 模块从最终合并的 settings
自动生成版本为 1 的 `{version, bindings: [{mode, kind, raw}]}` JSON，包含
所有模式的键盘、鼠标和手势绑定，包括原有帮助入口。命令缺数据时说明路径并退出，
不提供可能过时的内置绑定副本。JSON 包含公开配置中的命令路径，没有运行时状态或秘密。

`list --json` 输出完整数组：`mode/kind/raw/chord/group/description/conflict`；
raw 与 Mango 实际配置逐字对应，规则未识别的动作仍显示原始动作。
中文说明和分组是动作规则，无第二份手写绑定。`check_bindings.py` 将 JSON、
命令输出和 HM 渲染的 Mango 配置按多重集合比较，重复行也不会被漏检。

- `0` 全部；`1` 窗口、`2` 工作区、`3` 应用、`4` TUI 工具、`5` 截图、`6` 媒体、`7` 系统。
- `/` 输入模糊查询：按键名、中文说明、模式或原始命令。多词 AND、大小写不敏感，支持中文、全拼和首字母；边输入边过滤，Enter 保留结果，Esc 恢复打开前过滤。输入中方向键仍可选择条目。
- `j/k`、方向键选择；PgUp/PgDn 或鼠标滚轮滚动；Home/End 或 g/G 选首尾；点击条目或分组。
- Enter 查看完整原始动作，方向键或滚轮滚动；Enter/Esc 返回。`?` 帮助；`q` 退出；列表 Esc 先清过滤，再退出（搜索时 q 是文本）。
- 输入支持字符光标、Home/End、Ctrl+A/E、Ctrl+U/K/W、Alt+Backspace 和单行粘贴；真实终端光标随光标移动，匹配字符使用现有黄色。
- 相同组合在同模式或 common 重叠时标红 `!`；键盘族跨 bind/bindl 等类型检测，鼠标与手势分开检测。

90 列使用两栏，每条快捷键和说明各占一行；更窄时单栏，138 列起三栏。
单组结果自动均分到各栏，避免只占左栏。长命令在详情中换行，CLI 和 JSON 始终完整。没有可靠的各工具键位导出接口，
本轮不猜测工具内部键位。数据反映当前构建配置，不查询合成器的运行时状态；
主代理应用新配置前，旧会话可能仍使用旧绑定。

公开包工厂：`default.nix { pkgs; }` → derivation（`pkgs.keysMayon`）。
复用只读 `../mayon-tui/crates/ui`；独立 Cargo workspace 和 Cargo.lock。
程序不写配置、缓存、历史或状态。HM 拥有的 JSON 是 Nix store 的只读链接（目标 0444）；
目录继承 HM/XDG 权限，不新增可写敏感文件。移除工具只移除命令；移除 Mango 功能时
其 JSON 随 HM 链接清理，不涉及应用数据。

验证：`cargo test`、`cargo clippy --all-targets -- -D warnings`、`cargo fmt --check`；
flake checks `keys-mayon`（包内含上述检查）、`keys-mayon-bindings`（真实数据一致性）。
