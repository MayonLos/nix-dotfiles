_: {
  networking.hostName = "nixos-btw";
  networking.networkmanager.enable = true;
  networking.firewall = {
    trustedInterfaces = [ "Mihomo" ];
    extraReversePathFilterRules = ''
      iifname { "Mihomo" } accept comment "clash tun trusted"
    '';
  };
  networking.enableIPv6 = true;

  # WiFi often associates after nm-online's 60s startup window, so this service
  # fails at boot ("Failed to start Network Manager Wait Online") and just adds a
  # red line + delay. Nothing here needs network-online.target to truly block
  # boot (docker tolerates async network; flatpak-add-flathub retries itself), so
  # disable the wait. NetworkManager.service still autostarts independently.
  systemd.services.NetworkManager-wait-online.enable = false;
}
