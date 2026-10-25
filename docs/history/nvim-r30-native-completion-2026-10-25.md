# Neovim r30：原生补全交互与浮窗

用户确认 `.work/nvim-r30/preview.png` 的布局方向后，明确选择继续使用 Neovim 原生补全，不引入 blink.cmp。

## 设计与边界

- 保留原生 LSP 候选、resolve、snippet 展开和既有自动请求防陈旧机制。
- 候选菜单采用 One Dark 同底细边框，显示类型图标、完整标签与按字符显示宽度截断的详情；文档由原生引擎提供，界面层负责尺寸、样式和滚动。
- 菜单打开时 Tab 接受已选项，无选中时接受首项；Enter 仅接受已选项，否则换行；Esc 关闭菜单并留在插入模式。菜单关闭时 Tab 优先跳转 snippet，再接受 AI，最后缩进。
- Ctrl-f/Ctrl-b 滚动当前补全文档。隐藏原生补全计数，移除依赖屏幕属性猜测位置的额外选中行装饰。
- 自动参数提示遵循服务器声明的触发字符，保留手动 `gK`；补全菜单可见时避免抢占浮窗。

原生终端网格的布局与 VS Code 不完全相同，候选、类型详情与文档丰富程度取决于语言服务；设计稿展示布局意图，不伪造运行时信息。

## 验证

独立审核复现并关闭了 `(a,` 参数重触发会话丢失问题，签名会话与浮窗展示分离；菜单 Esc 使用 buffer 局部抑制，避免候选回滚的 TextChangedI 重新弹出菜单。已打开菜单时 Ctrl-Space 保留当前菜单和选择，不重复请求。

私有 HOME/XDG/D-Bus、headless Sway 与真实 Kitty 验证真实 LuaLS 候选、文档、Tab 接受、参数高亮、Ctrl-f/Ctrl-b 滚动、窄画布及光标靠近底部。文档窗口由原生引擎选边，界面层限制尺寸；文档消失和换 buffer 后无残留。截图与探针保存在 `.work/nvim-r30-docui/`。

验证中修正了两项证据问题：锁定 0.12.6 的 `complete_info({ "preview_winid" })` 不返回该字段，必须使用无过滤调用；GUI 脚本对 `nvim_input` 预先替换 termcodes 导致特殊键双重编码，改为直接传 `<C-Space>` 后重复按键与 RPC 均正常，旧超时不作为生产缺陷结论。

最终格式化、完整 flake checks、normal 包及 toplevel 构建均退出 0。随后 `sudo nixos-rebuild switch --flake .#nixos-btw` 成功，当前系统为 `/nix/store/g962i1rsm1z23lfq04gn9vjqd9xd3had-nixos-system-nixos-btw-26.05.20261021.da6dc0e`。Home Manager 与 Noctalia 服务 active。实际用户 profile 的 Neovim 隔离启动退出 0，错误为空、`pumborder=rounded`、`cmdheight=0`、`shortmess` 含 `c`、未加载 blink；两补全模块逐字节与最终源码一致。证据 `.work/nvim-r30/build-results.json` 与 `applied.json`。

真实 GUI 验证使用 dev wrapper 加最终源码；安装后 smoke 核对实际 profile 模块一致。既有 Neovim 进程需重开加载更新，未操作真实项目或 AI 登录状态。
