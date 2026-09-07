{ config, ... }:
let
  # Clash Verge's mixed port. See networking.firewall.trustedInterfaces in
  # ./network.nix for the TUN side of the same proxy.
  daemonProxy = "socks5h://localhost:7897";
in
{
  nix = {
    channel.enable = false;
    optimise.automatic = true;
    settings = {
      trusted-users = [
        "root"
        "mayon"
      ];
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://noctalia.cachix.org"
        # Prebuilt AI coding agents from the llm-agents.nix flake input.
        "https://cache.numtide.com"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
        "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      ];
      experimental-features = [
        "nix-command"
        "flakes"
      ];
    };

    # The GitHub token must not be in nix.settings — modules are world-readable
    # in /nix/store. sops renders it at runtime; "!include" (as opposed to
    # "include") tolerates the file being absent, so nix still works on a fresh
    # boot before sops-nix activation has run.
    extraOptions = ''
      !include ${config.sops.templates."nix-access-tokens.conf".path}
    '';
  };

  # Substituter and tarball downloads run inside nix-daemon, a system service
  # that inherits nothing from the user's shell, so the proxy that makes
  # cache.nixos.org reachable here has to be set on the unit itself. The client
  # side is separate: flake input fetches happen in the `nix` process and read
  # the user environment.
  #
  # This hard-depends on Clash listening on that port. With it down, daemon-side
  # downloads fail outright instead of falling back to a direct connection --
  # that is the trade for them not timing out one by one when it is up.
  systemd.services.nix-daemon.environment = {
    https_proxy = daemonProxy;
    http_proxy = daemonProxy;
    # socks5h hands name resolution to the proxy too, so loopback has to be
    # excluded explicitly or a local substituter would hairpin through Clash.
    no_proxy = "localhost,127.0.0.1,::1";
  };
}
