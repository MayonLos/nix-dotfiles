# keys-mayon

安装 `pkgs.mayonTui.tools` 提供的 `mayon-tools keys` 快捷键速查。输入为 Mango
功能从最终合并的 `wayland.windowManager.mango.settings` 生成的
`$XDG_CONFIG_HOME/keys-mayon/bindings.json`（默认 `~/.config`）。
此 feature 只安装命令，不选择桌面、不拥有其他配置或用户状态。
移除后命令消失，无运行时状态需要清理；JSON 由 Mango feature 拥有。

程序与公开包工厂见 [packages/mayon-tui/crates/keys](../../../packages/mayon-tui/crates/keys/README.md)。
`checks.nix` 为显式登记的检查入口，逐行核对 JSON 与 HM 实际生成的
`mango/config.conf` 的模式、类型和原始动作，并检查命令输出。
