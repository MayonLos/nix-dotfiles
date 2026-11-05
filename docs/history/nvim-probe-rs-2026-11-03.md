# Neovim：probe-rs 调试接入（2026-11-03）

基于 `f81514b`，在工作树上修改。改动是在 nvim-dap 中加入 `probe-rs-debug` 适配器和 `STM32: Flash and debug (probe-rs)` 配置（`aspects/dev/neovim/config/lua/mayon/features/debug.lua`），并由 `debug-tools.nix` 注入 probe-rs 路径。本轮没有执行 `nixos-rebuild`。

## 原因

板卡是正点原子 Mini STM32H562 + ST-Link V2。系统 OpenOCD 0.12 没有 `stm32h5x` target，原有 `STM32: Attach OpenOCD` 条目对它不可用。

用 `probe-rs gdb` 0.31 配命令行 GDB 实测：断点、`print`、改变量都正常，但 `next`/`step`/`finish` 每一两条指令就以 SIGINT 停一次；读取 `GPIOB->ODR` 需要 `set mem inaccessible-by-default off`。probe-rs 的 DAP 服务是 VS Code 插件使用的主接口，nvim-dap 可以直接对接。

## 证据

| 层级 | 内容 | 结果 |
|---|---|---|
| 单元 | `tests/debug.lua`：probe-rs 路径属于 Nix、适配器参数、配置字段、芯片名与 ELF 输入校验、`show-message` 转通知 | 通过（单独构建的 `.#neovim` 包，隔离 HOME） |
| 实机 | 用同一个包以 headless 方式加载 h562-starter 工程的 `.vscode/launch.json`，对真板子执行 `dap.run` | 下载并在复位处停下约 1.0 s；断点命中 `main`；step over 依次到 26、27 行，没有进入 HAL；Variables 中 `count = 0`，跑完一圈后 evaluate 得 1；disconnect 后无残留 probe-rs 进程，固件继续运行（`uwTick` 递增，串口持续输出 tick） |

断点停在的行报告为 `main.c:24`（`while` 行），断点设在 25 行；这是 `-Og` 下地址到行号的映射，单步行为正常。实机证据来自 headless 会话，不是交互界面截图；dap-view 面板在实机会话中的显示未单独验证。

## VS Code

同一轮在 `aspects/dev/vscode/vscode.nix` 用 `extensionFromVscodeMarketplace` 固定引入 `probe-rs.probe-rs-debugger` 0.31.0（nixpkgs 未收录；市场上的 vsix 不区分平台，要求 VS Code ≥ 1.116，锁定版本是 1.119）。该扩展从 PATH 启动 `probe-rs dap-server`，所以 `vscode-settings` 检查会断言扩展版本等于 `probe-rs-tools` 版本。项目侧的 `tasks.json` 通过 `nix develop` 编译，launch.json 中的 `preLaunchTask` 字段经 nvim-dap 传给 probe-rs 后也被接受（实机复测通过）。VS Code 界面内的 F5 会话未在本轮实测。

检查：`treefmt`、`docs`、`vscode-settings`、`neovim` 构建通过；`nix flake check --no-build` 通过；`nixos-btw` toplevel 构建成功。没有执行 `nixos-rebuild`。
