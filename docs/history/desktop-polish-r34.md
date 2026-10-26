# 自主视觉巡检 r34（2026-10-26）

用户要求“自行检测优化美化，先做然后给图片”，本轮直接实施与核验，不另设预览审批。

## 取舍与实现

- Thunar 工具栏图标使用 GTK3 原生 icon transform 0.85，表头上下 padding 从 6 降到 4；列表和侧栏间隙保持，未接管 Xfconf 排序、列宽与窗口状态。
- 九个自定义操作补充原生 `xml:lang="zh_CN"` 名称和说明；默认英文名称、命令、ID、范围和类型不变。锁定 Thunar 的 UCA parser 根据 `LC_MESSAGES` 选取本地化字段，不读取 `LANGUAGE`；故仅在 `LANGUAGE`、`LC_MESSAGES`、`LC_ALL` 均未指定时，为应用进程默认设置中文消息 locale。显式覆盖保留；由 Thunar 启动的子应用可能继承这些变量。子菜单不支持本地化，保留 `Development`。
- 通知和 OSD 改为完全不透明，避免背景文字或壁纸透出；颜色与实色面板一致，r33 避让逻辑不变。
- 启动器原生 compact 会隐藏副标题和路径，因此保留完整行。顶栏、Kitty、Neovim 延续现行配置，未为了增加改动量替换已有布局或插件。

## 验证

完整 flake checks、系统 toplevel 构建和独立静态审核通过。最终包在隔离 HOME/XDG、D-Bus、Wayland 中验证：Thunar 默认中文与显式英文覆盖均正确，宽窄窗口已截图；桌面启动器、控制中心和通知在 2560×1600 与 2048×900 下完成截图核对。测试样例未执行自定义动作，Development 子菜单未展开验收；窄窗口的超长绝对路径由原生地址栏横向裁切。

`nixos-rebuild switch` 成功，实际系统为 `/nix/store/f53rnrcjals4fhrl2bl0x4x05816riq6-nixos-system-nixos-btw-26.05.20261025.1f607aa`。Home Manager 与 Noctalia active，无失败用户服务；生成 CSS 的 icon transform 与通知/OSD 实色配置已核对。个人 Thunar Xfconf、快捷键及 LibreOffice 配置哈希未变。既有 Thunar 进程需正常退出后重开以加载新 wrapper 和菜单。

全部私有图形进程已退出。截图环境关闭索引插件和 Secret Service 自动启动，以免生成大型测试缓存或出现新钥匙串提示；不改变生产配置。测试早期 D-Bus 环境隔离不足，已修正并重新截图；宿主 dconf 文件时间在最终截图结束后发生变化，具体来源未确定，主题键值相同，故不宣称整个 dconf 未变。

原始证据、隔离限制、截图及应用核验位于 Git 忽略的 `.work/polish-r34/`；展示图为 `01-files.png`、`02-launcher.png`、`03-notifications.png`。
