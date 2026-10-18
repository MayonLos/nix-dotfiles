# Den 纵向组合样本

独立子 flake，用真实 NixOS / Home Manager 选项验证新架构的第一条路径。主仓库尚未接入 Den，不导出测试主机为可部署配置，也不会激活账号或切换系统。

Den 固定为 [v0.19.0 / 37eb88c](https://github.com/denful/den/tree/37eb88ce28a9e42d5b367b967a9097030ff4f665)。nixpkgs、Home Manager、flake-parts 使用建立样本时主仓库的相同 revision；只有本目录的锁文件记录样本输入。Den 内部还使用其源码固定的 fetch 依赖，不能将 flake 的空 inputs 解释成没有上游依赖。

## 运行

在仓库根目录执行：

```sh
nix flake check ./tests/den --no-write-lock-file
nix eval ./tests/den#lib.composition.results --json --no-write-lock-file
nix eval ./tests/den#lib.composition.observations --json --no-write-lock-file
```

第一条命令同时构建组合报告和选中账号的真实 HM activationPackage；构建不会执行 activation。报告位于 `checks.x86_64-linux.composition` 输出的 `results.json`。求值用 `--no-build` 只能检查求值，不构建用户环境。

## 样本边界

- `fixture.nix` 显式登记定义，包含两台 x86_64-linux 测试主机、每台两个账号。
- 裸用户名 aspect 仅携带可移植身份；`user@host` aspect 拥有账号事实与功能选择，两者应组合生效。
- 绑定只选择一个 `command-line` 功能。功能配置目标 HM 的 Zsh、该账号的登录 shell/测试组权限，并通过 `provides.${host.name}` 投递宿主支持。
- `shell-host-support` 是共享的具名 aspect，负责 Zsh 系统支持、测试组和一个 `/etc` 文件。测试组只用于验证授权隔离，没有实际设备权限。
- `suite.nix` 检查真实配置值，不只检查 aspect 图。

验收覆盖：未选择时无功能输出；选择 `alice@probe-a` 时其他账号和主机不变；反向选择 `bob@probe-b` 也正确；两个账号共享宿主支持时文件内容只有一份；账号授权分别生效；身份与绑定组合；同一文件的 mode 冲突被拒绝；所查 X11、display manager、Sway 开关保持关闭。

这里验证的是上述具体配置路径，尚未证明所有桌面入口、平台、真实硬件或上游所有作用域行为都正确。没有构建测试主机的完整系统、启动 VM、执行 HM activation，或测试现有桌面的运行行为。嵌入式设备、外观、默认工具、语言协议和真实主机迁移仍待后续阶段验证。

## 已发现并修正的接线陷阱

将共享支持直接内联在参数化功能的 `provides.${host.name}.nixos` 中，两账号选择后，`environment.etc.<name>.text` 的行内容被拼接了两次。将 provider 改为 `includes = [ den.aspects.shell-host-support ]`，共享具名 aspect 的输出才去重为一份。`sharedSupport` 断言检查完整文本，防止把“求值成功”误当成资源去重成功。

文件 `text` 允许原生模块按行贡献，不能用两段不同文本模拟单值冲突。样本使用同一文件的两个不同 `mode` 值做冲突检查，并用正常路径的 `0444` 作为对照。

另做过隔离负例：复制这四个 Nix/lock 文件到临时目录，删除 host provider 的 includes；组合 derivation 求值按预期因 `completeFeature` 断言失败。该负例只修改临时副本。

接口证据以锁定源码为准：

- [`user` 到账号的路由](https://github.com/denful/den/blob/37eb88ce28a9e42d5b367b967a9097030ff4f665/modules/aspects/batteries/os-user.nix)
- [Home Manager 集成](https://github.com/denful/den/blob/37eb88ce28a9e42d5b367b967a9097030ff4f665/modules/aspects/batteries/home-manager.nix)
- [`provides` 目标匹配](https://github.com/denful/den/blob/37eb88ce28a9e42d5b367b967a9097030ff4f665/nix/lib/aspects/fx/aspect/provide.nix)
- [裸用户与 host-qualified aspect 组合的上游测试](https://github.com/denful/den/blob/37eb88ce28a9e42d5b367b967a9097030ff4f665/templates/ci/modules/public-api/aspect-host-qualified-lookup.nix)

用户作用域裸 OS class 的行为存在上游 [#694](https://github.com/denful/den/issues/694)，本样本使用显式 provider，不把当前实现的隐式投递当作公开路由保证。
