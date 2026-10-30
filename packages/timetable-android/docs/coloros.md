# ColorOS 提醒与后台适配

目标是中国大陆 OPPO / ColorOS、无 Google 服务。课前提醒由本地 `AlarmManager` 和 Android 通知实现，不依赖 Google Play Services。SDK 许可已获用户同意，工程已构建；目前只有 API 35 AOSP 无头模拟器的部分运行证据，没有 OPPO 实机验证。具体菜单会随机型、地区和 ColorOS 版本变化。

## 当前权限与调度实现

当前 Manifest 声明 `POST_NOTIFICATIONS`、`RECEIVE_BOOT_COMPLETED`、`SCHEDULE_EXACT_ALARM`（`maxSdkVersion=32`）和 `USE_EXACT_ALARM`。用户开启课前提醒后，`ReminderScheduler(context).reschedule(now)` 撤销旧滚动 alarm，并对下一条未来课程安排单次 `setExactAndAllowWhileIdle(RTC_WAKEUP, ...)`。API 31+ 若 `canScheduleExactAlarms()` 为 false，方法返回 `false`，界面提示用户处理权限；提醒关闭、无活动学期或无未来课程时不保留提醒 alarm。

| Android API | 当前声明/行为 | 用户侧含义 |
|---|---|---|
| 29–30（Android 10–11） | schedule 精确闹钟权限声明不适用；调度仍使用 `setExactAndAllowWhileIdle`。 | 没有 Android 12 特殊访问授权步骤；通知也不是 API 33 的运行时权限。尚未在此版本实测。 |
| 31–32（Android 12/12L） | `SCHEDULE_EXACT_ALARM`，最大 API 32；代码在安排前检查 `canScheduleExactAlarms()`。 | 用户需在系统“闹钟和提醒”特殊应用访问中允许；未允许时提醒未安排。尚未在此版本实测。 |
| 33+（Android 13 及以后） | `USE_EXACT_ALARM`；另在用户开启提醒时请求 `POST_NOTIFICATIONS`。 | 通知拒绝时不会显示课程提醒。USE_EXACT_ALARM 的适用范围和商店政策应在发行渠道改变时重新评估。AOSP 模拟器为 API 35，提醒实际触发仍待验。 |

`USE_EXACT_ALARM` 面向确实以定时提醒为核心的应用。项目当前以个人侧载为目标；侧载不豁免 Android 系统的闹钟、通知、省电规则，也不代表其他应用商店会接受该权限。若以后发布到商店，重新核对该商店的权限政策。[Android 精确闹钟指南](https://developer.android.com/develop/background-work/services/alarms)、[Android 14 精确闹钟权限变化](https://developer.android.com/about/versions/14/changes/schedule-exact-alarms)

闹钟会增加唤醒耗电。当前只安排最近一条提醒，投递后重新计算下一条；系统空闲配额及 ROM 策略仍可能造成延迟，不能保证所有电源状态下绝对准点。不要为普通 widget 自动刷新申请精确闹钟权限：widget 使用普通非精确 `AlarmManager.set`，按课程开始、结束或学期时区午夜刷新；系统省电时可能延迟，组件提供手动刷新。

## 系统变更与重复通知

Manifest 将 `RescheduleReceiver` 注册到 `BOOT_COMPLETED`、`TIMEZONE_CHANGED`、`TIME_SET`、`MY_PACKAGE_REPLACED` 和精确闹钟权限状态广播。重排依据持久化课表计算，不依赖旧 alarm。

时钟或时区变化广播可能与刚到期 alarm 竞争。当前 receiver 会先查找并尝试投递提醒时刻在“当前时间之前五分钟内、或当前时间之后两秒内”，且课程尚未结束的课程，再重建未来 alarm。`TimetableStore.claimReminder` 按课程 occurrence key 持久化去重，避免旧 alarm 和系统重排导致重复通知。学期仍采用自身保存的时区；设备时区变化不修改学期设置。

重启会清空系统 alarm，`BOOT_COMPLETED` 后从本地数据恢复。接收器只处理 App 曾启动、设备已完成启动等系统实际送达的广播。用户强行停止、关闭通知、撤销精确闹钟权限或 ROM 限制后台时，系统可能不投递或通知不可见；重新打开 App 后会再次重排。Android 广播行为见[系统广播例外](https://developer.android.com/develop/background-work/background-tasks/broadcasts/broadcast-exceptions)和[Intent 参考](https://developer.android.com/reference/android/content/Intent)。

## OPPO / ColorOS 用户设置路径

安装并首次启动后，在 App 的“设置”中打开提醒并允许通知。菜单若不同，先在“设置 > 关于本机”确认 ColorOS/Android 版本，再使用系统设置搜索下列关键词。

1. **通知**：设置 > 通知与状态栏/通知与快捷设置 > 应用通知/通知管理 > 课表 App，允许通知并检查“上课提醒”类别、锁屏、横幅、声音和振动。ColorOS 菜单可能变化，见 [OPPO 通知管理说明](https://support.oppo.com/en/answer/?aid=neu13639)。
2. **自启动**：搜索“自启动”“自动启动”或“自启动管理”，找到课表 App 并允许。部分版本路径为“设置 > 应用 > 自启动”或“应用管理 > 特殊应用权限 > 自启动管理”。COROS 对 ColorOS 12 的指引给出了示例路径，但不能代表所有 OPPO 机型：[COROS OPPO 权限指南](https://faq.coros.com/help/article/64213cc705be2e4057ad0799)。
3. **后台电池**：搜索“应用耗电管理”“后台活动”或“电池优化”，对课表 App 允许后台活动/设为不限制（如果本机提供此选项）。ColorOS 12 的 COROS 指南以及第三方 ColorOS 13–16 指南提供了不同例子：[ColorOS 12 指南](https://faq.coros.com/help/article/64213cc705be2e4057ad0799)、[ColorOS 13–16 第三方指南](https://jspsoft.co.kr/board_view.php?id=13)。
4. **闹钟和提醒（Android 12/12L）**：设置 > 应用 > 特殊应用访问权限 > 闹钟和提醒/闹钟与提醒 > 课表 App，允许 `SCHEDULE_EXACT_ALARM`。Android 13+ 当前使用 `USE_EXACT_ALARM`，不要照 API 31–32 路径额外要求用户开同一权限。

若设置入口不同，以手机系统页面为准；以上是搜索指引，不是 OPPO 对所有设备的统一实测路径。OPPO 帮助页也提示设置会因设备/版本不同而异：[OPPO 通知设置说明](https://support.oppo.com/en/answer/?aid=neu13639)。

## 当前验证状态

API 35 AOSP headless emulator 已完成六项 UI/导入测试，以及独立的真实 AlarmManager 提醒测试：同一个 instrumentation 内将时钟调到提醒前6秒，到点观察到且只观察到一条通知，并捕获深浅系统主题截图。Glance 两类组件在 debug AppWidgetHost 中实际显示 RemoteViews。最终实际 RAM 1280 MiB，宿主 RSS 采样峰值 2790.09 MiB；模拟器已关闭、AVD已清理。

Android 29–34 的版本矩阵、重启/Doze、强行停止、电池优化、通知权限拒绝及 ColorOS 菜单仍待实机验证。AOSP 结果不能外推为 OPPO/ColorOS 行为，也不保证强省电时准点。证据与复现见 [reminders.md](reminders.md)。
