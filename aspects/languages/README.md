# 所选语言向编辑器贡献数据

`default.nix` 声明 Den 的 `editorLanguages` quirk，并登记 `cpp-support` aspect。只有选择的语言才贡献数据；只有选择的编辑器才消费，不从 schema 或数据存在反向启用功能。

`cpp.nix` 选择同一 `pkgs.llvmPackages` 的 Clang、LLD、clang-tools，后者包含 clangd/clang-format。`cpp-data.nix` 提供稳定 ID `cpp` 和明确属于 Neovim 的 `neovim.servers.clangd` 数据：命令参数、文件类型及有序根标记。此处没有通用编辑器配置语言，未来其他编辑器有真实需求时再增加自己的命名适配。

`contract.nix` 的 `collect` 通过原生 Nix 模块类型先按语言 ID、再按 server 名合并和验证。相同 ID 的相同值可重复，不同 `cmd` 或 `root_markers` 明确冲突；跨语言 ID 共享同名 server 也使用同样的检查。`cmd`、根标记是不可拼接的有序值；文件类型作为集合合并去重。不用 `listToAttrs` 静默丢弃重复 ID。未声明字段或错误类型交给模块类型报错。

编辑器所属的 HM class 在同一用户 scope 读取 `{ editorLanguages, ... }`，将其传给 `neovim.nix`，由 `vim.lsp.config` 和 `vim.lsp.enable` 消费。空贡献不会启用 clangd。语言 aspect 可以单独提供构建工具，不强迫安装编辑器；反之，选择编辑器也不会自动选择 C/C++。

命令保留 `clangd` 的 PATH 查找和现有参数，根标记保留 `compile_commands.json`、`.clangd`、`CMakeLists.txt`、`.git` 的次序。项目 flake 继续拥有项目版本、依赖和构建数据库；本功能不创建或改写项目环境。样本未测试 direnv 切换和所有交叉编译工程。

`checks.nix` 在临时 C++ 工程执行实际编译检查，让 Neovim 启动 clangd、确认项目根并请求悬浮信息；另用未选择语言的编辑器 profile 验证没有启用或带入 clangd。真实笔记本现有工具清单、丰富编辑器配置和 LSP 接线尚未迁移，不能同时保留新旧 server 配置作为两套入口。
