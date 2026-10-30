# Android 架构与当前验证状态

更新于 2026-10-30。目标是中国大陆 OPPO / ColorOS、无 Google 服务。用户已同意 Android SDK 许可；`nix develop .#android` 与 Android Gradle 工程已启用，Debug APK 和 unsigned release APK 已构建。第二阶段还未完成全部模拟器验收，也没有 OPPO 实机验证。当前构建与安装证据见 [phase2-install.md](phase2-install.md)。

## 模块和数据

- `core` 是纯 JVM Kotlin 模块：课表 v1 模型/JSON、学期周次计算、WakeUp 文件与 ICS 编解码、照片 OCR 结果的格线重建、二维码分片/接收 codec。`core:test` 在最近一次记录的 Gradle 构建中通过。
- `app` 是 Kotlin + Compose / Material 3：今日和周视图、课程/学期编辑、导入导出、照片处理、设置、提醒及 Glance widgets。SDK 已用于构建，但运行行为并不等于实机验证。
- 每个学期保存一份 `files/semesters/<id>.json`，通过 `AtomicFile` 写入；提醒偏好、活动学期选择与投递去重记录留在设备偏好。导入先解析/校验，再由用户确认。**相同学期 ID 当前只有用户显式选择“替换”后才覆盖**；没有“保留两份相同 ID”的选项。课程重叠目前未实现专门冲突提示。
- WakeUp 仅解析用户选择的本地导出文件；分享口令/链接取回数据需要 WakeUp 服务端，本 App 不请求该服务。ICS 导入要求已有学期作息表，照片不会猜学期开学日期或课时表。

## 照片与二维码

照片入口是 Android `GetContent()` 系统图片选择器，另有系统相机拍照入口；当前不是 Android Photo Picker API。图片按 EXIF 解码，进入可拖动四角裁剪，可手动旋转，然后由 APK 内 PP-OCRv4 detector/recognizer 与 ONNX Runtime CPU 本地识别。当前引擎没有方向分类模型，方向由 EXIF 和用户旋转处理。识别后的格线/字段重建依赖 JVM core 算法。

照片校对页面把识别结果逐格列出，低置信度或需复核格会突出显示；**保存前每一格均须用户勾选确认**。用户可以修改课程名、教师、教室、星期、节次和周次，也可以添加或移除格子。Android 连通 OCR 的整图准确率/内存尚无本阶段基准结果；第一阶段 Python/OpenCV 参考准确率不能当作 Android 实测。

二维码分享页显示逐帧 QR。接收采用 Android `GetMultipleContents()` 选择含 QR 的图片并离线解码，多图逐帧交给 core 校验；当前没有实时相机扫码界面。传输压缩包有总大小/帧数/解压限制和 SHA-256，不加密；收齐后仍经过 JSON schema 校验与普通导入确认。

## UI 状态与恢复

启动后进入今日视图；周视图可切周，当前周/课时以课程和时钟计算。照片、二维码接收、对话框和未提交编辑保存在当前 Activity 的 Compose 内存状态中，尚未持久化为草稿；Android 进程被杀后，这些未保存状态会丢失。主 Activity 声明 `orientation|screenSize|uiMode` 的 `configChanges`，因此旋转及系统深浅主题切换沿当前 Activity 保留内存状态；这不构成进程死亡恢复保证。课表一旦确认保存，仍由 app 私有文件持久化。

## 提醒和小组件

用户开启提醒后，`ReminderScheduler` 只滚动安排下一条 `setExactAndAllowWhileIdle` 精确闹钟。Android 12/API 31–32 若没有 `SCHEDULE_EXACT_ALARM` 会返回未能安排；API 33+ 声明 `USE_EXACT_ALARM`。通知发送按课程 occurrence key 去重。开机、系统时间/时区变化、升级和精确闹钟授权广播会重排；时钟变更先尝试投递最近五分钟内到期课程，再重排。

今日与下一节课使用 Glance；组件显示更新时间、今日当前课程或下一节日期时间，提供手动刷新。`WidgetRefreshScheduler` 使用普通非精确 `AlarmManager.set` 安排下一次上课、下课或学期时区午夜，不要求精确闹钟权限。Android 省电可能延迟非精确 widget 更新；ColorOS 表现尚待目标设备验收。

## 隐私与配色

最终 APK Manifest 已审计无联网权限，ORT 自动遥测 Provider 已移除并显式 setTelemetry(false)，OCR 模型随 APK 本地加载，无 GMS 或模型下载。二维码和文件交换不启动网络；默认关闭的大模型只保留设计接口，没有联网客户端。系统文件选择器的目标提供者由用户选择，云盘等第三方服务的网络行为不由本 App 控制。

深色 One Dark refined 色板来源为 `aspects/appearance/appearance/onedark.nix`；浅色主题使用暖灰底和深色文字。小组件按系统 `uiMode` 选择深浅色。没有远程字体或广告；ORT 随带的遥测初始化被禁用。

## 第二阶段验证记录与后续

- `nix develop .#android`、23 项 core 单测、Debug/Release assemble、Android lint（0 errors/29 warnings）通过。Release 已本地签名，两个 APK 的签名和离线清单审计通过，release 实装冷启动成功。
- 最终 API35 AOSP、1280 MiB 实际 RAM 上，六项 UI/文件/二维码/照片/截图测试通过；独立 host handshake 提醒测试也通过。照片两主题经真实随包 OCR、逐格修改并确认后保存；Glance 真实 RemoteViews 深浅截图已完成。
- 47 张运行截图与两轮复核记录在外部产物 `shots/gallery.html`、`overview.png`；源码的 HTML 仍是第一阶段静态原型。
- OPPO/ColorOS 真机、物理相机与跨设备二维码、其他 Android 版本、Doze/重启/时区完整矩阵仍待目标设备验收。未来 LAN 与大模型网络能力没有实现。

历史信息：第一阶段 SDK 许可尚未获得，因此当时 app 未编译；这一描述只适用于第一阶段，不代表当前状态。技术参考：[AGP 8.10](https://developer.android.com/build/releases/agp-8-10-0-release-notes)、[Glance widget](https://developer.android.com/develop/ui/compose/glance/create-app-widget)、[Android Photo Picker](https://developer.android.com/training/data-storage/shared/photo-picker)。
