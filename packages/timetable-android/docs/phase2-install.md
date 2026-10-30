# Android 第二阶段：构建与安装

SDK 许可于 2026-10-30 获得用户同意。以下证据来自 `/home/mayon/nix-dotfiles/.work/r50/android/run/phase2/` 和 APK 审计日志；它们证明 API 35 AOSP 模拟器与二进制构建情况，不等同 OPPO / ColorOS 实机验收。

## 构建与验收

在仓库根目录进入 Android 开发 shell：

```sh
nix develop .#android
```

由受控脚本运行 Gradle：

```sh
packages/timetable-android/tools/android-gradle.sh assembleDebug test assembleRelease
packages/timetable-android/tools/sign-release.sh
```

`android-gradle.sh` 使用隔离 Android/Gradle cache、启用 Android 工程参数，并用 `/home/mayon/nix-dotfiles/.work/r50/heavy.lock` 串行化重型构建。签名脚本必须在 `nix develop .#android` shell 内运行：它以 `zipalign` 对齐 release APK，从本地受限权限文件读取口令签名，再运行 `apksigner verify`，最后将 APK 复制到交付目录。

当前 APK：

| 类型 | 路径 |
|---|---|
| 推荐侧载 release | `/home/mayon/nix-dotfiles/.work/r50/android/apk/timetable-mayon-0.2.0-release.apk` |
| Debug 验证版 | `/home/mayon/nix-dotfiles/.work/r50/android/apk/timetable-mayon-0.2.0-debug.apk` |

最终签名日志和 APK 审计日志确认 release 使用 RSA-3072，并通过 APK Signature Scheme v3 验证；debug 与 release 均为 `dev.mayon.timetable` / 版本 `0.2.0`，目标 API 35、最低 API 29。审计还确认 APK 无 INTERNET 权限且不含 ORT telemetry initializer。最终 SHA-256：

```text
debug   c99b25cc8b0442c6edf06417ab62a01f683d5a51c9833a59a43043731a6bb14a
release 701bf884ea16530b9c3cd083963f8c7caf1c0f4e3c8f72b80a85acd40df197e1
```

release 安装建议使用签名 release；debug 使用不同签名证书，不能直接覆盖 release 安装。

测试证据：

- `core` 共 23 项 JVM 测试通过。
- `instrumentation-delivery.log` 显示 Android 仪器测试 6/6 通过，含照片流程、外部 WakeUp/QR 导入和深浅主题截图场景。
- Lint 0 errors、29 warnings；警告主要为依赖更新与 KTX 建议。
- API 35 AOSP 无头模拟器已用于上述 UI 测试。8 个主要界面有深浅主题截图；当前图集为 `/home/mayon/nix-dotfiles/.work/r50/android/shots/gallery.html`，总览 `/home/mayon/nix-dotfiles/.work/r50/android/shots/overview.png`。Glance RemoteViews 深浅主题截图来自应用内 `WidgetHostActivity`，不是 OPPO Launcher 实机截图。

`reminder-instrumentation.log` 记录 API 35 AOSP 模拟器上一次真实 AlarmManager 仪器测试通过：同一测试运行期间 ADB 将模拟器时间调至提醒前 6 秒，观察到一条通知（最终记录见 alarm-delivered.txt）；复现步骤见 [reminders.md](reminders.md)。这不是完整的 Android 版本/Doze 矩阵。最终实际 RAM 1280 MiB 的虚拟机完成全部六项 UI/导入测试及独立提醒测试，宿主 RSS 每秒采样峰值 2790.09 MiB；模拟器和专用 adb 已关闭，临时 AVD 已删除，SDK 留在 store。没有在用户 OPPO 手机上安装或验证，AOSP 结果不能推断 ColorOS 菜单与后台行为。

## Release keystore 与备份

本地签名文件位于：

```text
~/.local/share/timetable-android/keystore
~/.local/share/timetable-android/keystore.password
```

签名脚本要求两个文件均为 `0600`；它们不入库、不进入 Nix store，也不应放进 APK、构建命令参数、日志或同步盘。请离线备份 keystore 和口令；建议分别存放在安全的离线位置。若丢失密钥或口令，将无法以同一签名覆盖安装更新。文档不包含口令或私钥内容。

## 安装到 OPPO 手机

优先安装已签名的 release APK。打开 `nix develop .#android`，用 USB 调试安装：

```sh
adb devices
adb install -r /home/mayon/nix-dotfiles/.work/r50/android/apk/timetable-mayon-0.2.0-release.apk
```

首次连接时在手机上确认 USB 调试授权。若设备未列出，检查 USB 数据模式、数据线和开发者选项中的 USB 调试。

也可直接传 APK 到手机下载目录，再用系统文件管理器安装：

```sh
adb push /home/mayon/nix-dotfiles/.work/r50/android/apk/timetable-mayon-0.2.0-release.apk /sdcard/Download/timetable-mayon.apk
```

在 OPPO 文件管理器中打开 `Download/timetable-mayon.apk`。系统提示来源不允许时，进入“设置 > 安全与隐私/更多安全与隐私 > 安装来源/安装未知应用”，允许启动安装器的来源（通常是文件管理器或浏览器），返回继续安装。ColorOS 菜单名称依版本变化；可在设置搜索“安装未知应用”或“安装来源”。安装后可关闭该来源授权。路径参考 [ColorOS 说明](coloros.md)。

**不要用 Debug APK 覆盖 Release APK，或用 Release 覆盖 Debug APK**：两者签名不同，Android 会拒绝更新。如果手机当前安装了另一签名版本，先在 App 内导出课表并确认备份可读，再卸载旧版并安装目标版本；卸载会删除 app 私有课表数据。

## 运行期

课表保存、PP-OCRv4 识别、照片处理、二维码分片和文件交换在本机执行，不依赖 GMS。允许通知后才能看到提醒；Android 12/12L 还需允许精确闹钟访问。ColorOS 自启动/电池设置见 [ColorOS 说明](coloros.md)。App 没有在用户手机实测；首次安装后请先导入或创建学期，并核对提醒、通知和桌面组件表现。
