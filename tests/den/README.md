# Den 纵向组合样本

独立求值的子 flake，用真实 NixOS / Home Manager 选项验证 shell、嵌入式和外观/默认工具/语言接口。主仓库尚未接入 Den，不导出测试主机为可部署配置，也不会激活账号或切换系统。

Den 固定为 [v0.19.0 / 37eb88c](https://github.com/denful/den/tree/37eb88ce28a9e42d5b367b967a9097030ff4f665)。nixpkgs、Home Manager、flake-parts 使用建立样本时主仓库的相同 revision；只有本目录的锁文件记录样本输入。实现通过非 flake 的相对 path input 引用 `aspects/` 下的嵌入式、外观、默认工具和语言目录，无需加载根 flake。这些输入跟随本仓库内容，提交负责固定它们，不能单独复制 `tests/den/` 就假定样本完整。Den 内部还使用其源码固定的 fetch 依赖，不能将 flake 的空 inputs 解释成没有上游依赖。

## 运行

在仓库根目录执行：

```sh
nix flake check ./tests/den --no-write-lock-file
nix eval ./tests/den#lib.composition.results --json --no-write-lock-file
nix eval ./tests/den#lib.composition.observations --json --no-write-lock-file
nix eval ./tests/den#lib.embedded.results --json --no-write-lock-file
nix eval ./tests/den#lib.embedded.observations --json --no-write-lock-file
nix eval ./tests/den#lib.contracts.results --json --no-write-lock-file
```

第一条命令构建组合报告、选中账号的真实 HM activationPackage、最终 udev 规则和工具启动检查；构建不会执行 activation。shell 报告位于 `checks.x86_64-linux.composition` 输出的 `results.json`，嵌入式报告是 `checks.x86_64-linux.embedded-composition` 输出的 JSON 文件。求值用 `--no-build` 只能检查求值，不构建用户环境。

共享接口报告为 `checks.x86_64-linux.contracts`，`contracts-home` 构建带显式应用选择的用户环境；其余共享接口检查见下表。

## 样本边界

- `fixture.nix` 显式登记定义，包含两台 x86_64-linux 测试主机、每台两个账号。
- 裸用户名 aspect 仅携带可移植身份；`user@host` aspect 拥有账号事实与功能选择，两者应组合生效。
- shell 样本绑定选择一个 `command-line` 功能。功能配置目标 HM 的 Zsh、该账号的登录 shell/测试组权限，并通过 `provides.${host.name}` 投递宿主支持。
- `shell-host-support` 是共享的具名 aspect，负责 Zsh 系统支持、测试组和一个 `/etc` 文件。测试组只用于验证授权隔离，没有实际设备权限。
- `suite.nix` 检查真实配置值，不只检查 aspect 图。

验收覆盖：未选择时无功能输出；选择 `alice@probe-a` 时其他账号和主机不变；反向选择 `bob@probe-b` 也正确；两个账号共享宿主支持时文件内容只有一份；账号授权分别生效；身份与绑定组合；同一文件的 mode 冲突被拒绝；所查 X11、display manager、Sway 开关保持关闭。

嵌入式样本在 `embedded-suite.nix`，选择真实的 [完整功能入口](../../aspects/embedded-workbench/README.md)。检查两主机/两账号、反向选择、未选隔离、共享规则贡献列表去重、移除一个使用者后共享支持仍在、与 shell 共存。新增规则包明确匹配锁定的 OpenOCD 和本地 ST-Link 规则包，不只检查数量。只有选中的账号获得工具和 `dialout`，USB 探针采用 uaccess/活动 seat 机制，不声称按绑定隔离 USB。

`embedded-home` 构建包含 ST 图形工具的完整 HM 环境；`embedded-udev` 构建最终规则（上游构建含 `udevadm verify`），检查 OpenOCD 的目标 ST-Link 规则带 uaccess、四份 ST-Link 规则均为 0660/uaccess 且别名未变、DFU 规则只有一份；`embedded-tools` 从生成的 profile 编译 Cortex-M4 ARM 对象文件，让交叉 GDB 读取符号，并启动 host GDB、OpenOCD、probe-rs、tio 的无设备查询。此对象文件只是编译检查，不是可直接烧写的固件。

最终规则检查发现原始 ST-Link 包实际使用 0666，与旧注释不同；现由本地规则包修正，同时保持 CLI 二进制与别名。兼容入口也获得该修正，但尚未应用到运行系统。

## 共享接口样本

`contracts-fixture.nix` 只提供最小 Kitty/Neovim 消费者和明确选择的 GUI 应用，不代替现有完整桌面或编辑器。`contracts-suite.nix` 验证两主机/两账号选择、数据不启用功能、默认工具不安装应用、CLI/GUI 编辑器分开、语言与编辑器独立选择、重复贡献幂等以及同语言 ID/跨 ID 的 server 冲突。

| 接口与检查 | 实际验证 |
|---|---|
| [外观](../../aspects/appearance/README.md)：`appearance-kitty`、`appearance-neovim` | Kitty 自己解析最终配置；Neovim 实际高亮和 ANSI 值；同一输入被两个消费者使用 |
| [默认工具](../../aspects/default-tools/README.md)：`default-tools-runtime` | 真实 wrapper 用 spy 程序记录参数；空格、引号、`$`、命令替换文本及空参数保真；MIME 内容和 Desktop ID 文件存在 |
| [语言](../../aspects/languages/README.md)：`language-clangd`、`language-not-selected` | 实际 C++ 编译检查、clangd 连接、项目根和 hover；未选择语言的 profile 没有启用或带入 clangd |

Kitty 检查避免优化 Python 删除 `assert`：显式错误加完成结果文件判定。另在仅含样本和四个功能目录的临时副本做负例：错误背景、删除 argv 转义、删除 LSP 启用，相关运行检查均失败。

新适配器没有与当前桌面共同启用。真实接入前须先转移 Kitty/Noctalia 的文件所有权、旧 EDITOR/MIME 声明和现有完整 Lua/LSP 接线；不能把本样本的“单写入者”断言当成已验证旧配置兼容。具体迁移前提在各接口说明中。

这里验证的是上述具体配置路径，尚未证明所有桌面入口、平台、真实硬件或上游所有作用域行为都正确。没有构建测试主机的完整系统、启动 VM、执行 HM activation、启动 ST GUI 或进行烧写/ACL 验证；GUI、项目 direnv 切换和真实主机 Den 接线仍未验证。

## 已发现并修正的接线陷阱

将共享支持直接内联在参数化功能的 `provides.${host.name}.nixos` 中，两账号选择后，`environment.etc.<name>.text` 的行内容被拼接了两次。将 provider 改为 `includes = [ den.aspects.shell-host-support ]`，共享具名 aspect 的输出才去重为一份。`sharedSupport` 断言检查完整文本，防止把“求值成功”误当成资源去重成功。

文件 `text` 允许原生模块按行贡献，不能用两段不同文本模拟单值冲突。样本使用同一文件的两个不同 `mode` 值做冲突检查，并用正常路径的 `0444` 作为对照。

另做过隔离负例：shell 初版删除 host provider 的 includes；嵌入式版分别删除 `dialout` 和宿主 provider。相关组合 derivation 均按预期因 `completeFeature` 断言失败。嵌入式负例复制 `tests/den/` 和 `aspects/embedded-workbench/` 到临时根，只修改临时副本，通过 `path:<临时根>?dir=tests/den` 保留相对输入的源根边界。

接口证据以锁定源码为准：

- [`user` 到账号的路由](https://github.com/denful/den/blob/37eb88ce28a9e42d5b367b967a9097030ff4f665/modules/aspects/batteries/os-user.nix)
- [Home Manager 集成](https://github.com/denful/den/blob/37eb88ce28a9e42d5b367b967a9097030ff4f665/modules/aspects/batteries/home-manager.nix)
- [`provides` 目标匹配](https://github.com/denful/den/blob/37eb88ce28a9e42d5b367b967a9097030ff4f665/nix/lib/aspects/fx/aspect/provide.nix)
- [裸用户与 host-qualified aspect 组合的上游测试](https://github.com/denful/den/blob/37eb88ce28a9e42d5b367b967a9097030ff4f665/templates/ci/modules/public-api/aspect-host-qualified-lookup.nix)
- [用户 schema 扩展](https://github.com/denful/den/blob/37eb88ce28a9e42d5b367b967a9097030ff4f665/templates/fleet-demo/modules/users.nix)
- [同 scope quirk 贡献与消费](https://github.com/denful/den/blob/37eb88ce28a9e42d5b367b967a9097030ff4f665/templates/ci/modules/public-api/pipes.nix)
- [锁定 HM 的 Neovim initLua](https://github.com/nix-community/home-manager/blob/32904dfe1cf86039f3c8c9f41f94e1cfd76dbb34/modules/programs/neovim/default.nix)

用户作用域裸 OS class 的行为存在上游 [#694](https://github.com/denful/den/issues/694)，本样本使用显式 provider，不把当前实现的隐式投递当作公开路由保证。
