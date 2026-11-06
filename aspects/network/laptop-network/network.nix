_: {
  networking = {
    networkmanager.enable = true;
    enableIPv6 = true;
    # The NixOS firewall and libvirt's NAT backend (it follows this switch)
    # use nftables instead of the legacy iptables frontend.
    nftables.enable = true;
  };

  systemd.services.NetworkManager-wait-online.enable = false;
}
