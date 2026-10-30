# 照片课表 OCR 选型与基准

## 结论与设备约束

默认路线选择 PaddleOCR 的 PP-OCRv4 mobile 中文检测/识别模型，经 ONNX Runtime CPU 推理，模型和全部图片处理留在设备上。它不需要 Google Play 服务，也不需要网络。对 OPPO 国行无 GMS 手机适配直接；Compose App 阶段应将固定版本模型作为 app 私有资源或首装后由用户显式导入，完成后禁止后台下载。模型许可和 APK 体积需在第二阶段核实。

PP-OCRv5 mobile 是值得复测的升级候选，但当前基准通过 RapidOCR 1.x `rapidocr_onnxruntime` 包运行 PP-OCRv4 mobile；此 API 默认配置不暴露 PP-OCRv5。没有测出 v4/v5 的准确率对比，不能宣称 v5 实测优劣。第二阶段需用 RapidOCR 3.x 或显式 ONNX 图和预处理在 Android/JVM 上比较。这里的 PP-OCRv4 是可复现基线。

Google ML Kit Chinese **bundled** 依赖在官方 Android 文档中使用 `com.google.mlkit:text-recognition-chinese`，文档称 bundled 模型构建时静态链接进 App；`com.google.android.gms:play-services-mlkit-text-recognition-chinese` 则是 Play Services 动态安装路线。因此 bundled artifact 通过 `com.google.mlkit` 命名空间打包模型，不要求设备安装 Google Play Services APK 才能本地识别；这只说明模型分发和运行可本地完成。应用仍使用 Google ML Kit 客户端库。Google ML Kit 条款说明 API 会发送性能和使用指标，也可能联系 Google 获取兼容性及更新信息；本地图片处理不等于无统计。ML Kit 因而不进入默认发行依赖，只可在第二阶段做隔离对照，除非依赖审计证明可关闭遥测且满足隐私要求。它还依赖 Google ML Kit 运行库、增加安装体积，并非开源可自托管权重。官方文档没有为每种国行 ROM 给设备兼容承诺。

基于无广告、无统计、离线和可审计需求，推荐 PP-OCR ONNX 作为主引擎，ML Kit bundled 可作第二阶段的可选对照，不能作为唯一依赖。OCR 置信度只辅助黄色标记和人工校对，不自动承诺识别正确。任何云端大模型只能作为用户主动开启的显式上传选项，默认关闭。

## 合成数据和测量

`tools/ocr/generate.py` 固定随机种子生成 30 张完整课表图及逐格 ground truth。数据包含思源黑体、思源宋体、Maple Mono NF CN 三种字体，3 种低饱和教务表风格，清晰/低对比/轻微模糊/透视倾斜/低分辨率/阴影等变体，画布 1440×1000，课程表网格完整可见。每张含 30 个星期×节次格，occupied 与 empty 都计分；每第六张增加 3 个课程名、教师、教室、周次四行样本，并放入 1 个跨两节的视觉合并格。所有图均为程序合成，未使用真实用户课表。透视样本真值附单应矩阵，仅用于 oracle 诊断评分，不参与 raw 图片版面预测。

`tools/ocr/benchmark.py` 在每张原图上运行 RapidOCR/ONNX Runtime CPU。实际预测的版面映射从 OCR 检出的 `周一…周五` 表头 x 中心和 `第1节…第6节` 行标签 y 中心做线性拟合，预测不读真值网格坐标或透视矩阵。置信度低、表头/节次标签漏检时会导致真实可见的映射失败。评分分别报告非空格严格匹配、对应预测格有文字的比例、有预测内容格内的文字准确率、按启发式规则分类的“识别错/疑似错映射/漏检”、空格误报和全格准确率。这些分类不是有独立标注框支持的真实错误因果归因。另有 `oracleGeometryDiagnosticOnly` 诊断指标仅用于分析 OCR 能否读对已知格子内文本：它会用生成时的真值网格和透视矩阵，不能代表照片导入端到端表现。

预测 OCR 框、原文、置信度和由识别表头推导出的格子编号输出为 `ocr-boxes.json`，可供 core 版面算法回放。完整逐样本结果、模型 SHA-256 和计时写入 `summary.json`。大多数格为单行课程名。富字段组对 60 个字段字符串分类型计算位置无关的文字精确匹配率（summary 键为 `richFieldStringRecognitionAnywhereInImage`）；它只表示完整字符串是否在图内被识别，不能解释为字段提取或落格准确率。5 张中的合并课程块另报告位置无关的课程文字精确率，但没有量化合并边界重建准确度。

### 本次实测（PP-OCRv4 mobile）

30 张、900 格的合成图中有 460 个非空格和 440 个空格；每图识别到全部 5 个星期表头与 6 个节次标签，30/30 张成功建立预测网格。

- 从原图 OCR 表头推导版面：非空格 423/460 严格正确（91.96%），空格 421/440 正确、19 个误报，全格准确率 844/900（93.78%）。非空格有预测内容的比例 446/460（96.96%），这些格的文字严格匹配率 94.84%。`occupiedDetectionRecall` 是历史指标键名，实际衡量对应预测格是否有文字，不是经独立检测框 IoU 标注计算的 OCR 检测召回率。
- 使用合成数据真值网格和透视矩阵的诊断上限：非空格 453/460 正确（98.48%），空格 440/440 正确，全格 893/900（99.22%）。这只是识字上限，不能当作照片导入预测准确率。
- 错误拆分启发式：raw 版面组报告 23 个格内内容不匹配、14 个疑似映射错误、19 个空格误报；真值网格诊断有 2 个格内内容不匹配和 5 个疑似映射错误。因为缺少真实拍摄的独立检测/布局标注，这些类别是诊断分类，不是严格错误因果结论。
- 每六张中一张的富字段样本：位置无关的字符串识别为课程 15/15、教师 13/15、教室 14/15、周次 13/15；5 个视觉合并块课程文字 5/5。它们没有证明字段分类/落格或合并边界重建准确率。
- ONNX Runtime 1.31.1，RapidOCR 1.4.4，NumPy 2.5.4，Pillow 11.3.0，OpenCV 5.0.0.93；ORT 配置 intra-op 2 / inter-op 1。均值 1.055 秒/张，总推理 31.65 秒，含模型加载和评分的进程墙钟 32.01 秒，峰值 RSS 410 MiB。模型文件总大小约 15.44 MiB（det 4.53 MiB、cls 0.56 MiB、rec 10.35 MiB）。三个模型文件哈希记录于 `summary.json`。

合成数据只代表已覆盖的程序印刷体表格，不代表实拍真实教务系统、手写内容、字段分类或复杂合并单元格的泛化表现。

### 复现

模型、虚拟环境和测量输出均放在仓库外的 `.work/r50/android/run/ocr/`；该目录不纳入源码提交。Runtime 使用 ONNX Runtime 2 个 intra-op 线程、1 个 inter-op 线程；峰值 RSS、实耗总时间、模型文件大小/hash 与库版本写入 `summary.json`。安装需要 Python、Pillow、NumPy、opencv-python-headless、ONNX Runtime 和 RapidOCR。NixOS Python wheel 环境可能需要 `LD_LIBRARY_PATH` 指向 nixpkgs GCC `libstdc++.so.6`。`tools/ocr/requirements.txt` 保存本次隔离环境的完整版本快照；用 `--no-deps -r` 安装全部固定项，避免 RapidOCR 的元数据额外安装带 GUI 的 OpenCV。未另建第二个空环境重复安装。

```sh
# tools/ocr/requirements.txt is the actual isolated venv version snapshot.
# Install its complete pins with --no-deps to avoid pulling the GUI OpenCV wheel.
python tools/ocr/generate.py --out "$OUT/dataset" --count 30
python tools/ocr/benchmark.py --data "$OUT/dataset" --out "$OUT/ppocrv4"
```

重型安装、模型下载和推理应串行持有 `/home/mayon/nix-dotfiles/.work/r50/heavy.lock`，并使用独立 `HOME`、`XDG_CACHE_HOME` 与 `env -i`。报告记载的模型版本、哈希与耗时以实跑产物为准。

## 模型来源

- RapidOCR 官方文档模型表：<https://github.com/RapidAI/RapidOCRDocs/blob/main/docs/model_list.md>，列出 PP-OCRv4 中文 mobile 支持 ONNX Runtime，并列出 PP-OCRv5 的 ONNX Runtime 适配。模型仓库地址、官方 SHA-256 见 RapidOCR `default_models.yaml`：

当前安装的 `rapidocr_onnxruntime==1.4.4` wheel 内置 PP-OCRv4 文件哈希与 RapidOCR 发布表匹配：det `d2a7720d45a54257208b1e13e36a8479894cb74155a5efe29462512d42f49da9`；rec `48fc40f24f6d2a207a2b1091d3437eb3cc3eb6b676dc3ef9c37384005483683b`；cls `e47acedf663230f8863ff1ab0e64dd2d82b838fceb5957146dab185a89d6215c`。

RapidOCR `default_models.yaml`：<https://github.com/RapidAI/RapidOCR/blob/main/python/rapidocr/default_models.yaml>。
- ML Kit Android Text Recognition v2：<https://developers.google.com/ml-kit/vision/text-recognition/v2/android>。官方表格说明 bundled artifact 是 `com.google.mlkit:text-recognition-chinese`，而 Play Services artifact 的坐标以 `com.google.android.gms` 开头。
- ML Kit 迁移说明：<https://developers.google.com/ml-kit/migration/android>。官方区分 `com.google.android.gms` Play Services 库和 `com.google.mlkit` bundled 库。
- ML Kit 模型安装路径：<https://developers.google.com/ml-kit/tips/installation-paths>。bundled 模型静态随应用分发，unbundled 由 Google Play Services 下载；后者不适合本设备约束。
- Google ML Kit 服务条款与隐私说明：<https://developers.google.com/ml-kit/terms>。其中说明会收集性能、使用指标，也可能联系 Google 获取兼容性及更新信息；因此不能仅凭图像在本地处理推断为零统计。

## 模型与再分发许可

RapidOCR 仓库将引擎代码标为 Apache-2.0，并声明其 PaddleOCR 派生权重和 ONNX 转换模型适用 Apache-2.0；PaddleOCR 仓库也标为 Apache-2.0。ONNX Runtime 使用 MIT。当前基准安装的 RapidOCR 1.4.4 wheel 内置模型哈希与 RapidOCR 发布模型表相符，但该 wheel 不随模型单独附带逐模型许可证与 NOTICE。将模型打入 APK 前应随应用附 Apache-2.0 文本、RapidOCR/PaddleOCR/Baidu 署名与模型来源/hash 说明，并审核最终 APK 依赖/NOTICE；这里没有实际导出或分发模型文件。

- RapidOCR 许可与模型来源说明：<https://github.com/RapidAI/RapidOCR/blob/main/LICENSE>、<https://github.com/RapidAI/RapidOCR/blob/main/README.md>。README 说明权重来源归上游 PaddleOCR 权利人，当前采用的 Apache-2.0 条款和模型转换归属。
- PaddleOCR 项目许可证：<https://github.com/PaddlePaddle/PaddleOCR>。
- ONNX Runtime Java 许可证声明：<https://github.com/microsoft/onnxruntime/blob/main/java/build.gradle>。
