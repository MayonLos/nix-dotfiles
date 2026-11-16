_: {
  den.aspects.extra-tools = _: {
    homeManager = { pkgs, ... }: {
      # Installation only: no service, daemon, activation or application config.
      home.packages = with pkgs; [
        lm_sensors
        s-tui
        nvme-cli
        smartmontools
        nvd
        argyllcms
        bluetui
        gdu
        newsboat
        trippy
        bind.dnsutils
        restic
        keepassxc
      ];
    };
  };
}
