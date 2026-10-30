# 课表 · Mayon（Android）

面向国行无 GMS OPPO 的本地课表。Android SDK 许可已于 2026-10-30 获得用户同意，Nix 开发 shell、APK 构建和模拟器 UI/导入验证已经完成。App 最终清单无联网权限，已移除 ORT 自动遥测并显式关闭其统计；课表、图片识别、二维码互传均在本机处理。

## 文档与契约

- [JSON v1 格式](docs/format.md)：与电脑端 `study-mayon` 的数据交换契约。
- [架构与设计](docs/architecture.md)、[WakeUp 导入依据](docs/wakeup.md)。
- [OCR 参考基准](docs/ocr.md)、[Android OCR 实现说明](docs/ocr-android.md)。
- [离线二维码协议](docs/qr.md)、[局域网同步草案](docs/sync.md)。
- [提醒与 Glance 小组件](docs/reminders.md)、[ColorOS 说明](docs/coloros.md)。
- [第二阶段构建与安装步骤](docs/phase2-install.md)、[默认关闭的大模型接口](docs/llm-fallback.md)。
- [HTML 原型](prototype/index.html)：1080×2400 图片是静态原型截图，不是 Android 页面。

## 当前实现状态

| 区域 | 状态与证据 |
|---|---|
| `core` | 纯 JVM 模型、周次、JSON、WakeUp、ICS、照片版面和 QR 传输 codec；第二阶段 core 共 23 项测试通过。 |
| Android app | Kotlin/Compose 工程已编译；仪器测试 6 项全通过，覆盖照片导入主题变体、外部 WakeUp/QR 导入和主要页面截图。Lint 0 错误、29 条警告（以依赖更新/KTX 建议为主）。 |
| OCR / 照片 | 随包 PP-OCRv4 ONNX；真实 Android fixture 在深浅主题均完成离线识别、逐格人工确认和保存。没有将 Python 的 900 格 93.78% 参考准确率计作移动端准确率；复杂布局仍需人工复核。最终 1280 MiB 虚拟机复跑通过，宿主 RSS 采样峰值 2790.09 MiB。 |
| QR | ZXing 分享分帧、系统图片多选识别并导入通过仪器测试；未据此宣称两台真实设备间已完成互传验收。 |
| 提醒 / widget | API 35 AOSP 模拟器的一次真实 AlarmManager 仪器测试通过并观察到一条通知；`WidgetHostActivity` 挂载真实 Glance RemoteViews 的深浅主题渲染已复核。它们不是 ColorOS/OPPO 桌面实测。 |
| UI 测试与截图 | API 35 AOSP 无头模拟器 6 项仪器测试通过；8 个主要界面有深浅主题截图，另有 reminder/widget 截图。gallery 为 `/home/mayon/nix-dotfiles/.work/r50/android/shots/gallery.html`，总览为 `overview.png`。 |

Debug 和 release APK 已复制到 `/home/mayon/nix-dotfiles/.work/r50/android/apk/`。Release 使用本地 RSA-3072 密钥并通过 APK Signature Scheme v3 验证。最终 SHA-256：Debug `c99b25cc8b0442c6edf06417ab62a01f683d5a51c9833a59a43043731a6bb14a`；Release `701bf884ea16530b9c3cd083963f8c7caf1c0f4e3c8f72b80a85acd40df197e1`。尚未在用户 OPPO 手机上安装或测试。

## 构建

Android shell：

```sh
nix develop .#android
```

通过受控脚本构建（脚本使用隔离 `env -i`、独立 Gradle HOME，并以共享 `flock` 串行化重型任务）：

```sh
packages/timetable-android/tools/android-gradle.sh assembleDebug
packages/timetable-android/tools/android-gradle.sh test
packages/timetable-android/tools/android-gradle.sh assembleRelease
packages/timetable-android/tools/sign-release.sh
```

签名脚本需在 `nix develop .#android` 环境中执行；它从本地 `0600` 口令文件读取口令，不把秘密放入参数或日志。APK 路径、签名信息和手机安装步骤见 [phase2-install.md](docs/phase2-install.md)。提醒复现方式和 Glance 模拟器限制见 [reminders.md](docs/reminders.md)。工具首次解析 Android Gradle Plugin/Maven 依赖或 Nix SDK 闭包时需要下载开发工具；运行期 App 不联网。

## 文件与数据边界

运行日志、SDK 外临时数据与截图放在 `.work/r50/android/{run,shots}/`，APK 交付件放 `.work/r50/android/apk/`；模拟器 gallery 为 `/home/mayon/nix-dotfiles/.work/r50/android/shots/gallery.html`，总览为 `overview.png`。本仓库只拥有工程源码、规范、人工合成 fixture 和原型，不拥有用户已有 WakeUp 数据、相册或电脑端工程。安装后的课表保存在 Android app 私有 `files/semesters/<id>.json`，卸载会由系统移除私有数据；卸载前请通过 App 导出重要课表。release keystore 不入库、不进 Nix store，路径、备份和安装步骤见安装说明。
