{ pkgs, ... }:

# Accounts and credentials are configured interactively, not in the Nix store.
{
  programs.thunderbird = {
    enable = true;
    package = pkgs.thunderbird;
  };
}
