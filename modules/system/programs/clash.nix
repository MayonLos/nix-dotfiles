_: {
  programs.clash-verge = {
    enable = true;
    serviceMode = true;
    tunMode = true;
  };

  # Stub listener stays at the module default. Clash TUN hijacks DNS inside
  # the tunnel; it does not bind 127.0.0.53:53. Turning the stub off left
  # resolv.conf naming an address with no listener.
  services.resolved.enable = true;
}
