{ pkgs }:
{
  # Public test hook: same seat-access rules installed by this feature.
  seatRules = import ./rules.nix { inherit pkgs; };
}
