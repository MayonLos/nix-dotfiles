# Android 离线 OCR 引擎

`PaddleOcrEngine(context)` 实现 `OfflineOcrEngine`，使用 APK 内的 PP-OCRv4 中文 mobile detector 和 recognizer，通过 `com.microsoft.onnxruntime:onnxruntime-android` CPU session 执行。它不请求网络、不发送统计，也不访问 Google Play 服务。OCR 结果的坐标相对传入的已校正 `Bitmap`；EXIF 方向和照片选择由调用端负责。

## 离线防护

ONNX Runtime 1.31.1 AAR 自带 HTTP 遥测 ContentProvider 和联网权限。App 通过 Manifest merger `tools:node="remove"` 删除 `TelemetryInitializer`、`INTERNET` 和 `ACCESS_NETWORK_STATE`，在创建 OrtEnvironment 时显式 `setTelemetry(false)`；发行前用 `tools/verify-apk.sh` 审计最终 APK。只检查源 Manifest 或只关闭 native telemetry 均不足以封住自动 Provider。参见 [ORT 1.31.1 Java API](https://github.com/microsoft/onnxruntime/blob/v1.31.1/java/src/main/java/ai/onnxruntime/OrtEnvironment.java)。第三方原生二进制未作完整安全审计。

## 推理流程

1. 限制输入为最长边 4096 px、最多 12 MP，然后将 detector 输入限制到最长边 1536 px。短边优先按 RapidOCR PP-OCRv4 配置放大到 736 px，再为极宽/极高图片按比例缩小到最长边上限；尺寸取 32 的倍数。通道按 BGR、`(pixel / 255 - 0.5) / 0.5` 归一化。
2. 运行 detector ONNX。对概率图执行 0.30 DB 阈值、8 邻域连通组件提取，以组件平均概率作为检测 confidence；小于 3 个概率像素或平均分低于 0.50 的组件丢弃。每张图至多保留 300 个框。
3. 对组件外接矩形做受限扩边并裁剪原图文字区域。扩边保留文字周围背景，避免分割概率图直接裁断字符。
4. 每次只识别一个 crop：高度缩放到 48，按宽高比计算内容宽度，再补零到至少 320 px（最多 1280 px），使用同一 BGR 归一化后输入 recognizer。输出通过 CTC argmax、blank 去除和重复 token 合并解码。字符顺序由模型 ONNX metadata 的 `character` 值导出到 `assets/ocr/keys.txt`，不是手工推测；blank 为索引 0，末尾追加空格。
5. 每个结果包含文本、输入图上的矩形四角坐标和置信度。置信度为 detector 组件分数与识别 token 平均 softmax 分数的几何平均，只用于校对界面提示，不代表字段级准确率。结果按 y、x 排序。

本实现不打包 PP-OCRv4 的可选方向分类器，照片方向由 EXIF 与用户四角校正负责。DB 后处理使用概率图连通组件与外接轴对齐框，并以 30% 框尺寸近似扩边；RapidOCR 桌面实现的 `minAreaRect`、多边形 unclip 和精确 box score 尚未复刻。因此旋转文字、彼此相连的文字行或复杂页面可能出现合并框/分框差异；调用方应提供尽可能裁紧且校正后的课表图，并让用户逐格校对。这里并未宣称 Android 推理与第一阶段 OpenCV 基准逐像素等价。

## 内存与生命周期

推理串行运行在 `Dispatchers.Default`。Detector 的 map 被限制在 2.5 MP；每次只保留一个 crop 和一个 recognizer tensor，最多 300 条结果，过宽 crop 限制到 1280 px。两个 session 在首次调用时从 APK assets 加载，保留到调用 `close()`；初始化与推理不得放主线程。调用方拥有传入的 Bitmap，本类不会释放它。

如果输入超过范围，方法抛出带用户可读信息的 `IllegalArgumentException`，应提示用户先裁剪。资源加载、ONNX 推理或模型/字典形状不匹配时抛出 `IllegalStateException`，调用端应显示可恢复的错误并允许重选照片。

## 随包资源与许可

| 文件 | 来源/用途 | SHA-256 |
| --- | --- | --- |
| `assets/ocr/det.onnx` | RapidOCR PP-OCRv4 mobile 中文检测模型 | `d2a7720d45a54257208b1e13e36a8479894cb74155a5efe29462512d42f49da9` |
| `assets/ocr/rec.onnx` | RapidOCR PP-OCRv4 mobile 中文识别模型 | `48fc40f24f6d2a207a2b1091d3437eb3cc3eb6b676dc3ef9c37384005483683b` |
| `assets/ocr/keys.txt` | 从 recognizer ONNX metadata `character` 字段提取 | `a1c84d9bdb9ab29043c58896224d32941783eb821629618416dcb08f12886492` |

模型来自第一阶段隔离 RapidOCR 1.4.4 环境中的 wheel，哈希与第一阶段 `summary.json` 已测模型匹配。模型、转换和字典按 Apache-2.0 随包附带 `assets/ocr/LICENSE-APACHE-2.0.txt` 与 NOTICE。RapidOCR 源码许可、模型来源与权属说明见 [RapidOCR LICENSE](https://github.com/RapidAI/RapidOCR/blob/main/LICENSE)、[RapidOCR default model manifest](https://github.com/RapidAI/RapidOCR/blob/main/python/rapidocr/default_models.yaml) 和 [PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR)。ONNX Runtime 单独使用 MIT 许可。

Android API 35 AOSP 模拟器上的照片仪器 fixture 已覆盖两个系统主题，并走完本地 OCR、逐格人工确认和保存课程流程；该结果是完整流程测试，不是 OCR 单元格准确率统计。首阶段 Python RapidOCR/OpenCV 参考实现的 900 格全格准确率为 93.78%（30 张合成图），不能当作 Android 移动端准确率。复杂或相连文字、旋转/模糊/低分辨率课表仍可能出现错误拆分或字段误识别；每格确认和人工复核仍是导入流程的一部分。Android 峰值 RSS 最终复测仍在进行，本文件不报告推测值。
