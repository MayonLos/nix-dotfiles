_: {
  networking.hostName = "nixos-btw";
  networking.networkmanager.enable = true;
  networking.firewall = {
    # Clash Verge 的 TUN 网卡。verge-mihomo 1.19.x 默认把设备命名为 "Meta"，
    # 早期版本叫 "Mihomo"；名字对不上时 TUN 里的 TCP 会被 INPUT 链丢掉
    # （UDP/DNS 仍然正常），表现为「开了代理反而连不上」。两个名字都放行。
    trustedInterfaces = [
      "Meta"
      "Mihomo"
    ];
  };
  networking.enableIPv6 = true;
  systemd.services.NetworkManager-wait-online.enable = false;
}
