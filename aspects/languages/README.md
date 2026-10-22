# 语言工具与编辑器贡献

`default.nix` 声明 Den 的 `editorLanguages` quirk，并登记语言工具支持与 Neovim 数据贡献。
只有显式选择的语言才安装其工具并贡献数据；只有选择的编辑器才消费这些贡献，schema 或数据
本身不会反向启用功能。

`data.nix` 是唯一的语言协议：按稳定语言 ID 提供 Neovim LSP server 的命令、filetypes、root
markers，以及 formatter/linter 数据。`contract.nix` 使用原生 Nix 模块类型按 ID 合并并检查冲突：
`cmd`、`root_markers` 等有序定义不能拼接，filetypes 集合会去重。Neovim production renderer
将这些数据生成到 `mayon.generated`，由 LSP、Conform 和 lint 配置消费；这里不定义第二份编辑器
配置，也不采用孤立样本 adapter。

语言功能保留各自工具链：例如 C/C++ 的 Clang/LLD/clang-tools 使用同一 `llvmPackages`，Java
提供 JDK 与 shell 选择逻辑，Python/Lua/LaTeX/MATLAB 工具按选择安装。项目 flake 继续拥有项目
依赖、SDK 版本和构建数据库，项目环境可以覆盖 PATH；本功能不创建或改写项目环境。

生产检查 `checks.editing-composition` 验证语言与编辑器组合、冲突拒绝、未选数据隔离和真实
clangd 小工作负载；`checks.neovim` 覆盖实际生成配置及编辑器行为。该验证不覆盖所有项目、交叉
编译工程或已应用桌面。每批记录见[执行记录](../../docs/history/den-execution.md)。
