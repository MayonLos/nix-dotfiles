_: {
  programs.clash-verge = {
    enable = true;
    serviceMode = true;
    tunMode = true;
  };

  services.resolved = {
    enable = true;
    settings = {
      Resolve = {
        # Free :53 on 127.0.0.53 for clash's TUN resolver. Note what this does
        # *not* change: NixOS still symlinks /etc/resolv.conf at
        # stub-resolv.conf, which names 127.0.0.53 regardless. Ordinary glibc
        # lookups are unaffected because enabling resolved also adds
        # `resolve [!UNAVAIL=return]` to nsswitch, so getaddrinfo goes over
        # D-Bus and never reads the file. What breaks is anything that parses
        # resolv.conf and speaks DNS itself -- static Go binaries, `dig`
        # without an explicit @server. Point those at the proxy directly.
        DNSStubListener = "no";
      };
    };
  };
}
