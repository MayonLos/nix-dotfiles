_: {
  programs.clash-verge = {
    enable = true;
    serviceMode = true;
    # The root service starts Mihomo and owns TUN (confirmed in boot logs).
    # tunMode only grants capabilities to the GUI wrapper; that makes it
    # non-dumpable, so the portal cannot inspect /proc/<pid>/root.
    tunMode = false;
  };

  # Stub listener stays at the module default. Clash TUN hijacks DNS inside
  # the tunnel; it does not bind 127.0.0.53:53. Turning the stub off left
  # resolv.conf naming an address with no listener.
  services.resolved.enable = true;
  # This laptop intentionally requires its local proxy for daemon downloads.
  systemd.services.nix-daemon.environment = {
    https_proxy = "socks5h://localhost:7897";
    http_proxy = "socks5h://localhost:7897";
    no_proxy = "localhost,127.0.0.1,::1";
  };
}
