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
        DNSStubListener = "no";
      };
    };
  };
}
