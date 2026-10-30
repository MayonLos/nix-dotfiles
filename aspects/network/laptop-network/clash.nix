_: {
  # Stub listener stays at the module default. Clash TUN hijacks DNS inside
  # the tunnel; it does not bind 127.0.0.53:53. Turning the stub off left
  # resolv.conf naming an address with no listener.
  services.resolved.enable = true;
  # Clash is started and stopped by hand through mayon-clash. No proxy is
  # forced on nix-daemon: while Clash runs, TUN already captures its traffic;
  # while it is off, downloads go direct instead of failing on a dead port.
}
