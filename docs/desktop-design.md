# One Dark 精修桌面

现行视觉依据为 [Astra 设计稿](visual-design.md)，2026-10-24 用户确认。
本轮实现与命令证据见[桌面视觉执行记录](history/visual-desktop-2026-10-24.md)。
仅修改声明并验证构建，没有激活系统或改写用户目录。旧轮次设计和测量有其时间范围，
历史取舍见[第九轮记录](history/desktop-polish-2026-10-24.md)。

颜色唯一来源是共享 [palette](../aspects/appearance/appearance/onedark-darker.nix)：
桌面 bg、卡片 surface、选择 selection；正文 brightFg、必要次级文字 fg，
blue 标示焦点和短选中标签。无整块蓝色选中行。桌面字体 Inter，中文回退 Noto Sans CJK SC；
Mango jump 标签使用 Maple Mono NF CN。配置接口与职责遵循[架构规范](architecture-design.md)
和[写入归属](config-ownership.md)。文件名暂保留 Darker，合并后统一处理。

| 界面 | 实施目标（设计稿章节） |
|---|---|
| Noctalia 顶栏 | §3–4：40 高、8/16 外距、12 外圆角；组内 8 圆角、selection 活动工作区蓝字；中文日期，保留托盘/状态入口和低频插件 |
| Launcher / 控制中心 | §5：680 全布局，pinned；控制中心 compact sidebar，浮动右上 offset12；本地源码主题适配将选中行与活动开关改为 selection 底、蓝色小标记，保持 Primary 蓝字语义 |
| 通知 / OSD | §6：380 通知，16/64 定位，最多3条；OSD 底部32；均 .98 背景、1 outline；warning 是 normal 消息附文字/图标，critical 保留原生红边 |
| 锁屏 / greeter | §6：共享静湾默认壁纸，中文日期；锁屏 compact 输入、不显示天气/媒体，blur .40、tint .48、淡入200ms；greeter 采用原生小方形蓝色登录按钮作为 C 类降级 |
| Mango | §3、§7：2px 焦点蓝边、12 圆角，inner8/outer16；tab/group/title/jump 的 selection/blue；overview16/32；仅浮窗阴影 black/.32、offset0/6；正文不透明，无 dim，无 layer blur/shadow/animation |
| 壁纸 | §11：四张构建期 SVG→PNG 2560×1600，更亮渐变与蓝青柔光；固定 URL/hash 的 Unsplash 夜景；原冷色002/005/008/009/011；用户 local/ 递归轮换 |
| 可选 Xorg | 仅外观跟随，复用同一默认图；dwm/dmenu/Dunst/Picom 不增加新会话行为 |

壁纸工厂、许可证与来源在 [资源目录](../aspects/appearance/appearance/resources/wallpaper/CREDITS.md)。
`managed` 为只读内置壁纸软链，用户 `local/` 只在应用时缺失则创建；两者在同一父目录中，
Noctalia 递归扫描跟随软链。锁屏使用当前壁纸；其声明默认与 greeter 同为静湾。锁定自动轮换也会在 shell 启动时随机选图，锁屏随桌面当前图。

Astra 的 S1–S3 阴影、面板行高/卡片尺寸、72px 锁屏时钟等部分值属于视觉目标；
只使用锁定原生接口或明确的局部源码 patch，不虚构配置项。
精确尺寸、用户卡原生壁纸 tint、禁用态文字、白色窗口后的 .98 合成、多屏缩放、
最长日期/九工作区/五托盘图标、长中文通知、认证失败与性能仍需实机截图验收。

`notify-send` 随本 feature 安装，用隔离审查消息检查普通/警告语义/critical；
构建检查不会发送通知、打开用户状态或应用配置。功能与状态归属另见
[Mango README](../aspects/desktop/mango-session/README.md)、[greeter README](../aspects/desktop/greeter/README.md)
和[Xorg README](../aspects/desktop/xorg-session/README.md)。
