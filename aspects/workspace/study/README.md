# Study

可选 Den feature `study`，没有实体输入。公开入口为 `default.nix`，
显式测试钩子为 `checks.nix`。通过 `pkgs.studyMayon` 安装 `study-mayon`/`study`，
提供「学习」desktop entry 与精确提醒的每日/登录 bootstrap timer。
真实用户选择由主代理在 inventory binding 的 includes 中加入 `study`，本 feature 不隐式选择宿主。

程序源码、数据许可、CLI、导入格式和提醒取舍见
[包 README](../../../packages/study-mayon/README.md)。
HM 仅拥有 desktop entry、`~/.config/study/reminders-enabled` 标记和
`study-plan.service`/`study-plan.timer`；不接管用户 SQLite 或设置。
程序拥有 `~/.local/share/study/`（0700、数据库 0600）、可变学习/课表记录和音频缓存。

不新增常驻服务、不每分钟轮询、不阻止睡眠。bootstrap 让程序安排下一个精确 transient
user timer；修改数据后重排。通知 action 支持时打开 `study-mayon` Kitty 窗口。
移除 feature 撤回标记，已有 transient callback 看到标记缺失即退出，不再通知或续约；
保留用户数据。应用后仍须核对用户 manager 的 timers、通知 action、实际学校格式与发音。
桌面快捷键/窗口规则/Noctalia 归桌面维护者，未在此 feature 写入。
