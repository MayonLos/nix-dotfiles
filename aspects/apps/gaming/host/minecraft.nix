_: {
  # The Yet Another Bingo: Ultimate server under ~/Game is started and owned by
  # the user, not by Nix. Only its two inbound ports are declared here.
  networking.firewall.allowedTCPPorts = [ 25565 ];
  networking.firewall.allowedUDPPorts = [ 24454 ];
}
