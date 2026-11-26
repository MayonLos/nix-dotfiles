_: {
  den.aspects.extra-tools = {
    homeManager = { pkgs, ... }: {
      home.packages = with pkgs; [
        lm_sensors
        s-tui
        nvme-cli
        smartmontools
        nvd
        bluetui
        gdu
        gparted
        newsboat
        trippy
        bind.dnsutils
      ];

      programs.newsboat = {
        enable = true;
        maxItems = 200;
        autoReload = false;
        reloadTime = 120;
        urls = [
          {
            url = "https://discourse.nixos.org/latest.rss";
            tags = [ "nixos" ];
            title = "NixOS Discourse";
          }
          {
            url = "https://lwn.net/headlines/rss";
            tags = [ "linux" ];
            title = "LWN";
          }
          {
            url = "https://www.phoronix.com/rss.php";
            tags = [ "linux" ];
            title = "Phoronix";
          }
          {
            url = "https://sspai.com/feed";
            tags = [ "tech" ];
            title = "少数派";
          }
          {
            url = "https://www.ithome.com/rss/";
            tags = [ "tech" ];
            title = "IT之家";
          }
        ];
      };
    };

    nixos = { pkgs, ... }: {
      # trip needs CAP_NET_RAW. /run/wrappers/bin is first in PATH; this
      # wrapper shadows the plain package binary.
      security.wrappers.trip = {
        source = "${pkgs.trippy}/bin/trip";
        capabilities = "cap_net_raw+ep";
        owner = "root";
        group = "root";
      };

    };
  };
}
