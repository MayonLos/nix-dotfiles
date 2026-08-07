_: {
  services.openssh = {
    enable = true;
    startWhenNeeded = true;

    # sshd stays available (socket-activated) but the port is not opened on the
    # firewall: this is a laptop that joins public networks, no key has ever been
    # authorised, and password/keyboard-interactive auth are both off — so nothing
    # could log in anyway. Set this back to true (and add
    # `users.users.mayon.openssh.authorizedKeys.keys`) when inbound SSH is wanted.
    openFirewall = false;

    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };
}
