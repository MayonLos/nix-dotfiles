# 提醒与桌面小组件运行说明

## 提醒

`ReminderScheduler(context).reschedule(now): Boolean` 先撤销旧的滚动提醒，再为活动学期中最近一节未开课课程设置一枚 `setExactAndAllowWhileIdle` RTC 闹钟。系统 API 31+ 缺少精确闹钟授权时返回 `false`；其他正常完成（包括提醒关闭或暂无课程）返回 `true`。提醒仍会由主界面在保存/切换学期后重排。

`ReminderReceiver` 按 `上课开始 - 提前分钟数` 的窗口投递通知，允许设备在提醒时间后五分钟内恢复时补发。`TimetableStore.claimReminder` 以完整课程 occurrence key 去重。通知采用完整 delivery key 作为 tag、固定 int ID，避免仅靠字符串 hash 导致课程提醒互相覆盖。

`RescheduleReceiver` 处理开机、系统时间/时区变化、包替换与精确闹钟权限状态变化。它先投递刚到期的五分钟窗口，再重建提醒，以免时钟变化抹掉刚应触发的通知；持久化去重避免与旧闹钟并发重复通知。

## 小组件刷新

今日与下一节 Glance 小组件显示最后更新时间，今日组件标记当前正在上的课，下一节组件显示日期、时间和教室。配色随系统深浅主题变化。组件内“刷新”触发 `WidgetRefreshAction`。

`WidgetRefreshScheduler(context).reschedule(now)` 计算下一次课程开始、课程结束或学期时区午夜，并使用普通 `AlarmManager.set` 排程；它不请求精确闹钟权限。显式接收器为 `dev.mayon.timetable.widget.WidgetRefreshReceiver`，Manifest 中只需声明非导出 receiver，不需要导入 intent-filter。触发后刷新两个 Glance provider 并续排下一边界。

应用层课表变更后可在自己的协程中调用 `refreshTimetableWidgets(context)`，它更新两种 widget 并重新排程。提醒投递和系统重排接收器也会更新 widget 并续排。非精确系统闹钟受 Android 省电策略影响，更新可能晚于边界；用户可随时点组件“刷新”。

## API 35 AOSP 模拟器验证

最终模拟器会话用应用内 `WidgetHostActivity` 挂载真实 Glance `RemoteViews`，在深色和浅色系统模式分别渲染了今日/下一节组件；这验证了 Glance 生成的 RemoteViews 能在 AppWidgetHost 环境展示，不是用普通 Compose 页面模拟 widget。截图位于 `/home/mayon/nix-dotfiles/.work/r50/android/shots/round2/round2-dark-widgets.png` 与 `round2-light-widgets.png`。截图复核后刷新入口已在 widget 标题行右对齐，星期使用中文；周视图当前节号也已高亮。**该验证不是 OPPO Launcher/ColorOS 桌面实测。**

提醒使用实际 `AlarmManager` 而非 mock 做过一次 API 35 AOSP 模拟器仪器验证：`reminder-instrumentation.log` 中 `ReminderTest#realAlarmFiresExactlyOnceAfterHostClockAdvance` 通过，日志记录观察到一条通知（最终记录见 alarm-delivered.txt）。复现脚本 `packages/timetable-android/tools/verify-reminder.sh` 要求已启动的隔离模拟器中安装 Debug 和 AndroidTest APK；脚本在测试运行期间通过 ADB 将模拟器时间调至预定提醒前 6 秒，等待真实闹钟通知出现并验证本轮仅一条，然后保存通知栏截图。示例：

```sh
packages/timetable-android/tools/verify-reminder.sh emulator-5580 /home/mayon/nix-dotfiles/.work/r50/android
```

该结果仅证明 API 35 AOSP 模拟器上的单轮 alarm/notification 行为。Android 29–34、Doze/重启/时区变化的完整矩阵，以及 ColorOS 电池策略和 OPPO 桌面 widget 刷新仍待目标设备验证；不能据此保证真实手机在强省电或强行停止时准点送达。

该测试需 `clockHandshake=true`，工具脚本会自动传入；普通 connected 测试默认跳过需要宿主改时的用例。
