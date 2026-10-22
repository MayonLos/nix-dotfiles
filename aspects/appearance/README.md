# 共享外观数据

`default.nix` 将完整 palette 接入 Den host/user schema。真实绑定在
`inventory/hosts/nixos-btw/default.nix` 选择 One Dark Darker；数据本身不会安装应用或启用
桌面。`contract.nix` 检查主题名、颜色值、字体/光标字段和 `reducedMotion` 布尔偏好，`onedark-darker.nix` 保留当前
主背景 `#1f2329`，来源和 MIT 许可见 `ONEDARK-LICENSE`。`ansi.nix` 是 Kitty 和 Neovim
共用的 16 色顺序。

palette 是静态类型化输入，功能 renderer 显式消费它：交互会话将颜色用于 Mango、Noctalia、
Fcitx、GTK/Qt、greeter 和字体；命令行终端与编辑器读取对应字段。壁纸不会改写主题色。每个
host/user scope 单独提供数据，不隐式跨用户或跨主机传播。功能被选择时才会生成对应应用配置。
`noctaliaIntegrations` quirk 由 registry 声明，各应用仅在被选择时贡献集成标记；Noctalia 据此
渲染相应集成，不会另有功能写同一配置文件。Kitty 与 Mango 模板始终不由 Noctalia 接管。

Neovim 使用锁定 OneDark 完整主题和薄 Lua 适配，从 `mayon.generated` 读取 palette 与 ANSI；语言
aspect 向生成数据贡献 LSP、formatter 和 linter。唯一的数据协议由各 renderer 消费，不再维护
仅供示例的 adapters。Kitty 使用 HM renderer 生成完整配置，Noctalia 不拥有 Kitty 模板。

相关生产检查见根 `checks.interactive-session-config`、`checks.command-line-runtime` 和
`checks.editing-composition`；它们覆盖最终配置/解析器、组合隔离与编辑器数据。实际图形外观、
显示器行为、输入法和桌面启动仍需配置应用后在真实会话验收；构建检查不代表已应用。每批记录
见[执行记录](../../docs/history/den-execution.md)。

`reducedMotion` 默认 `false`，保留日常完整动效。设为 `true` 时，已选择的 Mango、Noctalia
与 Kitty 分别关闭窗口动画、shell/壁纸/锁屏转场及光标闪烁；Noctalia 还从面板移除频谱与猫，
关闭媒体滚字和天气效果。插件配置及用户历史保留。它是声明式偏好，不是运行中的切换按钮，
不自动改变电源/GPU策略，也不声称会关闭所有第三方应用自身动画。
