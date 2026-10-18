# 共享外观数据

`default.nix` 只把 `appearance` 加到 Den 用户 schema，默认 `null`。绑定或个人身份可以提供一份完整调色板；这个数据不会自动选择应用、安装软件或启用桌面。

`contract.nix` 限定主题名和当前消费者使用的语义色，颜色格式为 `#RRGGBB`。`onedark-darker.nix` 提供现有 Neovim 使用的 One Dark Darker 值，背景为 `#1f2329`；来源及 MIT 许可见 `ONEDARK-LICENSE`。`ansi.nix` 是 Kitty 和 Neovim 共用的 16 色顺序，命名色的含义不由各应用重新定义。

`kitty.nix` 与 `neovim.nix` 是显式导入的 HM 适配器，参数为 `{ palette = user.appearance; }`。它们只给已选择的应用提供配置，不设置 `programs.<app>.enable`。Kitty 使用 HM 自有 renderer 生成 `kitty.conf`；Neovim 使用当前锁定 HM 的 `initLua`，样本只设置少量 UI 高亮和终端色，不替代现有完整 Lua 主题。

同一绑定只有一个有效 palette。Nix 子模块按字段检查，冲突色值需明确处理，不用全局可写主题文件或自制主题 registry。另一账号、另一主机、宿主 greeter 的外观各自选择，没有隐式传播。

## 真实桌面的接入前提

这些适配器目前只在隔离样本中消费，不能直接与旧 Kitty/Noctalia 接线同时启用。旧配置由 HM 写 `mayon.conf`，Noctalia 修改可写的 `kitty.conf` stub 和主题文件；其 hook 会先 `touch kitty.conf`，对 HM store symlink 会失败。迁移真实终端时必须先停用 Noctalia 的 Kitty 模板，并迁走旧 seed/stub 和重复配置，再由 HM 单独拥有最终文件。不能仅添加本适配器、保留两套写入者，也不以 `mkForce` 掩盖归属冲突。

类似地，现有丰富 Neovim 主题将来要保留高亮实现并改为读取共享数据；本样本不是把它替换为四组高亮。Noctalia、Mango、GTK/Qt、字体和透明度尚未迁移。

`checks.nix` 使用 Kitty 自身的配置解析器检查最终文件，以 headless Neovim 检查实际高亮与 ANSI 值；不需要或启动图形会话。[组合样本](../../tests/den/README.md)覆盖数据不启用功能及两主机/两账号选择。这里验证的是独立消费者，不是现有桌面的共同启用验收。

Kitty 内嵌 Python 当前以优化模式运行，`assert` 会被移除；检查须显式抛出错误，并在全部比较完成后写出 `kitty.json`，构建脚本再确认该文件存在。用错误背景色做过负例，检查按预期失败，不能仅以 `+runpy` 退出成功认定验证完成。
