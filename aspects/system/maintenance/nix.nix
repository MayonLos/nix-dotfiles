{
  lib,
  ...
}:
{
  # Bound journal rotation without removing existing logs during configuration work.
  services.journald.extraConfig = ''
    SystemMaxUse=1G
  '';

  nix = {
    channel.enable = false;
    optimise.automatic = true;
    settings = {
      # NixOS supplies root trust and the official cache signing key. Keep
      # only additional keys here, avoiding duplicate generated declarations.
      keep-outputs = false;
      # The first three mirrors serve cache.nixos.org content and are signed
      # with the same key, so they need no extra trusted-public-keys entry.
      # Probed on 2026-11-23: narinfo fetches took 0.04-0.07 s (USTC), 0.16 s
      # (NJU) and 0.23-0.26 s (CERNET); Tsinghua returned 404 for every store
      # path and was left out. A path missing from one cache falls through to
      # the next substituter, ending at the official cache. Priorities are
      # ascending because a lower value is queried first.
      # force: NixOS appends cache.nixos.org with mkAfter at the default priority 0, outranking every mirror.
      substituters = lib.mkForce [
        "https://mirrors.ustc.edu.cn/nix-channels/store?priority=10"
        "https://mirrors.nju.edu.cn/nix-channels/store?priority=20"
        "https://mirrors.cernet.edu.cn/nix-channels/store?priority=30"
        "https://nix-community.cachix.org?priority=40"
        # Prebuilt AI coding agents from the llm-agents.nix flake input.
        "https://cache.numtide.com?priority=45"
        "https://cache.nixos.org?priority=50"
      ];
      trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      ];
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      # The 1 MiB default stalls large slow transfers between refills. This is
      # one shared buffer, not a per-download cost.
      download-buffer-size = 67108864;
    };
  };
}
