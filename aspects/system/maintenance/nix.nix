_: {
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
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://noctalia.cachix.org"
        # Prebuilt AI coding agents from the llm-agents.nix flake input.
        "https://cache.numtide.com"
      ];
      trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
        "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      ];
      experimental-features = [
        "nix-command"
        "flakes"
      ];
    };
  };
}
