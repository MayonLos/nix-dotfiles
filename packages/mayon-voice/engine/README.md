# ASR 与可选文本润色 worker

`worker.py` 通过 JSON Lines 和 Rust daemon 通信。它启动后保留单个 sherpa recognizer；模型只在收到第一条非静音音频时加载，worker 自己不会联网或下载模型。daemon 可直接用 CLI 初始化，也可用 JSON 首行配置，基准脚本使用后者。

直接启动：

```sh
python3 /path/to/mayon-voice/engine/worker.py --engine sensevoice \
  --model-dir ~/.local/share/mayon-voice/models/sensevoice-small-int8 \
  --provider cpu --threads 4
```

首条可选配置行：

```json
{"config":{"engine":"sensevoice","model_dir":"/home/user/.local/share/mayon-voice/models/sensevoice-small-int8","provider":"cpu","num_threads":4,"language":"auto","use_itn":true,"hotwords":["NixOS","Neovim"]}}
```

每段音频一行：

```json
{"wav":"/run/user/1000/mayon-voice/current.wav","hotwords":["NixOS","Neovim"]}
```

输入必须是单声道、16 kHz、PCM16 WAV；worker 不重采样。它用 WebRTC VAD 模式2和30 ms帧检测语音，裁掉长静音边界并保留语流里的停顿；没有 `webrtcvad` 时明确返回 error，不回退成能量阈值。全静音返回 `text:""`、`error:null`，不加载模型。识别结果包含 `elapsed_ms`、`cpu_ms`、`rss_peak_kb`、`speech_ratio` 和 `warnings`。离线 sherpa API 不输出部分文本，因而端到端“首字延迟”要等录音结束后才产生。

## 引擎与热词

- 默认 `sensevoice`：`model_dir` 下需要 `model.int8.onnx` 与 `tokens.txt`。支持普通话、粤语、英语、日语、韩语，并可启用 `use_itn`。CPU 是默认 provider；当前 nixpkgs CPU-only binding 对任何非 CPU provider 显式返回错误，不会暗中切到其他设备。
- `paraformer`：需要 `model.int8.onnx` 与 `tokens.txt`。支持中文，适合较低 warm latency。
- `whisper-cli`：设置 `--model /path/to/ggml-model.bin`，可用 `--whisper-binary` 指定 `whisper-cli` 路径；CPU 调用固定加 `-ng`。用户显式选 `provider:"cuda"` 时不加 `-ng`，仅在目标进程 stderr 含上游 v1.8.4 的 `whisper_backend_init_gpu: using CUDA` 后端日志才接受结果；没有这条日志就报错，不悄悄回退 CPU。此路径需要用户另行提供 CUDA-enabled 的 whisper.cpp 二进制，仓库没有构建或捆绑它。`hotwords` 作为 `--prompt` 提示上下文传给 Whisper，效果不保证。
- sherpa-onnx v1.12.38 `from_sense_voice()` 和 `from_paraformer()` 工厂均没有 hotwords 参数。通用 hotword 配置只接入要求 `modified_beam_search` 的兼容 decoder；这两个 factory 使用 greedy decode。因此它们忽略用户热词并在响应中发出 warning，不会声称热词生效。

模型需用户明确调用 `mayon-voice models fetch`。内部脚本接口：

```sh
python3 models.py --engine sensevoice --model-dir ~/.local/share/mayon-voice/models/sensevoice-small-int8
python3 models.py --engine paraformer --model-dir ~/.local/share/mayon-voice/models/paraformer-zh-small
```

脚本固定下载 sherpa-onnx GitHub Releases 上的 SenseVoice int8 归档（163,002,883 bytes，SHA-256 `7d1efa2138a65b0b488df37f8b89e3d91a60676e416f515b952358d83dfd347e`）或 Paraformer zh-small int8 归档（77,920,048 bytes，SHA-256 `da92b3db5218c5be53aad53e57d1b6e63e7fc98a0e054fbdd6dbe18e9c6b1450`）。只有哈希匹配才解包；临时文件在目标目录同一文件系统，安装通过原子重命名完成。遇到已有目标会拒绝覆盖。模型源文件进入用户数据目录且权限为目录 `0700`、文件 `0600`，不经过 Nix store。

## 润色 helper

`polish.py` 只在用户开启 DeepSeek 润色时由 daemon 单独启动。stdin JSON 为 `{"text":"...","key_file":"/run/.../deepseek-key","hotwords":[...]}`，stdout 返回 `{"text":"..."}`。它只访问 `https://api.deepseek.com/chat/completions`，密钥从 sops 运行时文件读取，HTTP 超时3秒；错误或空响应返回原始文本。helper 不记录请求、密钥或响应；daemon 还应有自己的3秒硬超时。

## 本地检查

```sh
python3 -m unittest discover -s . -p 'test_*.py'
```

Nix 包需提供 `python3.withPackages [ sherpa-onnx numpy webrtcvad setuptools ]`。当前 nixpkgs `webrtcvad` 模块导入 `pkg_resources`，故除了项目请求的三个包，还需要 setuptools；纯 Python env 和 sherpa binding 已在本机命中二进制缓存。
