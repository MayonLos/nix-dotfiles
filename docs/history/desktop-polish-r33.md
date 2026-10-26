# Thunar 与浮层布局 r33（2026-10-26）

用户确认两张预览后实施。Thunar保留原生菜单/工具栏/侧栏/列表，局部GTK样式收紧，并通过应用包装器在LANGUAGE未设置时默认zh_CN:en_US。显式LANGUAGE保留，C locale禁用翻译；从Thunar启动的子应用可能继承该变量。未接管xfconf排序、列宽、窗口几何。

SYSTEM提示和右上通知按同一输出的逻辑坐标避让：先下移，空间不足尝试左移，无法同时容纳则本次hover抑制提示；通知内已有指针时不移动可交互通知。提示淡出结束后才释放占用。当前右上通知使用不预留空间的exclusiveZone=-1，因此offset_y=64自屏幕边缘计算；其他通知位置保持原语义。

## 实现归属

- `aspects/desktop/session-support/resources/gtk/gtk3.css`：仅 `.thunar` 样式，Noctalia 继续作为生成 CSS 的唯一 writer。GTK3 TreeView 无逐行 CSS 节点，使用现有 vertical/horizontal separator 调整单元格间隙。
- `aspects/apps/file-manager/packages.nix`：Thunar 与设置入口的局部语言默认，原有插件和 D-Bus/systemd 接线保持。
- `aspects/desktop/mango-session/noctalia/hud-overlay-clearance.patch`：实际 tooltip configured 坐标、占用信号、通知整体平移及 hover 抑制；不重建通知卡片、不重启倒计时。
- `resources/overlay-clearance-test.cpp` 与 `runtime-check.nix`：从锁定源严格应用真实补丁后编译几何回归。通知动画同时计算当前位置与目标位置，避免卡片移动途中越界。

## 验证记录

独立审核发现的动画占用缺陷已修复。新增严格补丁检查还发现旧 `hud-tooltips.patch` 最后一个 hunk 缺少第三行尾上下文；补充真实空白上下文后，全补丁严格应用且 1,339 个源码文件与目标树逐字节一致，未改变该旧 hunk 的代码语义。

Thunar 在私有 HOME/XDG/D-Bus/Mango 中验证 2048×1280 与 1280×900：中文菜单、紧凑布局和长路径可用；`LANGUAGE=en` 经 FileManager1 激活仍为英文。测试核对服务 Exec、进程命令行和 LANGUAGE，没有操作真实个人配置。首次私有 D-Bus 测试服务项创建过晚，误激活旧包；修正为先创建服务项再启动私有总线后重新通过，首次结果不作为验收证据。

最终 Noctalia C++ 构建、完整 flake checks 与系统 toplevel 构建均通过。最终产物 `prcv1hf7wjjjvdgcjjdi1s99wyxsj845-noctalia-5.3.0` 在 2560×1600@1.5、2048×900@1.5 验证并存、离开恢复、反复悬停及三通知堆叠；各场景的通知按钮均实际返回 `open`。800×600@1.5 使用仅保留生产 CPU 小组件的测试顶栏，确认通知完整、SYSTEM 本次 hover 抑制、超时后不自动重显以及离开重进恢复。多屏与负桌面原点只完成源码/几何审查，未进行双输出 GUI；淡出行为未做逐帧录像。全部私有 GUI 进程退出后才进行系统应用。原始日志与图像保留于 Git 忽略的 `.work/polish-r33/`。

## 边界

仅处理当前右上通知与顶栏 SYSTEM 提示，其他位置/普通文字提示沿用上游行为。私有测试中的橙色窗口边框是隔离 Mango 默认样式，不是生产配色。Thunar 自定义操作标签保留原有英文，菜单的 gettext 翻译不改变这些自定义标签。


## 应用结果

`nixos-rebuild switch` 成功，当前系统为 `/nix/store/13cyxb9h3mzrfacrd2ivy3b7skyzrzai-nixos-system-nixos-btw-26.05.20261025.1f607aa`。真实运行 Noctalia 为已验收的 `prcv1hf7…`，Noctalia/Home Manager 均 active，用户失败服务为空，应用后 Noctalia error journal 为空。实际 Thunar 包装器含中文默认设置，生成 GTK CSS 含紧凑规则；Thunar Xfconf、快捷键及 LibreOffice profile 哈希与操作前一致。内核未变，无需重启电脑；旧 Thunar 进程需正常退出并重开以加载新包装器。

应用证据 `.work/polish-r33/run/applied.json`，真实桌面只读截图 `.work/polish-r33/applied-desktop.png`。测试结束清除 5 份可重建索引缓存（996,891,576 字节），保留截图、日志和代码。
