_: {
  nix = {
    settings = {
      trusted-users = [
        "root"
        "mayon"
      ];
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
      # /etc/resolv.conf is a symlink chain on NixOS; the sandbox sees a dangling
      # symlink and DNS fails in FOD derivations (Nix #11004). Belt-and-suspenders
      # until the host runs Nix 2.20+.
      extra-sandbox-paths = [ "/etc/static/resolv.conf" ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };

  # nix-daemon is a separate systemd service; sudo -E does NOT pass env vars to it.
  # Set proxy here so fetches inside the daemon (substituters, FOD) go through the proxy.
  # systemd.services.nix-daemon.environment = {
  #   https_proxy = "http://127.0.0.1:7897";
  #   http_proxy = "http://127.0.0.1:7897";
  #   all_proxy = "socks5://127.0.0.1:7897";
  # };
}
