{ pkgs, ... }:

# Accounts and credentials are configured interactively, not in the Nix store.
{
  programs.thunderbird = {
    enable = true;
    # nixpkgs' wrapThunderbird delegates to wrapFirefox, which supports
    # package-level autoconfig preferences without claiming any user profile.
    package = pkgs.thunderbird.override {
      extraPrefs = ''
        lockPref("widget.use-xdg-desktop-portal.file-picker", 1);
      '';
    };
  };
}
