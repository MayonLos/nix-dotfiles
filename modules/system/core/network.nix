_: {
  networking = {
    hostName = "nixos-btw";
    networkmanager.enable = true;
    firewall = {
      # Clash Verge's TUN interface. verge-mihomo 1.19.x names the device
      # "Meta" by default; earlier versions used "Mihomo". When the name does
      # not match, TCP inside the TUN is dropped by the INPUT chain (UDP/DNS
      # keeps working), which shows up as "the proxy is on and now nothing
      # connects". Trust both names.
      trustedInterfaces = [
        "Meta"
        "Mihomo"
      ];
    };
    enableIPv6 = true;
  };

  systemd.services.NetworkManager-wait-online.enable = false;
}
