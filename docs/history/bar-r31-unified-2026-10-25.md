# 顶栏 r31：一体式 One Dark

用户确认 A 版预览后实施，保留顶部位置、35 px 高度、1.15 内容缩放及原有功能。平坦 One Dark 背景配单层细边框，移除渐变亮线和重复胶囊。左侧为启动器、工作区、布局与折叠工具，中央为日期时间，监控及系统控制归右侧；右端使用 settings 图标。

工作区使用淡蓝底与底线，圆角在创建及运行时布局中保持一致。中央两侧保留 24 逻辑像素间距；右侧不足时 GPU/温度压缩为点。隔离测试发现初版窄屏 CPU 标签被裁，最终将 monitor padding/spacing 收紧为 2/6、system spacing 为 8，并同步配置契约。

## 验证与应用

- 独立复审通过；11 个补丁按序应用到锁定源码成功，Noctalia 包构建成功。
- 私有 HOME/XDG/D-Bus/Wayland 验证 2560×1600 与 2048×1280、1.5 缩放，工具展开及托盘真实点击。三个独立 SNI fixture 验证 pinned 图标和两个 drawer 项目。最终生成配置另做窄屏复验，CPU/MEM 完整、时钟及系统控件无碰撞。
- `nix fmt`、完整 `nix flake check --no-write-lock-file`、系统 toplevel 构建均退出 0。
- `sudo nixos-rebuild switch --flake .#nixos-btw` 退出 0。应用时隔离 GUI 尚在运行，触发 Noctalia 按用户检查的 writer 保护；待隔离进程退出后，主代理 reset-failed 并启动真实服务成功。
- 实机 Noctalia 与 Home Manager active，运行包、生成配置和桌面截图已核对；未操作用户桌面键鼠。

系统输出：`/nix/store/1lnca57i69wmz29idy9p39d9g9ikdb06-nixos-system-nixos-btw-26.05.20261021.da6dc0e`。

本地证据：主仓库 `.work/bar-r31/{checks.log,toplevel.log,applied.json,applied-desktop.png}`；实现工作树 `.work/bar31/headless/RESULTS.md` 与 `case-2048-1792925917/shots/` 为最终生成配置截图。实现提交 `d20a41c`，合并 `272b255`。
