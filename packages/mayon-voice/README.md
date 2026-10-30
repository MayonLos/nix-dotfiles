# mayon-voice

本地中文语音输入。Rust 管理 socket activation、PipeWire 录音、状态通知、焦点保护、
上屏及空闲退出；Python 只承载 sherpa-onnx 官方绑定及可选 DeepSeek HTTP 调用。
这避开自建 ONNX/CUDA FFI；默认使用 nixpkgs CPU 构建，不加载 CUDA、不探测 NVIDIA。
公开包工厂：`default.nix { pkgs }`；公开输出 `pkgs.mayonVoice` 和
`pkgs.mayonVoice.fcitxAddon`。共享 One Dark UI 通过 mayon-ui 的公开 path 依赖复用。

## 使用

先由主代理选择 `voice-input` aspect，应用并刷新图形会话后使用：

```sh
mayon-voice models fetch  # 显式联网获取校验哈希的模型；识别不自动下载
mayon-voice start
mayon-voice stop
mayon-voice toggle
mayon-voice status       # JSON；不包含转写正文
mayon-voice ui           # 中文状态界面；空格录音、1/2 切页、? 帮助、/ 过滤、q 退出
mayon-voice config       # 输出默认 TOML，用户自行保存修改
```

`start`/`stop` 幂等；识别期间不允许开始第二次录音。录音最长默认 120 秒（可设 1–600），
单次识别最长等待 120 秒，超时释放引擎并报错。默认输入设备由 PipeWire 选择，16kHz/mono/PCM16；`input_device` 可设 PipeWire target 名称。
worker 用 WebRTC VAD 丢弃静音，SenseVoice/Paraformer 模型首次识别加载、后续复用，空闲 600 秒退出并释放模型。
Whisper CLI 是兼容路径，每次识别新建进程并加载模型，不常驻复用；其 warm 指标最多
表示系统页缓存已热，不能与 sherpa 的驻留模型等同。
非流式模型的首字与整句同时返回，必须把首字延迟按“停止录音至整句返回”理解，
不能宣称流式首字延迟。`status` 查询不延长空闲计时；socket 自身随图形 target 安装。

服务不启动于登录，只有 socket 监听；首次命令激活服务。通知显示录音、识别和结果状态，
不显示正文。当前采用通知，没有新增 layer-shell 浮标或实时音量条。TUI 为可选查看器，
关闭查看器不会取消录音；通知与 CLI 状态仍工作。

## 配置及状态

没有配置文件使用默认值。`~/.config/mayon-voice/config.toml` 完全归用户写入；HM 不生成，
不 activation patch；建议目录 `0700`、文件 `0600`。修改在下次服务启动读取。
可从 `mayon-voice config` 生成与当前用户 XDG 路径匹配的默认配置。示例：

```toml
engine = "sensevoice"
model_dir = "/home/mayon/.local/share/mayon-voice/models/sensevoice"
device = "cpu"
threads = 4
input_device = "auto"
delivery = "auto"
hotwords = ["NixOS", "Rust", "线性代数"]
idle_seconds = 600
max_record_seconds = 120
polish = false
key_file = "/run/secrets/deepseek-api-key"
```

`engine`、模型文件布局和可用 backend 见 [engine/README.md](engine/README.md)。
CPU 默认不请求 CUDA。可选 GPU 限于 Whisper CLI：设置 `engine = "whisper-cli"`、
`device = "cuda"`、`model_file = "/path/to/ggml-model.bin"` 与
`whisper_binary = "/path/to/cuda-whisper-cli"`；只有 stderr 确认选中 CUDA backend 才接受结果。
用户需另行提供已带 CUDA 的 CLI，本包不从源码编译 CUDA 或自动安装大型 GPU runtime。
该可选路径只有参数/日志判定测试，没有 GPU 硬件实测。热词配置是否可用于 decoder
取决于引擎；不支持的引擎会明确说明，不能用强制替换冒充识别 hotword。

模型保留在 `$XDG_DATA_HOME/mayon-voice/models`（默认 `~/.local/share/…`），显式下载校验
固定 SHA256、私有临时文件、完成后移动；不会在日常录音中联网。
用户拥有模型与下载缓存。选择运行时下载而非 Nix fetchurl 是为了让大模型不进入每代
system closure、避免未选择 feature 就拉模型；代价是包构建不证明模型存在，首次需下载。

录音只暂存 `$XDG_RUNTIME_DIR/mayon-voice/capture-*.wav`：目录 `0700`，音频 `0600`，
成功、失败或结束录音时删除。服务启动会清理自身 runtime 的旧录音；未完成录音在
进程异常退出后可能残留到下次启动或 runtime 清理。不写录音/转写历史、正文日志。
Whisper CLI 的 VAD 中间音频同样位于该私有 runtime 的 `whisper-*` 临时目录，
正常完成自动清理，异常残留在下次服务启动清理。control socket `0600`，只有同一 UID 可连接。没有遥测或后台网络请求。

## 上屏与隐私

[Fcitx addon](fcitx/) 在 Fcitx 主循环中调用 `InputContext::commitString`，适用于
支持 Fcitx 的 Wayland/XIM/GTK/Qt frontend。开录捕获焦点 token，提交要求同一 input
context 仍是 Fcitx 最近聚焦对象且不是密码框。应用禁用 IME、错误的 GTK/Qt/XMODIFIERS 环境、未加载
addon 或焦点改变均可能导致拒绝。未使用剪贴板传递 Fcitx 正常路径正文。

`delivery = "auto"` 优先 Fcitx，失败自动复制到 Wayland 剪贴板并通知手动粘贴；
不猜测终端和 GUI 的粘贴键。此回退会替换现有剪贴板，可能被已有剪贴板历史记录，
不尝试读取或恢复原内容；需要避免复制时用 `delivery = "fcitx"`（失败直接报错）。
`clipboard` 总是复制，`wtype` 是用户显式选择的 virtual-keyboard 路径，
发送首键前等待 150ms，让客户端处理新 virtual keyboard 的初始化，避免测试中出现的首字符丢失。

wtype 成功退出不能证明应用收到了文字，尤其 XWayland；因此不能作为自动成功判据，
也不在其后自动复制/粘贴重复文本。没有能保证“所有程序”的通用上屏协议：Fcitx 正常
注册的应用可直接提交，其余依赖手动粘贴。真实 QQ/微信还需应用后现场核验。

## 可选润色

`polish = true` 才向固定 `https://api.deepseek.com/chat/completions` 发送当前句子及热词。
这会使文本离开设备；录音始终不上传。密钥只通过 `key_file` 运行时文件读取，
沿用 inventory 的 sops secret owner/mode（不修改既有秘密声明）。不从环境获取 token，
不在 Nix、store、命令参数、通知或日志包含 key。主进程以 3 秒 deadline 约束 helper，
超时、认证失败或响应异常均返回原文；默认关闭。没有读取真实凭据做联网验证。

## 开发与验证

独立 Cargo workspace 和 `Cargo.lock`，依赖共享 UI 但不改共享源码。

```sh
CARGO_BUILD_JOBS=6 cargo test --locked
CARGO_BUILD_JOBS=6 cargo clippy --locked --all-targets -- -D warnings
cargo fmt --all --check
python3 engine/test_worker.py
python3 tests/daemon.py target/debug/mayon-voice
```

进程测试只用私有 runtime 与替身录音/引擎，不连接真实 PipeWire、Fcitx 或桌面。
包含命令幂等、识别期间拒绝重复录音、权限与删除、空闲释放、真实 fd3 传递。
实测基准与隔离桌面证据留在本轮 `.work/r50/voice/`，不等于应用配置或真实麦克风验收。
