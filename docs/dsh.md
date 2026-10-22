# DeepSeek Harness 命令与桌面入口

2026-10-20。`aspects/ai-workbench/ai-agents.nix` 安装 `dsh` 命令与 `dsh-desktop`，两者调用同一个带 Node 兼容修正的锁定 DSH 0.2.0-rc.2。不需要 OpenCode CLI，也不通过 npm 临时下载另一份运行时。

## 使用

```sh
dsh --version
dsh --help
dsh headless --help
cd /path/to/project
dsh headless "分析当前项目并给出方案"
dsh headless --json "检查测试失败原因"
printf '%s\n' '总结当前目录的结构' | dsh headless
```

headless 每次处理一个任务，普通模式把最终答案写到 stdout、诊断与推理写到 stderr；`--json` 输出逐行 JSON 事件。工作目录是执行命令时的目录。任务可能调用工具修改文件，具体由任务和 Harness 权限策略决定。`--session-id` 继续已存在的会话，并非任意指定新会话 ID。

## 状态与模型

命令未收到有效 `DSH_HOME`（未设置、空串或纯空白）时，默认使用 `${XDG_DATA_HOME:-$HOME/.local/share}/dsh-desktop/harness`，与桌面启动器一致，不重新加载旧 `~/.dsh` 插件。显式设置有效 `DSH_HOME` 可隔离脚本或 CI：

```sh
DSH_HOME=/absolute/path/to/isolated-harness dsh headless --help
```

隔离目录需要自己的模型和凭据配置。不要把密钥写到 Nix 字符串、命令参数或项目仓库。

同一个 Harness home 共用凭据和会话目录，模型选择则由 profile 管理：桌面使用 `profiles/web/cordis.patch.yml`，一次性命令使用 `profiles/headless/cordis.patch.yml`，home 层 `cordis.patch.yml` 才跨 profile 生效。更改桌面默认模型不会自动同步到 headless。

本机审核时两个 profile 均已存在，分别声明 `opencode-go` / `deepseek-v4.1-flash`，provider 的凭据引用一致。此次未手工改写模型 patch 或复制密钥。已安装命令的 `headless --dump-config` 也确认最终组合选择为该 Go 模型；此结论属于配置核验，不等同于真实模型请求成功。Go 订阅能否完成当前任务仍取决于额度、端点及服务可用性。

源码与用法依据是已安装包的 `--help`、headless `startup.js`、`profile-boot` 与 credentials/default-model 文档；上游参考：[CLI](https://github.com/deepseek-ai/deepseek-harness/blob/master/apps/cli/README.md)、[官方使用指南](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/user/guide/index.md)。验证与系统应用见[本次审核](repository-audit-2026-10-20.md)。
