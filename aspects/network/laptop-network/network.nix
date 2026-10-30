_: {
  networking = {
    networkmanager.enable = true;
    enableIPv6 = true;
  };

  systemd.services.NetworkManager-wait-online.enable = false;
}
