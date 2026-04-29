_:
{
  networking.hostName = "nixos-btw";
  networking.networkmanager.enable = true;
  networking.firewall = {
    trustedInterfaces = [ "Mihomo" ];
    extraReversePathFilterRules = ''
      iifname { "Mihomo" } accept comment "clash tun trusted"
    '';
  };
  networking.enableIPv6 = true;
}
