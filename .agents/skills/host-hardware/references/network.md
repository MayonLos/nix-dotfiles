# 网络、代理与 SSH

以下模块路径以 `modules/system/` 为前缀。
`core/network.nix` 同时信任 `Meta` 和 `Mihomo` 两个 Clash TUN 名称。
版本更换曾改变接口名；名字不匹配时 TCP 被 INPUT 丢弃而 UDP/DNS 仍通，
会表现为“代理开启后无法联网”。不要只因当前看见一个接口就删另一个。

`programs/clash.nix` 开启 serviceMode/tunMode。resolved 的 stub listener 保持默认：
Clash TUN 在隧道内劫持 DNS，不绑定 `127.0.0.53:53`。不要再把 `DNSStubListener`
设为 `no`，除非实测 Clash 占用了该地址。排查先看实际监听者，不凭 DNS 解析成功推断 TCP 正常。

`core/nix.nix` 在 nix-daemon unit 设置 `http_proxy` / `https_proxy` 为
`socks5h://localhost:7897`，并为 localhost/127.0.0.1/::1 设置 no_proxy。
这是对 Clash 的明确依赖：它停机时 daemon 下载不会自动直连。
客户端输入获取与 daemon 下载处于不同环境；终端 curl 成功不能证明两边都能下载。

历史上曾出现下载连接停滞。先区分持续下载大 NAR 与完全无流量，再按需使用：

```sh
nix build --no-link --no-write-lock-file .#nixosConfigurations.nixos-btw.config.system.build.toplevel \
  --option stalled-download-timeout 20 --option connect-timeout 10
```

先用 `nix config show --json` 筛选这两个设置确认当前值，不声称默认没有超时。
store mtime 被规范化，不能用 `find /nix/store -newermt ...` 判断构建进度；
结合进程、吞吐、构建日志判断，不因短期没出现新 store 路径认定死锁。

`services/openssh.nix` 是 socket activation，openFirewall=false、禁止密码/交互认证，
未声明用户 authorizedKeys。外部登录需要网络可达和授权 key 两项都满足；
开放端口必须属于用户请求，不作为“让配置完整”的常规修补。
主机 SSH ed25519 密钥还是 sops 解密身份，关闭/移除 sshd 前读 `sops-secrets`，
核对主机 key 的生成与恢复路径，不删除 key 来清理服务。
