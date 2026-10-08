# 本地模型

`modules/home/programs/dev/llama-cpp.nix` 管理用户级 llama.cpp CUDA 服务，
`pkgs/llama-cpp.nix` 只编译本机 RTX 4060 的 CUDA 内核（计算能力 8.9 / SM89）。
权重在 `~/.local/share/llama-cpp/models/`，不进入 Nix store。
下载使用 `lib/local-models.nix` 中固定 revision 的 URL，断点续传，校验 SHA-256 后才改成 `.gguf`。

| 模型 ID | 用途 | 上下文配置 |
|---|---|---|
| `qwen2.5-coder-7b` | 代码任务 | 8192 |
| `qwen3.5-9b` | 更大通用模型 | 8192 |

两款都是 Q4_K_M，总文件大小约 9.65 GiB。4B 已完成 GPU 推理测试并删除。Router 按请求加载，最多同时加载一个模型；
未下载完成的模型无法加载。模型文件大小不等于运行时显存占用。
接口和 Web UI 在 <http://127.0.0.1:8080>，未开放防火墙或监听局域网地址。

```sh
systemctl --user status llama-cpp llama-models-download
journalctl --user -fu llama-models-download
journalctl --user -fu llama-cpp
du -h ~/.local/share/llama-cpp/models/*
curl -s http://127.0.0.1:8080/v1/models
pi-local --model qwen2.5-coder-7b
```

Neovim 的 `<leader>al` 打开本地 CodeCompanion chat，默认用 7B 编码模型。
要使用 9B，运行 `:CodeCompanionChat adapter=llama.cpp model=qwen3.5-9b`。
`:CodeCompanionCLI agent=pi_local` 打开本地 Pi；`agent=pi` 使用 Pi 原有 provider。
现有 Copilot chat、DeepSeek inline 和 Codex CLI 默认配置保留。

`pi-local` 显式加载由同一模型清单生成的 `llama-local` provider，默认选择 9B；
进入后可用 `/model` 选择其他模型。Router 自动加载、切换模型；输出上限为 2048 tokens。
该入口不修改 `auth.json` 或 `models.json`，常规 `pi` 保留所有原有 provider。
9B 已实测通过 Pi 调用 `read` 工具读取文件；7B 聊天正常，但两次只读工具测试
均未实际调用工具，因此将 7B 用于 CodeCompanion 聊天，9B 用作 Pi 默认。

锁定的 Pi 1.0.0 原生 `llama.cpp` provider 在启动时依赖已保存的连接及缓存目录，
而 b9190 router 未提供其自动发现未加载模型所需的 `source` 字段，可能导致 CLI 找不到模型
或继承错误的模型元数据。此入口使用声明式模型目录绕过该版本组合的发现问题；
普通 Pi 的 `/login llama.cpp` 和 `/llama` 仍可用于手动连接、加载已存在的模型。
本地推理不需要订阅或云端 API key；使用现有云端 provider 时，仍按其账号规则计费。
两款模型配置 8K 上下文；Pi 固定预留 4K tokens，因此不要将服务降为 4K 后继续用于 Pi。
上下文适合小任务；Pi 的完整项目上下文可能超出限制。

暂停推理用 `systemctl --user stop llama-cpp`；恢复用 `systemctl --user start llama-cpp`。
暂停下载用 `systemctl --user stop llama-models-download`，恢复用 `systemctl --user start llama-models-download`。
常规声明式部署仍随 NixOS 的 `nr` 应用，不单独执行 Home Manager switch。

上游资料：[llama.cpp b9190 server](https://github.com/ggml-org/llama.cpp/blob/b9190/tools/server/README.md)、
[Qwen3.5 9B GGUF](https://huggingface.co/unsloth/Qwen3.5-9B-GGUF)、
[Qwen2.5 Coder 7B GGUF](https://huggingface.co/bartowski/Qwen2.5-Coder-7B-Instruct-GGUF)。
