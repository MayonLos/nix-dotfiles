_: {
  services.openssh = {
    enable = true;
    startWhenNeeded = true;
    # There are no authorized inbound keys on this laptop. Preserve the local
    # socket endpoint without listening on Wi-Fi, Ethernet or the trusted TUN.
    listenAddresses = [
      { addr = "127.0.0.1"; }
      { addr = "[::1]"; }
    ];

    # sshd stays available (socket-activated) but the port is not opened on the
    # firewall: this is a laptop that joins public networks, no key has ever been
    # authorised, and password/keyboard-interactive auth are both off — so nothing
    # could log in anyway. To enable inbound SSH, change listenAddresses,
    # set this back to true (and add
    # `users.users.mayon.openssh.authorizedKeys.keys`) when inbound SSH is wanted.
    openFirewall = false;

    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };
}
